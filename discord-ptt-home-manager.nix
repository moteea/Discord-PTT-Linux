{ config, pkgs, ... }:

let
  pttConfig = {
    DEVICE_PATH = "/dev/input/eventX";
    PTT_CODE = 276;
    DISCORD_SHORTCUT = "shift+equal";
    DISPLAY = ":0";
  };
in
{
  home.packages = with pkgs; [
    python3
    python3Packages.evdev
    xdotool
    rofi
    libnotify
  ];

  xdg.configFile."ptt/config.json".text = builtins.toJSON pttConfig;

  xdg.configFile."ptt/discord-ptt.py" = {
    executable = true;
    text = ''
#!/usr/bin/env python3
from evdev import InputDevice, ecodes
import json
import os
import subprocess

cfg = json.load(open(os.path.expanduser("~/.config/ptt/config.json")))
dev = InputDevice(cfg["DEVICE_PATH"])

def send(press):
    os.environ["DISPLAY"] = cfg.get("DISPLAY", ":0")
    cmd = "keydown" if press else "keyup"
    subprocess.run(["xdotool", cmd, cfg["DISCORD_SHORTCUT"]], check=False)

for event in dev.read_loop():
    if event.type == ecodes.EV_KEY and event.code == int(cfg["PTT_CODE"]):
        if event.value == 1:
            send(True)
        elif event.value == 0:
            send(False)
'';
  };

  xdg.configFile."ptt/RofiPTT.sh" = {
    executable = true;
    text = ''
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
'';
  };

  systemd.user.services.discord-ptt = {
    Unit = {
      Description = "Discord Mouse Push-To-Talk";
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "%h/.config/ptt/discord-ptt.py";
      Restart = "always";
      Environment = [ "DISPLAY=:0" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
