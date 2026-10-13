#!/bin/bash
# Break mode of predmaxim.breaks (Service.qml):
#   quiet.sh on LOCK MUTE   LOCK=1: the predmaxim-breaks Hyprland submap (only
#                           the way out, Super+Shift+Alt+P); MUTE=1: mute the
#                           default output
#   quiet.sh off            undo what "on" did
#   quiet.sh cue CMD...     play a cue through the muted output
# The state file is in ~/.local/state, not the runtime dir: "off" at the
# service start puts the sound back after a crash or a reboot mid-break.
f=${XDG_STATE_HOME:-$HOME/.local/state}/predmaxim-breaks/quiet
sink=@DEFAULT_AUDIO_SINK@
case $1 in
on)
  [[ -e $f ]] && exit 0
  mkdir -p "${f%/*}"
  was_muted=0
  wpctl get-volume $sink | grep -q MUTED && was_muted=1
  printf 'lock=%s\nmute=%s\nwas_muted=%s\n' "$2" "$3" "$was_muted" >"$f"
  [[ $3 == 1 ]] && wpctl set-mute $sink 1
  [[ $2 == 1 ]] && hyprctl dispatch 'hl.dsp.submap("predmaxim-breaks")' >/dev/null
  ;;
off)
  [[ -e $f ]] || exit 0
  lock=$(sed -n 's/^lock=//p' "$f") mute=$(sed -n 's/^mute=//p' "$f") was_muted=$(sed -n 's/^was_muted=//p' "$f")
  [[ $lock == 1 ]] && hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null
  [[ $mute == 1 && $was_muted == 0 ]] && wpctl set-mute $sink 0
  rm -f "$f"
  ;;
cue)
  shift
  # ponytail: unmutes the whole output for the cue, other sound may slip
  # through for a second; per-stream muting if that matters.
  if [[ -e $f ]] && grep -qx 'mute=1' "$f"; then
    wpctl set-mute $sink 0; "$@"; [[ -e $f ]] && wpctl set-mute $sink 1
  else
    exec "$@"
  fi
  ;;
esac
