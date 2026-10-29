"""Rebuild Tidal Grid's original score and sound library without downloaded samples.

Requires the bundled Python's numpy and ffmpeg on PATH.  All notes, orchestration,
noise beds and effects are authored below; the piano is an additive synthetic
instrument, not a recording. Run from any directory with --output PATH optional.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

RATE = 44100
ROOT = Path(__file__).resolve().parents[2]
RNG = np.random.default_rng(291026)
NOTE_CACHE: dict[tuple, np.ndarray] = {}
MANIFEST: dict[str, dict] = {}


def note(midi: int, duration: float, voice: str = "piano") -> np.ndarray:
    key = (midi, round(duration, 4), voice)
    if key in NOTE_CACHE:
        return NOTE_CACHE[key]
    t = np.arange(round(duration * RATE), dtype=np.float32) / RATE
    f = 440.0 * 2 ** ((midi - 69) / 12)
    y = np.zeros_like(t)
    if voice == "piano":
        # A soft felt-piano-like additive tone: quicker upper-partial decay,
        # gentle inharmonicity, no borrowed samples or imitation recordings.
        for harmonic, level in enumerate([1, .30, .19, .10, .055, .033, .018], 1):
            stretch = 1 + .000035 * harmonic * harmonic
            decay = math.exp((60 - midi) / 55) * (1.4 / (1 + harmonic * .20))
            y += level * np.sin(2 * np.pi * f * harmonic * stretch * t) * np.exp(-t / decay)
        y *= 1 - np.exp(-t * 220)
        y *= np.minimum(1, np.maximum(0, (duration - t) / .22))
        y *= .43
    elif voice == "pad":
        for detune, level in [(-.0013, .32), (0, .45), (.0013, .32)]:
            y += level * np.sin(2 * np.pi * f * (1 + detune) * t)
            y += .07 * np.sin(2 * np.pi * f * 2 * (1 + detune) * t)
        y *= np.minimum(1, t / .6) * np.minimum(1, np.maximum(0, (duration - t) / .8)) * .32
    elif voice == "bass":
        y = (np.sin(2 * np.pi * f * t) + .16 * np.sin(2 * np.pi * f * 2 * t))
        y *= (1 - np.exp(-t * 60)) * np.exp(-t / 1.1)
        y *= np.minimum(1, np.maximum(0, (duration - t) / .15)) * .45
    elif voice == "bell":
        y = np.sin(2 * np.pi * f * t) * np.exp(-t / .65)
        y += .13 * np.sin(2 * np.pi * f * 2.008 * t) * np.exp(-t / .18)
        y *= (1 - np.exp(-t * 140)) * np.minimum(1, np.maximum(0, (duration - t) / .08)) * .3
    elif voice == "pluck":
        y = (np.sin(2 * np.pi * f * t) + .18 * np.sin(2 * np.pi * f * 3 * t))
        y *= (1 - np.exp(-t * 240)) * np.exp(-t / .16) * .26
    result = y.astype(np.float32)
    NOTE_CACHE[key] = result
    return result


def place(mix: np.ndarray, sound: np.ndarray, start: float, gain: float = 1,
          pan: float = 0, wrap: bool = True) -> None:
    offset = int(round(start * RATE)) % len(mix)
    count = len(sound)
    stereo = np.asarray([math.sqrt((1 - pan) * .5), math.sqrt((1 + pan) * .5)], np.float32)
    cursor = 0
    while cursor < count:
        available = min(count - cursor, len(mix) - offset)
        mix[offset:offset + available] += sound[cursor:cursor + available, None] * stereo * gain
        cursor += available
        if not wrap:
            break
        offset = 0


def reverb(mix: np.ndarray, amount: float = .20) -> np.ndarray:
    dry = mix.copy()
    for delay, level in [(.097, .42), (.173, .28), (.283, .20), (.419, .14), (.613, .08)]:
        shift = round(delay * RATE)
        mix += np.roll(dry[:, ::-1], shift, axis=0) * (amount * level)
    return mix


def export(path: Path, samples: np.ndarray, category: str, loop: bool = False,
           description: str = "", metadata: dict | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    samples = np.asarray(samples, np.float32)
    if samples.ndim == 1:
        samples = np.column_stack([samples, samples])
    samples -= np.mean(samples, axis=0)
    peak = float(np.max(np.abs(samples)))
    if peak > 0:
        samples *= .72 / peak
    if not loop:
        edge = min(round(RATE * .012), len(samples) // 4)
        samples[:edge] *= np.linspace(0, 1, edge, dtype=np.float32)[:, None]
        samples[-edge:] *= np.linspace(1, 0, edge, dtype=np.float32)[:, None]
    pcm = np.round(np.clip(samples, -1, 1) * 32767).astype("<i2")
    temporary_root = ROOT / ".godot" / "audio-build"
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="tidal-audio-", dir=temporary_root) as temp:
        wav_path = Path(temp) / "source.wav"
        with wave.open(str(wav_path), "wb") as output:
            output.setnchannels(2)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(pcm.tobytes())
        if path.suffix == ".ogg":
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav_path),
                            "-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1", str(path)], check=True)
        else:
            shutil.copyfile(wav_path, path)
    seam = float(np.max(np.abs(samples[0] - samples[-1])))
    MANIFEST[str(path.relative_to(OUTPUT)).replace("\\", "/")] = {
        "category": category, "description": description, "loop": loop,
        "duration_seconds": round(len(samples) / RATE, 4), "sample_rate": RATE,
        "channels": 2, "peak_dbfs": round(20 * math.log10(max(1e-10, float(np.max(np.abs(samples))))), 3),
        "loop_boundary_delta": round(seam, 6) if loop else None,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), **(metadata or {})}
    print(f"{path.name}: {len(samples)/RATE:.1f}s", flush=True)


PROGRESSIONS = {
    "title": [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 57, 59, 62], [45, 52, 57, 62, 64],
              [52, 59, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 57, 62, 66], [45, 52, 57, 61, 64]],
    "day": [[43, 50, 55, 59, 62], [40, 47, 55, 59, 62], [48, 55, 60, 64, 67], [50, 57, 62, 66, 69],
            [45, 52, 57, 60, 64], [40, 47, 55, 59, 62], [48, 55, 60, 64, 67], [50, 57, 62, 64, 69]],
    "night": [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 57, 62, 66], [45, 52, 57, 62, 64],
              [52, 59, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 57, 59, 62], [45, 52, 57, 61, 64]],
    "campaign": [[45, 52, 57, 60, 64], [48, 55, 60, 64, 67], [43, 50, 55, 59, 62], [50, 57, 62, 65, 69],
                 [41, 48, 53, 57, 60], [48, 55, 60, 64, 67], [43, 50, 55, 59, 62], [45, 52, 57, 60, 64]],
    "storm": [[40, 47, 52, 55, 59], [36, 43, 48, 52, 55], [43, 50, 55, 59, 62], [38, 45, 50, 54, 57],
              [40, 47, 52, 55, 59], [36, 43, 48, 52, 55], [45, 52, 57, 60, 64], [47, 54, 59, 62, 66]],
}


def music(name: str) -> None:
    bpm = {"title": 84, "day": 80, "night": 72, "campaign": 88, "storm": 96}[name]
    beat = 60 / bpm
    duration = 48 * 4 * beat
    mix = np.zeros((round(duration * RATE), 2), np.float32)
    progression = PROGRESSIONS[name]
    for bar in range(48):
        chord = progression[bar % 8]
        cycle = bar // 8
        start = bar * 4 * beat
        openness = [.72, .88, .70, .95, .76, .85][cycle]
        # Sustained warm chords sit beneath a deliberately quiet piano score.
        for index, pitch in enumerate(chord[1:]):
            place(mix, note(pitch, 4 * beat + .8, "pad"), start, .10 * openness,
                  -.55 + index * .32)
        place(mix, note(chord[0], 2.3 * beat, "bass"), start, .29 * openness)
        if name != "night":
            place(mix, note(chord[0] + (12 if bar % 4 == 3 else 7), 1.4 * beat, "bass"),
                  start + 2.5 * beat, .13)
        pattern = [1, 2, 3, 4, 2, 3] if name != "storm" else [1, 2, 3, 2, 4, 3, 2, 3]
        positions = [0, .75, 1.5, 2, 2.75, 3.5] if name != "storm" else [0, .5, 1, 1.5, 2, 2.5, 3, 3.5]
        if name == "night":
            pattern, positions = [1, 3, 4], [0, 1.5, 3]
        for index, (chord_index, position) in enumerate(zip(pattern, positions)):
            pitch = chord[chord_index] + (12 if cycle in [2, 4] and index % 3 == 0 else 0)
            place(mix, note(pitch, 2.8, "piano"), start + position * beat,
                  (.35 if name == "night" else .39) * openness * (1 if index % 2 == 0 else .8),
                  -.3 if index % 2 == 0 else .25)
        # The rising-tide four-note motif recurs with rests and inversions,
        # rather than a constant eight-bar loop pasted for two minutes.
        if bar % 4 in [0, 2] and not (name == "night" and cycle % 2):
            melody = [chord[2] + 12, chord[3] + 12, chord[4] + 12, chord[3] + 12]
            if cycle in [2, 4]:
                melody = [melody[2], melody[1], melody[0], melody[1]]
            for index, pitch in enumerate(melody):
                place(mix, note(pitch, 2.5, "piano"), start + (index * .75 + .25) * beat,
                      .32 * openness, .12)
        if name in ["day", "title", "campaign"] and cycle not in [0, 2]:
            for index in [0, 2, 3]:
                place(mix, note(chord[2 + index % 3] + 12, 1.1, "pluck"),
                      start + (index + .5) * beat, .12, -.5 if index % 2 else .5)
        if name == "storm":
            pulse_t = np.arange(round(.25 * RATE), dtype=np.float32) / RATE
            pulse = np.sin(2 * np.pi * (58 * pulse_t + 23 * pulse_t * np.exp(-pulse_t * 22)))
            pulse *= np.exp(-pulse_t * 22) * (1 - np.exp(-pulse_t * 600))
            for position in [0, 1.5, 2, 3.5]:
                place(mix, pulse, start + position * beat, .11)
    reverb(mix, .30 if name == "night" else .22)
    export(OUTPUT / "music" / f"{name}.ogg", mix, "music", True,
           f"Original warm synthetic piano and light electronic score: {name}",
           {"bpm": bpm, "bars": 48, "instrument": "original additive synthetic piano, pads, bass and plucks"})
    NOTE_CACHE.clear()


def noise(seconds: float, low: float, high: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    count = round(seconds * RATE)
    frequencies = np.fft.rfftfreq(count, 1 / RATE)
    spectrum = rng.normal(size=len(frequencies)) + 1j * rng.normal(size=len(frequencies))
    weight = np.zeros_like(frequencies)
    mask = (frequencies >= low) & (frequencies <= high)
    weight[mask] = 1 / np.sqrt(np.maximum(60, frequencies[mask]))
    spectrum *= weight
    spectrum[0] = 0
    y = np.fft.irfft(spectrum, n=count).astype(np.float32)
    y /= max(1e-6, float(np.max(np.abs(y))))
    return y


def ambience(name: str, seed: int) -> None:
    seconds = 16.0
    t = np.arange(round(seconds * RATE), dtype=np.float32) / RATE
    mix = np.zeros((len(t), 2), np.float32)
    for channel in range(2):
        wash = noise(seconds, 80 if name == "storm" else 130, 9000, seed + channel)
        wind = noise(seconds, 50, 1000, seed + 3 + channel)
        swell = .55 + .2 * np.sin(2 * np.pi * 2 * t / seconds + channel * .35)
        swell += .12 * np.sin(2 * np.pi * 5 * t / seconds)
        mix[:, channel] = wash * swell * (.47 if name == "storm" else .24) + wind * .17
    if name == "night":
        for index in range(7):
            at = index * 2.0 + .6
            chirp_t = np.arange(round(.16 * RATE), dtype=np.float32) / RATE
            chirp = np.sin(2 * np.pi * 3400 * chirp_t) * np.sin(np.pi * chirp_t / .16) ** 2
            place(mix, chirp, at, .015, -.6 if index % 2 else .6)
    if name == "coast":
        # Distant stylized shorebird calls, deliberately below the wave bed.
        for at, pan in [(3.2, -.65), (10.1, .6)]:
            call_t = np.arange(round(.8 * RATE), dtype=np.float32) / RATE
            phase = 2 * np.pi * (820 * call_t + 25 * np.sin(call_t * 5))
            call = np.sin(phase) * np.sin(np.pi * call_t / .8) ** 2
            place(mix, call, at, .012, pan)
    export(OUTPUT / "ambience" / f"{name}.ogg", mix, "ambience", True,
           f"Original cyclic noise synthesis: {name} coastal soundscape")


def facility(name: str, seed: int) -> None:
    seconds = 8.0
    t = np.arange(round(seconds * RATE), dtype=np.float32) / RATE
    fundamental = {"turbine": 75, "thermal": 62.5, "hydro": 50, "transformer": 100,
                   "digital": 150, "storage": 125, "city": 87.5}[name]
    bed = noise(seconds, 50, 2500 if name in ["turbine", "hydro"] else 950, seed) * .08
    bed += .07 * np.sin(2 * np.pi * fundamental * t)
    bed += .018 * np.sin(2 * np.pi * fundamental * 2 * t)
    bed *= .8 + .12 * np.sin(2 * np.pi * t / seconds)
    mix = np.column_stack([bed, np.roll(bed, 61)])
    export(OUTPUT / "facilities" / f"{name}.ogg", mix, "facility", True,
           f"Subtle original machinery family loop: {name}")


def short_score(name: str, notes: list[int], duration: float, voice: str = "piano") -> None:
    mix = np.zeros((round(duration * RATE), 2), np.float32)
    spacing = min(.28, (duration - 1) / max(1, len(notes)))
    for index, pitch in enumerate(notes):
        place(mix, note(pitch, min(2, duration - spacing * index), voice), spacing * index,
              .5 if name != "failure" else .34, -.2 + .4 * (index % 2), False)
    reverb(mix, .2)
    export(OUTPUT / "stingers" / f"{name}.wav", mix, "stinger", False,
           "Original rising-tide theme variation: " + name)


def effect(name: str, pitches: list[int], duration: float, texture: float = 0, seed: int = 0) -> None:
    mix = np.zeros((round(duration * RATE), 2), np.float32)
    for index, pitch in enumerate(pitches):
        place(mix, note(pitch, max(.08, duration - index * .065), "bell" if name not in ["demolish", "disabled", "rejected"] else "bass"),
              index * .065, .4, 0, False)
    if texture:
        n = noise(duration, 90, 4500, seed)
        t = np.arange(len(n), dtype=np.float32) / RATE
        n *= np.exp(-t * (8 if name != "thunder" else .8)) * (1 - np.exp(-t * 200))
        mix += n[:, None] * texture
    export(OUTPUT / "sfx" / f"{name}.wav", mix, "sfx", False, "Original synthesized interaction: " + name)


def main() -> None:
    for name in PROGRESSIONS:
        music(name)
    for index, name in enumerate(["coast", "night", "storm"]):
        ambience(name, 300 + index * 10)
    for index, name in enumerate(["turbine", "thermal", "hydro", "transformer", "digital", "storage", "city"]):
        facility(name, 400 + index)
    for name, pitches, duration in [
        ("chapter", [62, 66, 69, 74], 3.1), ("objective", [66, 69, 74], 2.4),
        ("victory", [62, 66, 69, 74, 78, 81], 4.5), ("failure", [64, 62, 59, 57], 3.6),
        ("recovery", [57, 62, 66, 69], 2.8)]:
        short_score(name, pitches, duration)
    effects = {
        "hover": ([88], .09, 0), "confirm": ([74, 81], .23, 0), "cancel": ([74, 69], .21, 0),
        "disabled": ([45, 44], .22, .035), "select": ([81], .16, 0), "build": ([50, 62, 69], .5, .12),
        "connect": ([62, 69, 74], .42, .025), "demolish": ([43, 38], .65, .22),
        "queued": ([69, 74], .35, 0), "executed": ([74, 78, 81], .45, 0),
        "rejected": ([45, 42], .35, .045), "save": ([69, 74, 78], .36, 0),
        "load": ([78, 74, 69], .4, 0), "repair": ([57, 62, 69], .65, .05),
        "toggle": ([76], .14, .015), "research": ([62, 66, 69, 74], .65, 0),
        "warning": ([74, 69], .8, 0), "critical": ([69, 69, 65], .9, 0),
        "outage": ([57, 54], .7, 0), "storm_warning": ([62, 59, 57], 1.1, 0),
        "thunder": ([28], 4.8, .8),
    }
    for index, (name, (pitches, duration, texture)) in enumerate(effects.items()):
        effect(name, pitches, duration, texture, 500 + index)
    manifest = {
        "title": "Tidal Grid original audio library", "version": 1, "license": "Project-original; no third-party audio or sample licenses required.",
        "authorship": "Original deterministic composition and signal synthesis; no external recordings, samples, or generated-model audio.",
        "piano_notice": "The warm piano-like voice is an additive synthetic instrument, not a real piano recording.",
        "rebuild": "python tools/audio/build_audio.py", "assets": MANIFEST,
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(MANIFEST)} original assets in {OUTPUT}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "assets" / "audio")
    OUTPUT = parser.parse_args().output.resolve()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    main()
