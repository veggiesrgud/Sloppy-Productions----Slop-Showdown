#!/bin/sh
cd "$(dirname "$0")"
if command -v godot >/dev/null 2>&1; then
  exec godot --headless --path "$PWD" "res://scenes/level/level.tscn"
else
  echo "ERROR: godot not found in PATH."
  echo "Install Godot or export the project and run: ./SlopShowdown --headless"
  exit 1
fi
