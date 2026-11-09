#!/bin/sh
# Look at the demo on the iPhone Duo simulator: install a build, launch it with
# the demo's launch arguments, take stills of both displays, walk a pose's
# states, and record a launch frame by frame.
#
# By launch argument, because while the Duo is open `simctl` reaches only the
# outer display with a tap or a key. Its screenshots and recordings reach both:
# display 1 is the outer one and display 3 the inner one. For touch on the inner
# display, run a UI test (scripts/ui-smoke.sh does, on an iPhone 18 Pro).
#
# Nothing here opens, closes or turns the Duo. Set the pose first, in Device
# Hub, and `orient` says what the displays make of it.
#
# usage: scripts/duo.sh <command> [...]
#   install <AskKitDemo.app>    install a build of the demo
#   launch [arguments...]       launch the demo, ending a running one first
#   cap <name>                  stills of both displays, and small copies
#   orient [name]               each display's orientation, and which is lit
#   closed <pose>               a closed pose's four states, in a tab over the slot:
#                               a chat, the same with the keyboard up, the first
#                               screen, and that with the keyboard up
#   open <pose> <part>          an open pose's states:
#                                 chats  a chat beside the pane of chats, in a tab
#                                        over the slot and in the screen's own bar,
#                                        at rest and with the keyboard up
#                                 first  the first screen of a domain that keeps
#                                        no chats, at rest and with the keyboard up
#                                 both   the first screen across both panes. It
#                                        starts from no saved chats and no
#                                        remembered domain, so what the demo
#                                        keeps is copied out first and put back
#                                 all    the three, in that order
#   record <name> outer|inner [arguments...]
#                               record a launch on one display, keep what the demo
#                               prints, and lay the bar strip out frame by frame
#   sheet <out.png> <label=still.png>...
#                               a contact sheet of stills, labelled
#
# `closed` and `open ... chats` want a chat already saved: launch the demo with
# no arguments and ask a question first, with the Duo closed.
#
# Everything lands under tmp/duo/, which git ignores: stills in shots/ with
# small copies in shots/s/, recordings in video/.
#
# The simulator is a booted device of the iPhone Duo device type, whatever it is
# named, on the Duo's own runtime (iOS-27-2-iPhone19-4 for iOS 27.2). Boot one
# first: this takes the one booted Duo and stops when more than one is booted;
# ASKKIT_DUO_UDID picks one then, or any device regardless. Nothing here boots
# it or shuts it down.
# ASKKIT_DUO_BUNDLE names an app other than the demo for `launch` and `record`,
# to set one of Apple's own beside it: `com.apple.Preferences` is Settings.
# `record` needs ffmpeg, and it and `sheet` need ImageMagick's montage.
set -eu

cd "$(dirname "$0")/.."

out=tmp/duo
bundle=${ASKKIT_DUO_BUNDLE:-com.example.askkitdemo}
# The question the keyboard comes up holding: `-askPrefill` focuses the field.
prefill='askkitdemo://ask?q=What%20is%20the%20oldest%20thing%20I%20have'
font=/System/Library/Fonts/Supplemental/Arial.ttf

usage() {
  # The header's usage block, to its first empty comment line.
  sed -n '/^# usage:/,/^#$/p' scripts/duo.sh | sed -e '$d' -e 's/^# \{0,1\}//' >&2
  exit 2
}

# A hung simctl would hold the simulator, which other work may be waiting on.
within() {
  seconds=$1
  shift
  perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
}

duo=${ASKKIT_DUO_UDID:-}
find_duo() {
  [ -n "$duo" ] && return 0
  duo=$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
for ds in json.load(sys.stdin)["devices"].values():
    for d in ds:
        if d.get("deviceTypeIdentifier") == "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo":
            print(d["udid"])')
  booted=$(printf '%s\n' "$duo" | grep -c . || true)
  if [ "$booted" -eq 0 ]; then
    echo "duo: no Duo is booted: boot a simulator of the iPhone Duo device type on the Duo's runtime, iOS-27-2-iPhone19-4, or set ASKKIT_DUO_UDID" >&2
    exit 1
  fi
  if [ "$booted" -gt 1 ]; then
    echo "duo: $booted Duos are booted, so it is unclear which to drive: name yours in ASKKIT_DUO_UDID" >&2
    exit 1
  fi
}

