#!/usr/bin/env bash
# Dangerous Delivery's on-box visual QA capture (docs/testing.md): gs-game's shot tool runs tools/visual_qa.gd.
# Driven by addons/gs_game/tools/gs_game_visual_qa.sh --shot tools/visual_qa_shot.sh; extra args go to the script.
exec bash "$(dirname "$0")/../addons/gs_game/tools/gs_game_visual_qa_shot.sh" --script tools/visual_qa.gd -- "$@"
