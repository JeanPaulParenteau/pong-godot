#!/usr/bin/env bash
# Apples-to-apples load probe: for each dedicated server on this VM (Unity on 7777,
# Godot on 7778), start one real match (two on-VM autoclients), then sample the
# server process's CPU% over 10 s and its RSS mid-match. Run: bash ~/load-measure.sh
set -u

cpu_pct() {  # pid -> CPU% over a 10s window
  local pid=$1 hz t1 t2
  hz=$(getconf CLK_TCK)
  t1=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null) || { echo "n/a"; return; }
  sleep 10
  t2=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null) || { echo "n/a"; return; }
  awk -v a="$t1" -v b="$t2" -v hz="$hz" 'BEGIN { printf "%.2f", (b-a)/hz/10*100 }'
}

probe() {  # unit label client_cmd...
  local unit=$1 label=$2; shift 2
  local pid rss
  pid=$(systemctl show -p MainPID --value "$unit")
  if [ -z "$pid" ] || [ "$pid" = "0" ]; then echo "== $label: not running =="; return; fi
  echo "== $label under load (1 match, 2 clients) =="
  "$@" >/tmp/lm1.log 2>&1 & C1=$!
  sleep 1
  "$@" >/tmp/lm2.log 2>&1 & C2=$!
  sleep 4  # let the match reach Playing
  local cpu; cpu=$(cpu_pct "$pid")
  rss=$(awk '/VmRSS/ {printf "%.1f", $2/1024}' "/proc/$pid/status")
  echo "  cpu_10s=${cpu}%  rss=${rss} MB"
  wait $C1 $C2 2>/dev/null
}

probe pong.service "Unity server" \
  "$HOME/pong/PongServer.x86_64" -batchmode -nographics -autoclient -address 127.0.0.1 -port 7777 -quitafter 20
probe pong-godot.service "Godot server" \
  "$HOME/pong-godot/PongServer.x86_64" --headless -- --autoclient --address 127.0.0.1 --port 7778 --quitafter 20
