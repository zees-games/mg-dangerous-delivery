#!/usr/bin/env bash
# Render the game and look at it. The check no assertion in this repository makes.
#
#   tools/shot.sh                                         # on foot in the lot, behind the player
#   tools/shot.sh --action emote dance                   # the local player on foot, third person, playing an avatar action (action_a/_b.png)
#   tools/shot.sh --people=6                              # with six more people walking round the lot
#   tools/shot.sh --view=workbench                         # the F9 tuning panel (offline client)
#   tools/shot.sh --panel                                 # the lot's panel open (G)
#   tools/shot.sh --view=far --people=4                   # the lot from high over its south fence
#   tools/shot.sh --view=seller [--truck=semi]            # beside a salesperson: what E does
#   tools/shot.sh --view=roam --seconds=4                 # at the wheel of a truck handed over in the lot
#   tools/shot.sh --view=land                             # the lot, the land and every road to the routes' gates
#   tools/shot.sh --view=sign [--n=0]                       # an entrance sign and the guide path leading out of the lot
#   tools/shot.sh --view=gate --route=dd_river_cut        # a truck at a route's gate, the delivery offered
#   tools/shot.sh --view=walk_gate                        # on foot at a gate: as far as anybody walks
#   tools/shot.sh --view=standin --seconds=40             # a stand-in from the spawn to its truck and up the land's road to a gate
#   tools/shot.sh --view=drive --route=dd_snowline --seconds=40   # a stand-in at the wheel, chase camera
#   tools/shot.sh --view=cab --route=dd_river_cut --seconds=20    # from the cab
#   tools/shot.sh --view=cab_side [--truck=semi] [--dx=-5 --dy=2.2 --dz=-1.6]   # beside the driver's door: the seated person; dz>0 looks from behind
#   tools/shot.sh --view=drive --orbit=70,15              # the chase camera dragged round (yaw,pitch degrees)
#   tools/shot.sh --view=standin --near=3.5 --seconds=3   # a walker close up, mid-stride (--near is the metres behind)
#   tools/shot.sh --view=above --route=dd_devils_spine     # the whole route from above
#   tools/shot.sh --view=drive --sky=snow                  # force the weather everywhere
#   tools/shot.sh --view=drive --mountain=high_country --route=dd_snowline --bridge=collapse --seconds=2   # a bridge deck coming down ahead of the truck
#   tools/shot.sh --view=drive --route=dd_wind_ridge --hazard=tornado   # a stage hazard (tornado, wind, quake) ahead, mid-life
#   tools/shot.sh --view=drive --route=dd_snowline --at=880 --seconds=4   # put the truck 880 m along first
#   tools/shot.sh --mountain=low_country                   # the lot on another mountain (DdMountains)
#   tools/shot.sh --view=loading                           # the loading screen, as the real entry puts it up
#   tools/shot.sh --view=cover                            # the same, under its platform-layer name
#   tools/shot.sh --view=maps                              # M: the solo mountain list with a Workshop fixture map (Name [Pack])
#   tools/shot.sh --ballot --out=res://screenshots/ballot.png   # the mountain vote's ballot, mid-vote, as the client shell draws it
#   tools/shot.sh --ballot --chat=8                        # and a chat log filled with eight lines over the lot
#
# xvfb-run because this needs a rendering context; --headless gives a null renderer and saves
# a frame of nothing. --fixed-fps so a stand-in forty seconds up a route is forty simulated
# seconds, not forty seconds of waiting.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots

view="garage"; seconds="6"; out=""; route="dd_foothills"; sky=""; hazard=""; at="0"; truck=""; mountain=""; ballot="0"; chat="0"; people="0"; panel="0"; n="0"; orbit=""; near="0"; dx="-5"; dy="2.2"; dz="-1.6"; bridge=""
take=0; extra=()
for arg in "$@"; do
    if [ "$take" -gt 0 ]; then extra+=("$arg"); take=$((take - 1)); continue; fi
    case "$arg" in
        --action)    extra+=("$arg"); take=2; view="action" ;;
        --view=*)    view="${arg#*=}" ;;
        --seconds=*) seconds="${arg#*=}" ;;
        --out=*)     out="${arg#*=}" ;;
        --route=*)   route="${arg#*=}" ;;
        --sky=*)     sky="${arg#*=}" ;;
        --hazard=*)  hazard="${arg#*=}" ;;
        --at=*)      at="${arg#*=}" ;;
        --truck=*)   truck="${arg#*=}" ;;
        --mountain=*) mountain="${arg#*=}" ;;
        --n=*)       n="${arg#*=}" ;;
        --ballot)    ballot="1" ;;
        --chat=*)    chat="${arg#*=}" ;;
        --people=*)  people="${arg#*=}" ;;
        --near=*)    near="${arg#*=}" ;;
        --orbit=*)   orbit="${arg#*=}" ;;
        --dx=*)      dx="${arg#*=}" ;;
        --dy=*)      dy="${arg#*=}" ;;
        --dz=*)      dz="${arg#*=}" ;;
        --bridge=*)  bridge="${arg#*=}" ;;
        --panel)     panel="1" ;;
        *)           echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done
[ -n "$out" ] || out="res://screenshots/${view}.png"

exec xvfb-run -a "${GODOT:-godot}" --fixed-fps 60 --path . --resolution 1280x720 \
    res://tools/shot.tscn -- "--seconds=$seconds" "--view=$view" "--out=$out" "--route=$route" "--sky=$sky" "--hazard=$hazard" "--at=$at" "--truck=$truck" "--mountain=$mountain" "--ballot=$ballot" "--chat=$chat" "--people=$people" "--panel=$panel" "--n=$n" "--orbit=$orbit" "--near=$near" "--dx=$dx" "--dy=$dy" "--dz=$dz" "--bridge=$bridge" "${extra[@]}"