launch() {
  within 90 xcrun simctl launch --terminate-running-process "$duo" "$bundle" "$@" >/dev/null || {
    echo "duo: launch failed" >&2
    exit 1
  }
  # The launch animation, and the saved chat read back.
  sleep 5
}

cap() {
  mkdir -p "$out/shots/s"
  for pair in 1:outer 3:inner; do
    still="$out/shots/$1-${pair#*:}.png"
    within 90 xcrun simctl io "$duo" screenshot --display="${pair%%:*}" "$still" >/dev/null 2>&1
    sips -Z 900 "$still" --out "$out/shots/s/$1-${pair#*:}.png" >/dev/null 2>&1
  done
  echo "$out/shots/$1-outer.png $out/shots/$1-inner.png"
}

# A display that isn't the lit one comes back black, a still of 50 to 110 KB
# where a lit one runs to megabytes.
orient() {
  xcrun simctl io "$duo" enumerate 2>/dev/null | grep "UI Orientation" | head -2 | tr -s ' ' | tr '\n' ';'
  echo
  cap "$1" >/dev/null
  for which in outer inner; do
    still="$out/shots/$1-$which.png"
    bytes=$(stat -f %z "$still")
    lit=dark
    [ "$bytes" -gt 300000 ] && lit=lit
    echo "$which: $lit, $(sips -g pixelWidth -g pixelHeight "$still" | awk '/pixel/ { printf "%s ", $2 }')($bytes bytes)"
  done
}

# Launch with the arguments after the name, then take the stills.
shot() {
  name=$1
  shift
  launch "$@"
  cap "$name"
}

# The same, a moment later: the keyboard is still on its way up at the launch's end.
shot_typing() {
  name=$1
  shift
  launch "$@" -askPrefill "$prefill"
  sleep 2
  cap "$name"
}

closed() {
  shot "$1-thread" -askTabs -askSlot -askScriptedAnswer
  shot_typing "$1-threadkb" -askTabs -askSlot -askScriptedAnswer
  shot "$1-first" -askTabs -askSlot -askScriptedAnswer -askResetThread
  shot_typing "$1-firstkb" -askTabs -askSlot -askScriptedAnswer -askResetThread
}

open_chats() {
  shot "$1-thread" -askTabs -askSlot -askScriptedAnswer
  shot_typing "$1-threadkb" -askTabs -askSlot -askScriptedAnswer
  shot "$1-bar-thread" -askScriptedAnswer
  shot_typing "$1-bar-threadkb" -askScriptedAnswer
}

open_first() {
  shot "$1-first" -askTabs -askSlot -askScriptedAnswer -askResetThread
  shot_typing "$1-firstkb" -askTabs -askSlot -askScriptedAnswer -askResetThread
}

# What `-askFreshHistory` deletes (`DemoHost.atLaunch()`): each domain's folder
# under Application Support, which holds everything AskKit keeps for it, and
# the default that remembers which domain the demo was left on.
history_folders="AskKitDemo AskKitDemoAssistant"
domain_key=demo.domain

