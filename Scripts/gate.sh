#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== disk =="
df -h . | tail -1

echo "== toolchain =="
swift --version | head -1
xcodebuild -version | head -2

echo "== lockfile =="
python3 - <<'PY'
import json
from pathlib import Path
resolved = json.loads(Path("Package.resolved").read_text())
pins = resolved["pins"] if "pins" in resolved else resolved.get("object", {}).get("pins", [])
found = None
for pin in pins:
    identity = pin.get("identity") or pin.get("package")
    if identity and "swiftagent" in identity.lower():
        found = pin
        break
if not found:
    raise SystemExit("SwiftAgent pin missing from Package.resolved")
state = found.get("state", {})
revision = state.get("revision") or ""
version = state.get("version") or ""
print(f"SwiftAgent version={version} revision={revision}")
if revision != "d5383a26849f45d8a442c24aebfb0b7ca4798dd5":
    raise SystemExit(f"unexpected SwiftAgent revision {revision}")
if version != "1.0.0-rc.3":
    raise SystemExit(f"unexpected SwiftAgent version {version}")
print("lockfile OK")
PY

echo "== unit tests =="
swift test --disable-sandbox --parallel

echo "== macOS build =="
xcodebuild -project OtohaChat.xcodeproj -scheme OtohaChat -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

echo "== iOS Simulator build =="
xcodebuild -project OtohaChat.xcodeproj -scheme OtohaChat-iOS -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

echo "gate OK"
