#!/usr/bin/env bash
# Side-by-side footprint of the Unity (pong.service) and Godot (pong-godot.service)
# dedicated servers running on this VM: RSS, CPU% sampled over a 10 s window, disk
# size of the install, and process count. Run on the VM: bash ~/measure-footprint.sh
set -u

cpu_pct() {  # pid -> CPU% over a 10s window (jiffies delta / hertz)
  local pid=$1
  local hz; hz=$(getconf CLK_TCK)
  local t1 t2
  t1=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null) || { echo "n/a"; return; }
  sleep 10
  t2=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null) || { echo "n/a"; return; }
  awk -v a="$t1" -v b="$t2" -v hz="$hz" 'BEGIN { printf "%.2f", (b-a)/hz/10*100 }'
}

report() {  # unit dir label
  local unit=$1 dir=$2 label=$3
  local pid rss disk
  pid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null)
  echo "== $label ($unit) =="
  if [ -z "$pid" ] || [ "$pid" = "0" ]; then echo "  not running"; return; fi
  rss=$(awk '/VmRSS/ {printf "%.1f", $2/1024}' "/proc/$pid/status" 2>/dev/null)
  disk=$(du -sh "$dir" 2>/dev/null | cut -f1)
  echo "  pid=$pid  rss=${rss} MB  disk=$disk  threads=$(ls /proc/$pid/task 2>/dev/null | wc -l)"
  echo "  cpu_10s=$(cpu_pct "$pid")%"
}

report pong.service "$HOME/pong" "Unity server"
report pong-godot.service "$HOME/pong-godot" "Godot server"
echo "== VM =="
grep -E "model name" /proc/cpuinfo | head -1
free -m | awk 'NR<=2'
uptime
