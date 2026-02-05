#!/bin/bash
TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
AVAILABLE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
USED=$((TOTAL - AVAILABLE))
PERCENT=$((USED * 100 / TOTAL))
echo "${PERCENT}%"
