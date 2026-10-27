#!/usr/bin/env bash
# Renders a battered truck (tools/crash_shot.gd) to screenshots/crash.png, or --out=.
set -euo pipefail
cd "$(dirname "$0")/.."
exec timeout 300 xvfb-run -a "${GODOT:-godot}" --path . --resolution 1280x720 res://tools/crash_shot.tscn -- "$@"
