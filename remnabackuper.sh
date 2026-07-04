#!/bin/bash

INSTALL_DIR="/opt/remnabot"
CONFIG_FILE="$INSTALL_DIR/config.json"
BOT_SCRIPT="$INSTALL_DIR/bot.py"
CHECKER_SCRIPT="$INSTALL_DIR/checker.sh"
STATE_FILE="$INSTALL_DIR/state.json"
OFFSET_FILE="$INSTALL_DIR/offset.txt"
LOG_FILE="$INSTALL_DIR/bot.log"
SERVICE_NAME="remnabot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if [[ "$0" == *"pipe"* ]] || [[ "$0" == "bash" ]] || [[ "$0" == "/dev/fd/"* ]]; then
    SCRIPT_PATH="/root/remnabot.sh"
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        curl -fsSL https://raw.githubusercontent.com/Dnt3e/RemnaBackuper/main/remnabot.sh -o "$SCRIPT_PATH" 2>/dev/null
    fi
    chmod +x "$SCRIPT_PATH" 2>/dev/null
else
    SCRIPT_PATH=$(readlink -f "$0")
    chmod +x "$SCRIPT_PATH"
fi

G="\e[32m"; Y="\e[33m"; R="\e[31m"; C="\e[36m"; W="\e[97m"; M="\e[35m"
DIM="\e[2m"; BOLD="\e[1m"; NC="\e[0m"
LINE="${DIM}────────────────────────────────────────────────────────${NC}"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${R}Please run as root${NC}"
        exit 1
    fi
}

init_dirs() {
    mkdir -p "$INSTALL_DIR"
    touch "$LOG_FILE"
}

progress_bar() {
    local pct=$1
    local width=40
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    printf "\r  ${C}["
    if [ "$filled" -gt 0 ]; then printf "%0.s█" $(seq 1 "$filled"); fi
    if [ "$empty" -gt 0 ]; then printf "%0.s░" $(seq 1 "$empty"); fi
    printf "]${NC} ${BOLD}%3d%%${NC}" "$pct"
}