# So what of those there is gets copied out first and put back however the run
# ends: a launch or a still that fails exits the script, and the trap restores
# them on the way out. The copy goes only once all of it is back, so one found
# at the start is a run's that couldn't put it back, perhaps the only copy of
# those chats, and this stops rather than overwrite it. The container's path is
# asked for each time: installing the demo again moves it.
open_both() {
  container=$(xcrun simctl get_app_container "$duo" "$bundle" data)
  support="$container/Library/Application Support"
  # The demo's defaults as a `defaults` domain: their plist's path, less .plist.
  prefs="$container/Library/Preferences/$bundle"
  keep="$out/saved-history"
  if [ -e "$keep" ]; then
    echo "duo: $PWD/$keep holds what an earlier run copied out before -askFreshHistory and didn't put back, perhaps the only copy of those chats." >&2
    echo "duo: put it back with:" >&2
    put_back_commands >&2
    echo "duo: or, if the demo's chats are the ones you want, remove $PWD/$keep. Then run this again." >&2
    exit 1
  fi
  xcrun simctl terminate "$duo" "$bundle" 2>/dev/null || true
  save_history
  if [ -e "$keep" ]; then
    # sh runs an EXIT trap on `exit`, not on a signal, so the signals exit.
    trap restore_history EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
  fi
  shot "$1-both" -askTabs -askSlot -askScriptedAnswer -askFreshHistory
  shot_typing "$1-bothkb" -askTabs -askSlot -askScriptedAnswer -askFreshHistory
  shot "$1-bar-both" -askScriptedAnswer -askFreshHistory
  trap - EXIT INT TERM
  restore_history
}

