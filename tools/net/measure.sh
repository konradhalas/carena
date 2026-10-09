#!/bin/bash
# Measures on-screen smoothness of own (predicted) and remote (interpolated)
# cars against a local dedicated server, optionally through a lag proxy.
# Usage: tools/net/measure.sh [ONE_WAY_DELAY_MS JITTER_MS]   e.g. 50 10 ≈ 100 ms RTT
set -u
cd "$(dirname "$0")/../.."
DELAY=${1:-0}
JITTER=${2:-0}
SERVER_PORT=7830
CLIENT_PORT=$SERVER_PORT
cleanup() { kill $(jobs -p) 2>/dev/null; }
trap cleanup EXIT

if [ "$DELAY" != "0" ] || [ "$JITTER" != "0" ]; then
  CLIENT_PORT=7831
  python3 tools/net/lag_proxy.py $CLIENT_PORT $SERVER_PORT "$DELAY" "$JITTER" &
fi

run_server() { godot --headless -- --server --port=$SERVER_PORT > /dev/null 2>&1 & SERVER=$!; sleep 2; }

run_server
godot --headless --script res://tools/net/jitter_probe.gd -- own $CLIENT_PORT 2>&1 | grep PROBE
kill $SERVER; wait $SERVER 2>/dev/null; sleep 1

run_server
godot --headless --script res://tools/net/jitter_probe.gd -- remote $CLIENT_PORT 2>&1 | grep PROBE &
PROBE=$!
sleep 1
godot --headless -- --join=127.0.0.1 --port=$SERVER_PORT --bot > /dev/null 2>&1 &
wait $PROBE
kill $SERVER; wait $SERVER 2>/dev/null; sleep 1

godot --headless --script res://tools/net/jitter_probe.gd -- offline 2>&1 | grep PROBE
