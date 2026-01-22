#!/bin/bash
# Script ultra-léger pour afficher l'usage RAM
# Utilise /proc/meminfo (instantané, 0 overhead)

# Lire directement depuis /proc (pas de commande externe = ultra rapide)
TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
AVAILABLE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

# Calculer l'usage
USED=$((TOTAL - AVAILABLE))
PERCENT=$((USED * 100 / TOTAL))

echo "${PERCENT}%"
