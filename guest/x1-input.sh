#!/bin/sh
# Step 1: stop anything left over, and announce the input devices to libinput.
#
# No udevd runs in this image, so libinput finds no tagged device unless the udev
# database is written by hand (the teammate's working session wrote c13:64 and
# c13:65 as literals).  This derives the numbers from /sys and prints every
# device it saw, so a missing keyboard shows up in the log instead of being
# guessed at -- the QMP keystrokes used later have nowhere to land without this.
set -u
echo X1
pkill -x jwm 2>/dev/null; pkill -x Xorg 2>/dev/null; pkill -f chromium 2>/dev/null
sleep 2
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0
mkdir -p /run/udev/data
n=0
for e in /sys/class/input/event*; do
  [ -e "$e" ] || continue
  m=$(cut -d: -f2 "$e/dev")
  nm=$(cat "$e/device/name" 2>/dev/null)
  case "$nm" in
    *Keyboard*) printf 'I:1\nE:ID_INPUT=1\nE:ID_INPUT_KEYBOARD=1\n' > /run/udev/data/c13:$m ;;
    *Mouse*|*Tablet*) printf 'I:1\nE:ID_INPUT=1\nE:ID_INPUT_MOUSE=1\n' > /run/udev/data/c13:$m ;;
  esac
  echo "X2 $e c13:$m [$nm]"
  n=$((n+1))
done
echo "X3 events=$n udevdb=$(ls /run/udev/data 2>/dev/null | tr '\n' ' ')"
echo X4
