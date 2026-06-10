#!/usr/bin/env bash
# Verified Unity-server load probe: -smoke autoclients with -logFile so we can
# confirm a real match was observed while sampling the server's CPU.
set -u
pid=$(systemctl show -p MainPID --value pong.service)
echo "unity pid=$pid"
rm -f /tmp/u1.log /tmp/u2.log
"$HOME/pong/PongServer.x86_64" -batchmode -nographics -autoclient -smoke -address 127.0.0.1 -port 7777 -quitafter 20 -logFile /tmp/u1.log & C1=$!
sleep 1
"$HOME/pong/PongServer.x86_64" -batchmode -nographics -autoclient -smoke -address 127.0.0.1 -port 7777 -quitafter 20 -logFile /tmp/u2.log & C2=$!
sleep 5
hz=$(getconf CLK_TCK)
t1=$(awk '{print $14+$15}' "/proc/$pid/stat")
sleep 10
t2=$(awk '{print $14+$15}' "/proc/$pid/stat")
awk -v a="$t1" -v b="$t2" -v hz="$hz" 'BEGIN { printf "unity cpu_10s=%.2f%%\n", (b-a)/hz/10*100 }'
awk '/VmRSS/ {printf "unity rss=%.1f MB\n", $2/1024}' "/proc/$pid/status"
wait $C1; R1=$?
wait $C2; R2=$?
echo "client exits R1=$R1 R2=$R2"
grep -h SMOKE_ /tmp/u1.log /tmp/u2.log 2>/dev/null || echo "(no SMOKE lines found)"
