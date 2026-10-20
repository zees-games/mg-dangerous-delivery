#!/usr/bin/env bash
# Renders a battered truck (tools/damage_shot.gd) to screenshots/damage.png, or --out=.
set -euo pipefail
cd "$(dirname "$0")/.."
exec timeout 300 xvfb-run -a "${GODOT:-godot}" --path . --resolution 1280x720 res://tools/damage_shot.tscn -- "$@"