# Copies what of `history_folders` and `domain_key` there is into $keep: each
# folder whole, and the domain as a file of its own, read from the plist the
# demo, ended first, has written. By plistlib, since plutil reads a key path,
# which takes the key's dot for a separator. A partial copy goes, since nothing
# has been deleted yet, and the run stops.
save_history() {
  for folder in $history_folders; do
    [ -d "$support/$folder" ] || continue
    if ! { mkdir -p "$keep" && cp -R "$support/$folder" "$keep/$folder"; }; then
      abandon_save
    fi
  done
  # Nothing printed is no domain remembered; a plist that can't be read stops
  # the run, as a folder that can't be copied does.
  [ -f "$prefs.plist" ] || return 0
  domain=$(python3 -I -c '
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    value = plistlib.load(f).get(sys.argv[2])
if isinstance(value, str):
    print(value)' "$prefs.plist" "$domain_key" 2>/dev/null) || abandon_save
  [ -n "$domain" ] || return 0
  if ! { mkdir -p "$keep" && printf '%s\n' "$domain" >"$keep/$domain_key"; }; then
    abandon_save
  fi
}

abandon_save() {
  rm -rf "$keep"
  echo "duo: couldn't copy out what -askFreshHistory deletes, so nothing was deleted" >&2
  exit 1
}

# Puts back what `save_history` copied out, and deletes the copy only once all
# of it is back. A failure leaves the copy where it is and says so.
#
# The domain goes back through `defaults` run in the simulator, not as a file:
# the demo reads its defaults through the simulator's preferences daemon, which
# may hold a copy of them and miss a file written underneath it. It is read
# back the same way, which shows the write took there, not that the demo will
# read it.
restore_history() {
  [ -d "$keep" ] || return 0
  xcrun simctl terminate "$duo" "$bundle" 2>/dev/null || true
  back=1
  for folder in $history_folders; do
    [ -d "$keep/$folder" ] || continue
    if ! { rm -rf "${support:?}/$folder" && cp -R "$keep/$folder" "$support/$folder"; }; then
      back=0
    fi
  done
  if [ -f "$keep/$domain_key" ]; then
    domain=$(cat "$keep/$domain_key")
    if ! xcrun simctl spawn "$duo" defaults write "$prefs" "$domain_key" -string "$domain" ||
      [ "$(xcrun simctl spawn "$duo" defaults read "$prefs" "$domain_key" 2>/dev/null)" != "$domain" ]; then
      back=0
    fi
  fi
  if [ "$back" = 1 ]; then
    rm -rf "$keep"
    # stderr, which a trap that fires inside `launch`'s `>/dev/null` still reaches.
    echo "duo: what -askFreshHistory deleted is back" >&2
  else
    echo "duo: couldn't put all of it back: the copy is in $PWD/$keep" >&2
    put_back_commands >&2
    return 1
  fi
}

# The commands that put back, by hand, the copy in $keep.
put_back_commands() {
  for folder in $history_folders; do
    if [ -d "$keep/$folder" ]; then
      echo "  rm -rf \"$support/$folder\" && cp -R \"$PWD/$keep/$folder\" \"$support/$folder\""
    fi
  done
  if [ -f "$keep/$domain_key" ]; then
    echo "  xcrun simctl spawn $duo defaults write \"$prefs\" $domain_key -string \"$(cat "$keep/$domain_key")\""
  fi
  echo "  rm -rf \"$PWD/$keep\""
}

# The strip is the display's trailing 84 pt, with the outer display upright
# and the inner one on its side: cropped at 3x from a recording ffmpeg has
# already turned the way the display is held.
record() {
  name=$1
  case "$2" in
    outer) display=1 crop=252:1200:1146:0 ;;
    inner) display=3 crop=272:1200:2580:0 ;;
    *) usage ;;
  esac
  shift 2
  video="$out/video"
  frames="$video/$name-frames"
  rm -rf "$frames"
  mkdir -p "$frames"
  xcrun simctl terminate "$duo" "$bundle" 2>/dev/null || true
  sleep 2
  xcrun simctl io "$duo" recordVideo --display="$display" --codec=h264 --force "$video/$name.mov" 2>"$video/$name.rec.log" &
  recorder=$!
  sleep 3
  # `--console-pty` holds the demo's output until the alarm ends simctl, which
  # is the exit status this ignores.
  within 9 xcrun simctl launch --console-pty --terminate-running-process "$duo" "$bundle" "$@" \
    >"$video/$name.console.log" 2>&1 || true
  kill -INT "$recorder"
  wait "$recorder" 2>/dev/null || true
  # Every frame as recorded: they aren't evenly spaced, and `ffprobe
  # -show_entries frame=pts_time` has each one's time.
  ffmpeg -v error -y -i "$video/$name.mov" -fps_mode passthrough -vf "crop=$crop,scale=iw/2:-1" "$frames/%04d.png" 2>/dev/null
  montage -font "$font" -pointsize 14 -label '%t' "$frames"/*.png -tile 30x -geometry +3+3 -background white "$video/$name-strip.png"
  echo "$video/$name.mov $video/$name.console.log $video/$name-strip.png"
}

sheet() {
  to=$1
  shift
  # Each `label=still.png` becomes montage's `-label label still.png`, appended
  # while the originals are shifted off the front.
  count=$#
  while [ "$count" -gt 0 ]; do
    set -- "$@" -label "${1%%=*}" "${1#*=}"
    shift
    count=$((count - 1))
  done
  montage -font "$font" -pointsize 30 "$@" -tile x1 -geometry 466x678+24+24 -background white "$to"
  echo "$to"
}

[ "$#" -ge 1 ] || usage
command=$1
shift
case "$command" in
  install)
    [ "$#" -eq 1 ] || usage
    find_duo
    within 300 xcrun simctl install "$duo" "$1"
    ;;
  launch)
    find_duo
    launch "$@"
    ;;
  cap)
    [ "$#" -eq 1 ] || usage
    find_duo
    cap "$1"
    ;;
  orient)
    [ "$#" -le 1 ] || usage
    find_duo
    orient "${1:-orient}"
    ;;
  closed)
    [ "$#" -eq 1 ] || usage
    find_duo
    closed "$1"
    ;;
  open)
    [ "$#" -eq 2 ] || usage
    find_duo
    case "$2" in
      chats) open_chats "$1" ;;
      first) open_first "$1" ;;
      both) open_both "$1" ;;
      all)
        open_chats "$1"
        open_first "$1"
        open_both "$1"
        ;;
      *) usage ;;
    esac
    ;;
  record)
    [ "$#" -ge 2 ] || usage
    find_duo
    record "$@"
    ;;
  sheet)
    [ "$#" -ge 2 ] || usage
    sheet "$@"
    ;;
  *) usage ;;
esac
