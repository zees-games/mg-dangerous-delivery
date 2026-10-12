#!/usr/bin/env bash
# The chase camera down every road, armed: exit 1 if it ends inside the mountain on any frame
# or if no frame would have been inside without the probe. --render draws each route's worst
# frame before and after (screenshots/cameras/).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--render" ]; then
  exec timeout 900 xvfb-run -a "${GODOT:-godot}" --path . --resolution 1280x720 res://tools/camera_check.tscn -- --render
fi
exec timeout 900 "${GODOT:-godot}" --headless --path . res://tools/camera_check.tscn