install_dependencies() {
    echo -e "${BOLD}${W}  Installing prerequisites${NC}"
    echo -e "${LINE}"
    local steps=(
        "apt-get update -y"
        "apt-get install -y python3"
        "apt-get install -y python3-pip"
        "apt-get install -y zip"
        "apt-get install -y curl"
        "apt-get install -y jq"
        "apt-get install -y cron"
        "systemctl enable cron"
        "systemctl start cron"
    )
    local total=${#steps[@]}
    local i=0
    for step in "${steps[@]}"; do
        i=$((i+1))
        eval "$step" >>"$LOG_FILE" 2>&1
        local pct=$(( i * 100 / total ))
        progress_bar "$pct"
        sleep 0.15
    done
    echo
    ensure_python_requests
    sleep 1
}

ensure_python_requests() {
    if python3 -c "import requests" >/dev/null 2>&1; then
        echo -e "${G}  [+] Dependencies installed.${NC}"
        return
    fi

    echo -e "${Y}  Installing python requests module...${NC}"
    python3 -m pip install --break-system-packages --quiet requests >>"$LOG_FILE" 2>&1

    if ! python3 -c "import requests" >/dev/null 2>&1; then
        apt-get install -y python3-requests >>"$LOG_FILE" 2>&1
    fi

    if ! python3 -c "import requests" >/dev/null 2>&1; then
        python3 -m pip install --user --quiet requests >>"$LOG_FILE" 2>&1
    fi

    if python3 -c "import requests" >/dev/null 2>&1; then
        echo -e "${G}  [+] Dependencies installed.${NC}"
    else
        echo -e "${R}  [-] Failed to install python requests module. Check $LOG_FILE${NC}"
    fi
}

default_config() {
    cat > "$CONFIG_FILE" <<EOF
{
  "bot_token": "",
  "admin_id": "",
  "interval_seconds": 3600,
  "backup_name": "RemnaBotBackup",
  "db_container": "remnawave-db",
  "db_user": "postgres",
  "db_name": "postgres",
  "extra_paths": []
}
EOF
}

load_config_value() {
    jq -r ".$1" "$CONFIG_FILE" 2>/dev/null
}

set_config_value() {
    local key=$1 val=$2
    local tmp
    tmp=$(mktemp)
    jq --arg v "$val" ".$key = \$v" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

set_config_number() {
    local key=$1 val=$2
    local tmp
    tmp=$(mktemp)
    jq --argjson v "$val" ".$key = \$v" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

get_server_ip() {
    hostname -I | awk '{print $1}'
}

format_interval_bash() {
    local seconds=$1
    local h=$(( seconds / 3600 ))
    local m=$(( (seconds % 3600) / 60 ))
    if [ "$h" -gt 0 ] && [ "$m" -gt 0 ]; then
        echo "${h}h ${m}m"
    elif [ "$h" -gt 0 ]; then
        echo "${h}h"
    else
        echo "${m}m"
    fi
}

write_bot_py() {
cat > "$BOT_SCRIPT" <<'PYEOF'
import json
import os
import shutil
import subprocess
import sys
import time
import requests

INSTALL_DIR = "/opt/remnabot"
CONFIG_FILE = os.path.join(INSTALL_DIR, "config.json")
STATE_FILE = os.path.join(INSTALL_DIR, "state.json")
OFFSET_FILE = os.path.join(INSTALL_DIR, "offset.txt")


def load_config():
    with open(CONFIG_FILE) as f:
        return json.load(f)


def save_config(cfg):
    tmp = CONFIG_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, CONFIG_FILE)


def save_state(data):
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, STATE_FILE)


def load_state():
    if not os.path.exists(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def api_url(token, method):
    return "https://api.telegram.org/bot{}/{}".format(token, method)


def get_server_ip():
    try:
        out = subprocess.check_output(["hostname", "-I"]).decode().split()
        return out[0] if out else "unknown"
    except Exception:
        return "unknown"


def run_pg_dump(cfg, sql_path):
    db_container = cfg.get("db_container", "remnawave-db")
    db_user = cfg.get("db_user", "postgres")
    db_name = cfg.get("db_name", "postgres")

    docker_bin = shutil.which("docker")
    use_docker = False
    if docker_bin:
        check = subprocess.run(
            [docker_bin, "inspect", db_container],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if check.returncode == 0:
            use_docker = True

    if use_docker:
        cmd = [docker_bin, "exec", db_container, "pg_dump", "-U", db_user, db_name]
    else:
        cmd = ["pg_dump", "-U", db_user, db_name]

    with open(sql_path, "w") as f:
        result = subprocess.run(cmd, stdout=f, stderr=subprocess.PIPE)

    return result.returncode == 0


def perform_backup(cfg):
    backup_name = cfg.get("backup_name", "RemnaBotBackup")
    extra_paths = cfg.get("extra_paths", [])
    home = os.path.expanduser("~")
    sql_path = os.path.join(home, "backup.sql")
    zip_path = os.path.join(home, "{}.zip".format(backup_name))

    ok = run_pg_dump(cfg, sql_path)
    if not ok:
        return None, sql_path

    if os.path.exists(zip_path):
        os.remove(zip_path)

    targets = ["backup.sql"]
    for d in ["/opt/remnawave/", "/opt/remnanode/"] + extra_paths:
        if os.path.exists(d):
            targets.append(d)

    zip_cmd = ["zip", "-r", "{}.zip".format(backup_name)] + targets
    subprocess.run(zip_cmd, cwd=home, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    return zip_path, sql_path


def send_backup(cfg, zip_path):
    token = cfg["bot_token"]
    admin_id = cfg["admin_id"]
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    ip = get_server_ip()
    caption = "Server IP: {}\nTime: {}".format(ip, ts)
    with open(zip_path, "rb") as f:
        requests.post(
            api_url(token, "sendDocument"),
            data={"chat_id": admin_id, "caption": caption},
            files={"document": f},
            timeout=120,
        )


def cleanup(paths):
    for p in paths:
        if p and os.path.exists(p):
            try:
                os.remove(p)
            except Exception:
                pass


def send_message(token, chat_id, text, keyboard=None):
    payload = {"chat_id": chat_id, "text": text}
    if keyboard:
        payload["reply_markup"] = json.dumps(keyboard)
    requests.post(api_url(token, "sendMessage"), data=payload, timeout=30)


def edit_message(token, chat_id, message_id, text, keyboard=None):
    payload = {"chat_id": chat_id, "message_id": message_id, "text": text}
    if keyboard:
        payload["reply_markup"] = json.dumps(keyboard)
    requests.post(api_url(token, "editMessageText"), data=payload, timeout=30)


def answer_callback(token, callback_id, text=""):
    requests.post(
        api_url(token, "answerCallbackQuery"),
        data={"callback_query_id": callback_id, "text": text},
        timeout=30,
    )


def run_backup_job(cfg, notify_chat=None):
    zip_path, sql_or_none = perform_backup(cfg)
    if zip_path is None:
        if notify_chat:
            send_message(cfg["bot_token"], notify_chat, "Backup failed: database dump error.")
        cleanup([sql_or_none])
        return False
    send_backup(cfg, zip_path)
    cleanup([zip_path, sql_or_none])
    state = load_state()
    state["last_backup_ts"] = int(time.time())
    save_state(state)
    return True


def main_keyboard():
    return {
        "inline_keyboard": [
            [{"text": "Manual Backup", "callback_data": "backup_now"}],
            [{"text": "Set Backup Interval", "callback_data": "set_interval"}],
            [{"text": "Exit", "callback_data": "exit_menu"}],
        ]
    }


def format_interval(seconds):
    h = seconds // 3600
    m = (seconds % 3600) // 60
    if h and m:
        return "{}h {}m".format(h, m)
    if h:
        return "{}h".format(h)
    return "{}m".format(m)


def get_offset():
    if os.path.exists(OFFSET_FILE):
        try:
            with open(OFFSET_FILE) as f:
                return int(f.read().strip())
        except Exception:
            return 0
    return 0


def save_offset(offset):
    with open(OFFSET_FILE, "w") as f:
        f.write(str(offset))


def main_loop():
    offset = get_offset()
    awaiting_interval = {}

    while True:
        try:
            cfg = load_config()
            token = cfg["bot_token"]
            admin_id = str(cfg["admin_id"])

            resp = requests.get(
                api_url(token, "getUpdates"),
                params={"offset": offset, "timeout": 50},
                timeout=60,
            )
            data = resp.json()
            if not data.get("ok"):
                time.sleep(3)
                continue

            for update in data.get("result", []):
                offset = update["update_id"] + 1
                save_offset(offset)

                if "message" in update:
                    msg = update["message"]
                    chat_id = str(msg["chat"]["id"])
                    if chat_id != admin_id:
                        continue
                    text = msg.get("text", "")

                    if chat_id in awaiting_interval:
                        raw = text.strip()
                        seconds = None
                        if ":" in raw:
                            parts = raw.split(":")
                            if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
                                seconds = int(parts[0]) * 3600 + int(parts[1]) * 60
                        elif raw.isdigit():
                            seconds = int(raw) * 60

                        if seconds and seconds >= 60:
                            cfg["interval_seconds"] = seconds
                            save_config(cfg)
                            send_message(token, chat_id, "Interval set to {}.".format(format_interval(seconds)))
                        else:
                            send_message(
                                token,
                                chat_id,
                                "Invalid format. Use minutes (e.g. 360) or H:MM (e.g. 1:30).",
                            )
                        del awaiting_interval[chat_id]
                        send_message(token, chat_id, "Menu:", main_keyboard())
                        continue

                    if text == "/start":
                        send_message(token, chat_id, "RemnaBot Control Panel", main_keyboard())

                if "callback_query" in update:
                    cb = update["callback_query"]
                    chat_id = str(cb["message"]["chat"]["id"])
                    message_id = cb["message"]["message_id"]
                    cb_id = cb["id"]
                    if chat_id != admin_id:
                        answer_callback(token, cb_id, "Unauthorized")
                        continue
                    action = cb["data"]

                    if action == "backup_now":
                        answer_callback(token, cb_id, "Starting backup")
                        edit_message(token, chat_id, message_id, "Backup in progress, please wait...")
                        ok = run_backup_job(cfg, notify_chat=chat_id)
                        if ok:
                            send_message(token, chat_id, "Backup completed and sent.", main_keyboard())
                        else:
                            send_message(token, chat_id, "Backup failed.", main_keyboard())

                    elif action == "set_interval":
                        answer_callback(token, cb_id)
                        awaiting_interval[chat_id] = True
                        cur = format_interval(cfg.get("interval_seconds", 3600))
                        guide = (
                            "Current interval: {}\n\n"
                            "Send the new interval as:\n"
                            "- plain minutes, e.g. 360\n"
                            "- H:MM format, e.g. 1:30 (1 hour 30 minutes)"
                        ).format(cur)
                        edit_message(token, chat_id, message_id, guide)

                    elif action == "exit_menu":
                        answer_callback(token, cb_id)
                        edit_message(token, chat_id, message_id, "Menu closed. Send /start to open again.")

        except requests.exceptions.RequestException:
            time.sleep(5)
        except Exception:
            time.sleep(3)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--backup":
        _cfg = load_config()
        run_backup_job(_cfg)
    else:
        main_loop()
PYEOF
    chmod +x "$BOT_SCRIPT"
}

write_checker_script() {
cat > "$CHECKER_SCRIPT" <<'SHEOF'
#!/bin/bash
INSTALL_DIR="/opt/remnabot"
CONFIG_FILE="$INSTALL_DIR/config.json"
STATE_FILE="$INSTALL_DIR/state.json"
LOCK_FILE="$INSTALL_DIR/.checker.lock"
PYTHON_BIN=$(command -v python3)

[ -f "$CONFIG_FILE" ] || exit 0
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

INTERVAL=$(jq -r '.interval_seconds' "$CONFIG_FILE" 2>/dev/null)
[ -z "$INTERVAL" ] || [ "$INTERVAL" == "null" ] && exit 0

NOW=$(date +%s)
LAST=0
[ -f "$STATE_FILE" ] && LAST=$(jq -r '.last_backup_ts // 0' "$STATE_FILE" 2>/dev/null)
[ -z "$LAST" ] && LAST=0

DIFF=$(( NOW - LAST ))
if [ "$DIFF" -ge "$INTERVAL" ]; then
    "$PYTHON_BIN" "$INSTALL_DIR/bot.py" --backup >>"$INSTALL_DIR/bot.log" 2>&1
fi
SHEOF
    chmod +x "$CHECKER_SCRIPT"
}

write_service_file() {
    local PYBIN
    PYBIN=$(command -v python3)
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=RemnaBot Telegram Service
After=network.target

[Service]
Type=simple
ExecStart=$PYBIN $BOT_SCRIPT
Restart=always
RestartSec=5
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

ensure_cron() {
    ( crontab -l 2>/dev/null | grep -v "$CHECKER_SCRIPT" ; echo "* * * * * /bin/bash $CHECKER_SCRIPT >/dev/null 2>&1" ) | crontab -
}

prompt_interval() {
    local cur_seconds=$1
    local cur_fmt
    cur_fmt=$(format_interval_bash "${cur_seconds:-3600}")
    echo -e "${DIM}  Format: plain minutes (e.g. 360) or H:MM (e.g. 1:30 = 90 minutes)${NC}" >&2
    printf "${C}  Backup interval [${cur_fmt}]: ${NC}" >&2
    read -r raw
    raw="${raw%$'\r'}"

    if [ -z "$raw" ]; then
        echo "$cur_seconds"
        return
    fi

    local seconds
    if [[ "$raw" =~ ^([0-9]+):([0-9]{1,2})$ ]]; then
        local h=${BASH_REMATCH[1]} m=${BASH_REMATCH[2]}
        seconds=$(( h * 3600 + m * 60 ))
    elif [[ "$raw" =~ ^[0-9]+$ ]]; then
        seconds=$(( raw * 60 ))
    else
        echo -e "${R}  Invalid format, keeping previous value.${NC}" >&2
        echo "$cur_seconds"
        return
    fi

    if [ "$seconds" -lt 60 ]; then
        echo -e "${R}  Interval must be at least 1 minute, keeping previous value.${NC}" >&2
        echo "$cur_seconds"
        return
    fi

    echo "$seconds"
}

configure_bot() {
    [ -f "$CONFIG_FILE" ] || default_config
    local cur_token cur_admin cur_name cur_interval new_interval

    cur_token=$(load_config_value bot_token)
    printf "${C}  Bot Token [${cur_token}]: ${NC}"
    read -r input
    input=${input:-$cur_token}
    set_config_value bot_token "$input"

    cur_admin=$(load_config_value admin_id)
    printf "${C}  Admin Chat ID [${cur_admin}]: ${NC}"
    read -r input
    input=${input:-$cur_admin}
    set_config_value admin_id "$input"

    cur_name=$(load_config_value backup_name)
    printf "${C}  Backup file name [${cur_name}]: ${NC}"
    read -r input
    [ -n "$input" ] && set_config_value backup_name "$input"

    cur_interval=$(load_config_value interval_seconds)
    [ -z "$cur_interval" ] || [ "$cur_interval" == "null" ] && cur_interval=3600
    new_interval=$(prompt_interval "$cur_interval")
    set_config_number interval_seconds "$new_interval"

    echo -e "${LINE}"
    echo -e "${W}  Database backup runs automatically using:${NC}"
    echo -e "    ${DIM}docker exec remnawave-db pg_dump -U postgres postgres${NC}"
    echo -e "    ${DIM}(falls back to local pg_dump -U postgres postgres if no such container exists)${NC}"
    echo -e "${LINE}"
    echo -e "${W}  Default backup paths (always included if they exist):${NC}"
    echo -e "    /opt/remnawave/"
    echo -e "    /opt/remnanode/"
    echo -e "${LINE}"
    echo -e "${W}  Add custom paths? Type 'add' to add one, 'done' to finish.${NC}"

    local paths_json
    paths_json=$(jq -c '.extra_paths' "$CONFIG_FILE")
    [ "$paths_json" == "null" ] && paths_json="[]"

    while true; do
        printf "  [add/done]: "
        read -r act
        act="${act%$'\r'}"
        if [ "$act" == "done" ]; then
            break
        elif [ "$act" == "add" ]; then
            printf "  Path: "
            read -r p
            p="${p%$'\r'}"
            if [ -n "$p" ]; then
                paths_json=$(echo "$paths_json" | jq --arg p "$p" '. + [$p]')
                echo -e "${G}  Path added: $p${NC}"
            fi
        else
            echo -e "${R}  Invalid, type add or done.${NC}"
        fi
    done

    local tmp
    tmp=$(mktemp)
    jq --argjson p "$paths_json" '.extra_paths = $p' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"

    ensure_cron
    echo -e "${G}  [+] Configuration saved.${NC}"
}

edit_interval() {
    local cur_seconds new_seconds
    cur_seconds=$(load_config_value interval_seconds)
    [ -z "$cur_seconds" ] || [ "$cur_seconds" == "null" ] && cur_seconds=3600
    new_seconds=$(prompt_interval "$cur_seconds")
    set_config_number interval_seconds "$new_seconds"
    ensure_cron
    echo -e "${G}  [+] Interval updated to $(format_interval_bash "$new_seconds"). Cron schedule refreshed.${NC}"
}

manual_backup_now() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${R}  Bot is not configured yet. Run Install & Setup first.${NC}"
        sleep 1
        return
    fi
    echo -e "${Y}  Sending manual backup...${NC}"
    if python3 "$BOT_SCRIPT" --backup; then
        echo -e "${G}  [+] Manual backup sent.${NC}"
    else
        echo -e "${R}  [-] Manual backup failed. Check $LOG_FILE for details.${NC}"
    fi
    read -p "  Press Enter..."
}

fix_bot_cache() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${R}  Bot is not configured yet.${NC}"
        sleep 1
        return
    fi
    local token
    token=$(load_config_value bot_token)
    echo -e "${Y}  Resetting Telegram API session...${NC}"
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    curl -s "https://api.telegram.org/bot${token}/deleteWebhook?drop_pending_updates=true" >/dev/null
    curl -s "https://api.telegram.org/bot${token}/close" >/dev/null
    sleep 3
    rm -f "$OFFSET_FILE"
    systemctl start "$SERVICE_NAME"
    echo -e "${G}  [+] API session reset. Bot restarted and should reconnect from this server's IP.${NC}"
    sleep 1
}

install_and_setup() {
    init_dirs
    install_dependencies
    [ -f "$CONFIG_FILE" ] || default_config
    configure_bot
    write_bot_py
    write_checker_script
    write_service_file
    ensure_cron
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    systemctl restart "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${G}  [+] RemnaBot installed and running.${NC}"
        echo -e "${DIM}  Open Telegram and send /start to your bot.${NC}"
    else
        echo -e "${R}  [-] Service failed to start. Check: journalctl -u $SERVICE_NAME -n 50${NC}"
    fi
    read -p "  Press Enter..."
}

edit_bot_menu() {
    while true; do
        banner
        echo -e "${BOLD}${C}  Edit Bot${NC}"
        echo -e "${LINE}"
        echo -e "   ${W}1)${NC} Edit Bot Settings"
        echo -e "   ${W}2)${NC} Edit Cron Job (Backup Interval)"
        echo -e "${LINE}"
        echo -e "   ${W}0)${NC} Back"
        echo -e "${LINE}"
        read -p "  Select: " opt
        case $opt in
            1)
                configure_bot
                systemctl restart "$SERVICE_NAME" 2>/dev/null
                read -p "  Press Enter..."
                ;;
            2)
                edit_interval
                read -p "  Press Enter..."
                ;;
            0) return ;;
            *) echo -e "${R}  Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

