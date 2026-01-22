#!/bin/bash
# Script ultra-léger pour afficher l'usage disque
# Utilise df (instantané)

# Lire l'usage de la partition racine
PERCENT=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')

echo "${PERCENT}%"
