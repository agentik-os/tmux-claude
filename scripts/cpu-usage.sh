#!/bin/bash
# Script ultra-léger pour afficher l'usage CPU
# Utilise /proc/stat (instantané, 0 overhead)

# Lire les valeurs CPU depuis /proc/stat
read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat

# Calculer le total et l'idle
total=$((user + nice + system + idle + iowait + irq + softirq + steal))
used=$((total - idle - iowait))

# Calculer le pourcentage
percent=$((used * 100 / total))

echo "${percent}%"