remove_bot() {
    echo -e "${Y}  This will remove the bot, its service, config and cron job.${NC}"
    read -p "  Confirm? [y/N]: " c
    if [ "${c,,}" != "y" ]; then
        return
    fi
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    crontab -l 2>/dev/null | grep -v "$CHECKER_SCRIPT" | crontab -
    rm -rf "$INSTALL_DIR"
    echo -e "${G}  [+] RemnaBot removed successfully.${NC}"
    sleep 1
    exit 0
}

show_status() {
    local svc_state interval_seconds interval_fmt last_backup next_backup admin_set

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        svc_state="${G}RUNNING${NC}"
    else
        svc_state="${R}STOPPED${NC}"
    fi

    if [ -f "$CONFIG_FILE" ]; then
        interval_seconds=$(load_config_value interval_seconds)
        [ "$interval_seconds" == "null" ] || [ -z "$interval_seconds" ] && interval_seconds=3600
        interval_fmt=$(format_interval_bash "$interval_seconds")
        admin_set=$(load_config_value admin_id)
        [ -z "$admin_set" ] || [ "$admin_set" == "null" ] && admin_set="${DIM}not set${NC}" || admin_set="${G}set${NC}"
    else
        interval_fmt="${DIM}n/a${NC}"
        admin_set="${DIM}not configured${NC}"
    fi

    if [ -f "$STATE_FILE" ]; then
        local last_ts now diff
        last_ts=$(jq -r '.last_backup_ts // 0' "$STATE_FILE" 2>/dev/null)
        if [ "$last_ts" != "0" ] && [ -n "$last_ts" ]; then
            last_backup=$(date -d "@$last_ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            now=$(date +%s)
            diff=$(( now - last_ts ))
            local remain=$(( interval_seconds - diff ))
            if [ "$remain" -lt 0 ]; then remain=0; fi
            next_backup="in $(format_interval_bash "$remain")"
        else
            last_backup="${DIM}never${NC}"
            next_backup="${DIM}pending${NC}"
        fi
    else
        last_backup="${DIM}never${NC}"
        next_backup="${DIM}pending${NC}"
    fi

    echo -e "  ${W}Service :${NC} ${svc_state}     ${W}Admin:${NC} ${admin_set}"
    echo -e "  ${W}Interval:${NC} ${interval_fmt}   ${W}Last Backup:${NC} ${last_backup}"
    echo -e "  ${W}Next    :${NC} ${next_backup}"
}

banner() {
    clear
    echo -e "${C}${BOLD}"
    cat <<'ART'
  ____                            ____        _   
 |  _ \ ___ _ __ ___  _ __   __ _| __ )  ___ | |_ 
 | |_) / _ \ '_ ` _ \| '_ \ / _` |  _ \ / _ \| __|
 |  _ <  __/ | | | | | | | | (_| | |_) | (_) | |_ 
 |_| \_\___|_| |_| |_|_| |_|\__,_|____/ \___/ \__|
ART
    echo -e "${NC}"
    echo -e "  ${BOLD}${W}Telegram Backup Bot Manager${NC}  ${DIM}v2${NC}"
    echo -e "${LINE}"
    show_status
    echo -e "${LINE}"
}

main_menu() {
    while true; do
        banner
        echo -e "${BOLD}${W}  Main Menu${NC}"
        echo -e "${LINE}"
        echo -e "   ${W}1)${NC} Install & Setup Bot"
        echo -e "   ${W}2)${NC} Manual Backup"
        echo -e "   ${W}3)${NC} Fix Bot Cache (Reset Telegram API)"
        echo -e "   ${W}4)${NC} Edit Bot"
        echo -e "   ${W}5)${NC} Remove Bot"
        echo -e "${LINE}"
        echo -e "   ${W}0)${NC} Exit"
        echo -e "${LINE}"
        read -p "  Select: " opt
        case $opt in
            1) install_and_setup ;;
            2) manual_backup_now ;;
            3) fix_bot_cache ;;
            4) edit_bot_menu ;;
            5) remove_bot ;;
            0) echo -e "${G}  Goodbye.${NC}"; exit 0 ;;
            *) echo -e "${R}  Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

check_root
init_dirs
main_menu
