"""Decode the delivered assets and verify real samples, headroom and loop seams."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / "assets" / "audio"
manifest = json.loads((AUDIO / "manifest.json").read_text(encoding="utf-8"))
results = []
for relative, meta in manifest["assets"].items():
    data = subprocess.run(["ffmpeg", "-v", "error", "-i", str(AUDIO / relative),
                           "-f", "f32le", "-acodec", "pcm_f32le", "-"],
                          check=True, capture_output=True).stdout
    samples = np.frombuffer(data, dtype="<f4").reshape(-1, 2)
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples * samples)))
    seam = float(np.max(np.abs(samples[0] - samples[-1])))
    duration = len(samples) / 44100
    success = 0 < rms and peak < .99 and abs(duration - meta["duration_seconds"]) < .02
    if meta["loop"]:
        # The noise bed can naturally change faster than a tonal music sample.
        success = success and seam < (.10 if meta["category"] == "ambience" else .04)
    if meta["category"] == "music":
        success = success and 119.9 <= duration <= 180
    results.append({"file": relative, "passed": bool(success), "duration": round(duration, 4),
                    "decoded_peak": round(peak, 5), "rms": round(rms, 5), "loop_seam": round(seam, 5)})
output = ROOT / ".godot" / "audio-validation.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
failed = [item for item in results if not item["passed"]]
for item in results:
    print(item)
print(f"AUDIO SIGNAL: {len(results)} checks, {len(failed)} failures")
raise SystemExit(bool(failed))
