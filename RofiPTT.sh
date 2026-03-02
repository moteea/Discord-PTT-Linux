#!/usr/bin/env bash
set -euo pipefail

CONFIG="$HOME/.config/ptt/config.json"
SERVICE="discord-ptt.service"

status=$(systemctl --user is-active "$SERVICE" 2>/dev/null || true)

if [[ "$status" == "active" ]]; then
  options=$(printf "Stop PTT Service\nRestart PTT Service\nSet Discord Keybind\nShow Current Keybind")
else
  options=$(printf "Start PTT Service\nSet Discord Keybind\nShow Current Keybind")
fi

choice=$(echo "$options" | rofi -dmenu -i -p "Discord PTT")

normalize_shortcut() {
  local s="$1"
  s=$(echo "$s" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$s" in
    "+"|"plus") s="shift+equal" ;;
  esac
  printf "%s" "$s"
}

set_shortcut() {
  local picked custom shortcut
  picked=$(printf "shift+equal\nCustom..." | rofi -dmenu -i -p "Discord keybind")

  if [[ "$picked" == "Custom..." ]]; then
    custom=$(rofi -dmenu -p "Type keybind" -mesg "Example: ctrl+shift+p or f8")
    shortcut=$(normalize_shortcut "$custom")
  else
    shortcut=$(normalize_shortcut "$picked")
  fi

  if [[ -z "$shortcut" ]]; then
    notify-send "Discord PTT" "No keybind entered"
    exit 0
  fi

  if [[ ! "$shortcut" =~ ^[a-z0-9_+:-]+$ ]]; then
    notify-send "Discord PTT" "Invalid keybind format: $shortcut"
    exit 1
  fi

  python3 - "$CONFIG" "$shortcut" <<'PY'
import json
import sys
p, key = sys.argv[1], sys.argv[2]
with open(p, 'r', encoding='utf-8') as f:
    data = json.load(f)
data['DISCORD_SHORTCUT'] = key
with open(p, 'w', encoding='utf-8') as f:
    json.dump(data, f, separators=(',', ':'))
PY

  notify-send "Discord PTT" "Saved keybind: $shortcut"
  systemctl --user restart "$SERVICE" || true
}

show_shortcut() {
  local current
  current=$(python3 - "$CONFIG" <<'PY'
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print(data.get('DISCORD_SHORTCUT', 'not-set'))
PY
)
  notify-send "Discord PTT" "Current keybind: $current"
}

case "$choice" in
  "Start PTT Service")
    systemctl --user start "$SERVICE"
    ;;
  "Stop PTT Service")
    systemctl --user stop "$SERVICE"
    ;;
  "Restart PTT Service")
    systemctl --user restart "$SERVICE"
    ;;
  "Set Discord Keybind")
    set_shortcut
    ;;
  "Show Current Keybind")
    show_shortcut
    ;;
  *)
    exit 0
    ;;
esac
