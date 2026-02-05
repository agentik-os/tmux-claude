#!/bin/bash
COUNT=$(pgrep -f "claude.*--background" 2>/dev/null | wc -l)
echo "$COUNT"
