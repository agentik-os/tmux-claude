#!/bin/bash
COUNT=0
for port in 9222 9223 9224 9225 9226 9227 9228; do
    ss -tln 2>/dev/null | grep -q ":$port " && ((COUNT++))
done
echo "$COUNT"
