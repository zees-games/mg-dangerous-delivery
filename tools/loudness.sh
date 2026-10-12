#!/usr/bin/env bash
# Record the game's mix while a stand-in drives, and measure it: integrated loudness (LUFS),
# loudness range and true peak, ffmpeg's EBU R128 meter.
#
#   tools/loudness.sh                                   # Snowline in snow and wind, 20 s
#   tools/loudness.sh --route=dd_river_cut --sky=rain
#
# xvfb-run for a real audio driver (see tools/loudness.gd), --fixed-fps so the recording is the
# simulated seconds asked for.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp --suffix=.wav)"
trap 'rm -f "$out"' EXIT
timeout 300 xvfb-run -a "${GODOT:-godot}" --fixed-fps 60 --path . --resolution 640x360 \
    res://tools/loudness.tscn -- "--out=$out" "$@" | grep -E '^driver=|^buses' || true
ffmpeg -nostats -i "$out" -af ebur128=peak=true -f null - 2>&1 | sed -n '/Summary/,$p' | grep -E 'I:|LRA:|Peak:'
