#!/usr/bin/env bash
# Dangerous Delivery's on-box visual QA capture (docs/testing.md): dot-game's shot tool runs tools/visual_qa.gd.
# Driven by addons/dot_game/tools/dot_game_visual_qa.sh --shot tools/visual_qa_shot.sh; extra args go to the script.
exec bash "$(dirname "$0")/../addons/dot_game/tools/dot_game_visual_qa_shot.sh" --script tools/visual_qa.gd -- "$@"
