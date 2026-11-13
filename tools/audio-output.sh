#!/bin/bash
# Set the default audio output and move what's playing onto it.
#   audio-output.sh <node-id> <sink-name>
#
# Like omarchy-audio-output-set-default, but also moves streams that carry no
# application.name (Mopidy shows up only as "python3.14"), which that command
# leaves on the old output. Left alone:
#  - internal streams of filter chains / loopbacks (node.link-group, or owned
#    by a module): moving them rewires the processing itself;
#  - EasyEffects' output, for the same reason;
#  - snapclient: it plays the Snapcast group on this machine, and moving it
#    into a Snapcast pipe sink would feed the group back into itself.
node_id=${1:-}
sink_name=${2:-}
if [[ -z $node_id || -z $sink_name ]]; then
  echo "Usage: audio-output.sh <node-id> <sink-name>" >&2
  exit 1
fi

timeout 2 wpctl set-default "$node_id" 2>/dev/null || true
timeout 2 pactl set-default-sink "$sink_name" 2>/dev/null || true

LC_ALL=C timeout 2 pactl list sink-inputs 2>/dev/null | awk '
  function flush() { if (id != "" && !skip) print id; id = ""; skip = 0 }
  /^Sink Input #/ { flush(); id = substr($3, 2) }
  /^\tOwner Module: [0-9]/ { skip = 1 }
  /node\.link-group = / { skip = 1 }
  /application\.name = "EasyEffects"/ { skip = 1 }
  /application\.process\.binary = "snapclient"/ { skip = 1 }
  /application\.name = "Snapclient"/ { skip = 1 }
  END { flush() }' | while read -r input; do
  [[ -n $input ]] && timeout 2 pactl move-sink-input "$input" "$sink_name" 2>/dev/null || true
done
