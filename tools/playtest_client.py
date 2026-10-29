"""Send one real-input command to the optional Godot playtest bridge."""
import argparse
import json
import sys
import time
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8")

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("action", choices=["state", "button", "click", "key", "text", "wheel", "wait", "resize", "quit"])
parser.add_argument("--text")
parser.add_argument("--key")
parser.add_argument("--ctrl", action="store_true")
parser.add_argument("--shift", action="store_true")
parser.add_argument("--x", type=float)
parser.add_argument("--y", type=float)
parser.add_argument("--direction", type=int)
parser.add_argument("--width", type=int)
parser.add_argument("--height", type=int)
parser.add_argument("--seconds", type=float)
parser.add_argument("--no-capture", action="store_true")
parser.add_argument("--full", action="store_true")
parser.add_argument("--expect-exit", action="store_true", help="Send an in-game exit button command without waiting for a response from the terminating process.")
args = parser.parse_args()
folder = Path(__file__).resolve().parents[1] / ".godot" / "live-playtest"
command = {k: v for k, v in vars(args).items() if v is not None and k not in ("no_capture", "full", "expect_exit")}
command["id"] = str(time.time_ns())
command["capture"] = not args.no_capture
temporary = folder / "command.tmp"
temporary.write_text(json.dumps(command, ensure_ascii=False), encoding="utf-8")
temporary.replace(folder / "command.json")
if args.expect_exit:
    print("Exit input sent; verify the Godot process exit code and its log.")
    raise SystemExit(0)
deadline = time.monotonic() + 45
while time.monotonic() < deadline:
    try:
        response = json.loads((folder / "response.json").read_text(encoding="utf-8"))
        if response.get("id") == command["id"]:
            if args.full:
                print(json.dumps(response, ensure_ascii=False))
            else:
                state = response.get("state", {})
                summary = {k: v for k, v in state.items() if k not in ("controls", "buildings", "audio")}
                summary["controls"] = [{k: c[k] for k in ("text", "type", "x", "y", "width", "height", "disabled", "value") if k in c} for c in state.get("controls", [])][:45]
                print(json.dumps({"error": response.get("error"), "screenshot": response.get("screenshot"), "state": summary}, ensure_ascii=False, indent=2))
            break
    except (OSError, json.JSONDecodeError):
        pass
    time.sleep(0.05)
else:
    raise SystemExit("The Godot playtest bridge did not respond within 45 seconds.")
