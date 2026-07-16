#!/bin/zsh
# Plays an audible tick every INTERVAL minutes to track elapsed interview time.
# At the Nth interval it plays N ticks (10 min = 1 tick, 20 min = 2 ticks, ...)
# so you can tell how far in you are without counting from the start.
#
# Usage: ./tick.sh [interval-minutes] [volume 0.0-1.0]
#   ./tick.sh          # tick every 10 min at 50% volume
#   ./tick.sh 5 0.3    # every 5 min, quieter
# Ctrl-C to stop.

INTERVAL_MIN=${1:-10}
VOLUME=${2:-0.5}
SOUND=/System/Library/Sounds/Tink.aiff

echo "Started $(date '+%H:%M:%S') — ticking every ${INTERVAL_MIN} min. Ctrl-C to stop."

start=$(date +%s)
n=0
while true; do
  (( n++ ))
  # Schedule against the start time so tick playback doesn't accumulate drift.
  target=$(( start + n * INTERVAL_MIN * 60 ))
  now=$(date +%s)
  (( target > now )) && sleep $(( target - now ))
  echo "$(date '+%H:%M:%S') — $(( n * INTERVAL_MIN )) min elapsed"
  # Launch each tick in the background: afplay blocks until the file's
  # trailing silence ends, so sequential plays would space ticks ~1.2s apart.
  for i in $(seq "$n"); do
    afplay -v "$VOLUME" "$SOUND" &
    sleep 0.2
  done
  wait
done
