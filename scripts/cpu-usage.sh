#!/bin/bash
read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
total=$((user + nice + system + idle + iowait + irq + softirq + steal))
used=$((total - idle - iowait))
percent=$((used * 100 / total))
echo "${percent}%"
