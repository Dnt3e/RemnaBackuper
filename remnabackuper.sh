#!/bin/bash

# ==============================
# RemnaBackuper
# Creator: Dnt3e
# ==============================

# ── Colors & UI ──────────────────────────────────────────────
G="\e[32m"; Y="\e[33m"; R="\e[31m"; C="\e[36m"; W="\e[97m"
DIM="\e[2m"; BOLD="\e[1m"; NC="\e[0m"
LINE="${DIM}────────────────────────────────────────────────────────${NC}"
GREEN="\e[32m"

# ── Paths ────────────────────────────────────────────────────
CONFIG_FILE="$HOME/.remnabackuper.conf"
BOT_PID_FILE="/tmp/remnabackuper_bot.pid"

# ── Script self-path detection ───────────────────────────────
if [[ "$0" == *"pipe"* ]] || [[ "$0" == "bash" ]] || [[ "$0" == "/dev/fd/"* ]]; then
    SCRIPT_PATH="/root/remnabackup.sh"
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        curl -fsSL https://raw.githubusercontent.com/Dnt3e/RemnaBackuper/main/remnabackuper.sh \
            -o "$SCRIPT_PATH"
    fi
    chmod +x "$SCRIPT_PATH"
else
    SCRIPT_PATH=$(readlink -f "$0")
    chmod +x "$SCRIPT_PATH"
fi

# ── Defaults (overridden by load_config) ─────────────────────
BOT_TOKEN=""
ADMIN_ID=""
BACKUP_INTERVAL=360
BACKUP_NAME="RemnaBackuper"
DB_CONTAINER="remnawave-db"
DB_USER="postgres"
DB_NAME="postgres"
EXTRA_PATHS=""

# ── Config I/O ───────────────────────────────────────────────
load_config() {
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}

save_config() {
    cat > "$CONFIG_FILE" <<EOL
BOT_TOKEN="$BOT_TOKEN"
ADMIN_ID="$ADMIN_ID"
BACKUP_INTERVAL="$BACKUP_INTERVAL"
BACKUP_NAME="$BACKUP_NAME"
DB_CONTAINER="$DB_CONTAINER"
DB_USER="$DB_USER"
DB_NAME="$DB_NAME"
EXTRA_PATHS="$EXTRA_PATHS"
EOL
    chmod 600 "$CONFIG_FILE"
}

# ── Dependencies ─────────────────────────────────────────────
install_dependencies() {
    apt-get update -qq
    apt-get install -y zip curl jq cron >/dev/null 2>&1
    systemctl enable cron >/dev/null 2>&1
    systemctl start  cron >/dev/null 2>&1
}

# ── Helpers ──────────────────────────────────────────────────
get_server_ip() {
    hostname -I | awk '{print $1}'
}

_curl() {
    curl -s --max-time 30 "$@"
}

# ── Backup ───────────────────────────────────────────────────
backup_db() {
    load_config

    local DOCKER_BIN ZIP_BIN
    DOCKER_BIN=$(command -v docker 2>/dev/null)
    ZIP_BIN=$(command -v zip 2>/dev/null)

    if [[ -z "$DOCKER_BIN" ]]; then
        echo -e "${R}  [ERR] docker not found in PATH.${NC}" >&2
        return 1
    fi
    if [[ -z "$ZIP_BIN" ]]; then
        echo -e "${R}  [ERR] zip not found. Run install to fix.${NC}" >&2
        return 1
    fi

    local TEMP_SQL="$HOME/backup.sql"
    local ZIPFILE="$HOME/${BACKUP_NAME}.zip"

    if ! $DOCKER_BIN exec "$DB_CONTAINER" \
            pg_dump -U "$DB_USER" "$DB_NAME" > "$TEMP_SQL" 2>/dev/null; then
        echo -e "${R}  [ERR] pg_dump failed. Is '${DB_CONTAINER}' running?${NC}" >&2
        rm -f "$TEMP_SQL"
        return 1
    fi

    rm -f "$ZIPFILE"

    local DEFAULT_DIRS="/opt/remnawave/ /opt/remnanode/"
    local ALL_TARGETS="backup.sql"
    for dir in $DEFAULT_DIRS $EXTRA_PATHS; do
        [[ -e "$dir" ]] && ALL_TARGETS="$ALL_TARGETS $dir"
    done

    pushd "$HOME" > /dev/null || return 1
    $ZIP_BIN -r "${BACKUP_NAME}.zip" $ALL_TARGETS >/dev/null 2>&1
    local rc=$?
    popd > /dev/null

    if [[ $rc -ne 0 ]]; then
        echo -e "${R}  [ERR] zip failed (exit $rc).${NC}" >&2
        return 1
    fi
    return 0
}

# ── Telegram send ────────────────────────────────────────────
send_to_telegram() {
    load_config

    local ZIP_PATH="$HOME/${BACKUP_NAME}.zip"
    if [[ ! -f "$ZIP_PATH" ]]; then
        echo -e "${R}  [ERR] Backup file not found: $ZIP_PATH${NC}" >&2
        return 1
    fi

    local TIMESTAMP SERVER_IP DESCRIPTION
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    SERVER_IP=$(get_server_ip)
    DESCRIPTION="Server IP: $SERVER_IP | Time: $TIMESTAMP"

    local resp
    resp=$(_curl -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        -F chat_id="$ADMIN_ID" \
        -F document=@"$ZIP_PATH" \
        -F caption="$DESCRIPTION")

    if echo "$resp" | grep -q '"ok":true'; then
        return 0
    else
        local err
        err=$(echo "$resp" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); print(d.get('description','Unknown error'))" \
            2>/dev/null || echo "Unknown error")
        echo -e "${R}  [ERR] Telegram: ${err}${NC}" >&2
        return 1
    fi
}

# ── Telegram message helper ───────────────────────────────────
tg_send_message() {
    local chat_id="$1" text="$2"
    _curl -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" >/dev/null
}

# ── Cleanup ──────────────────────────────────────────────────
cleanup() {
    rm -f "$HOME/backup.sql" "$HOME/${BACKUP_NAME}.zip"
}

# ── Full backup process ───────────────────────────────────────
run_full_process() {
    echo -e "  ${DIM}Creating backup...${NC}"
    if ! backup_db; then
        cleanup; return 1
    fi
    echo -e "  ${DIM}Sending to Telegram...${NC}"
    if ! send_to_telegram; then
        cleanup; return 1
    fi
    cleanup
    return 0
}

# ── Cron expression builder ───────────────────────────────────
# The cron minutes field only accepts 0-59.
# */360 is invalid and causes some daemons to run every minute instead.
build_cron_expression() {
    local minutes=$1
    if   (( minutes < 60 ));          then echo "*/$minutes * * * *"
    elif (( minutes % 60 == 0 ));     then echo "0 */$(( minutes / 60 )) * * *"
    else echo "$(( minutes % 60 )) */$(( minutes / 60 )) * * *"
    fi
}

# ── Cron setup ───────────────────────────────────────────────
setup_cron() {
    banner
    echo -e "${BOLD}${C}  🔄 Update Cron Schedule${NC}"
    echo -e "${LINE}"
    echo -e "   ${W}1)${NC} Keep existing entries and add new schedule"
    echo -e "   ${W}2)${NC} Clear all crontab entries and start fresh"
    echo -e "${LINE}"
    read -p "  Choice [1/2]: " cron_choice

    local tmp_cron="/tmp/remnabackuper_cron_$$"

    if [[ "$cron_choice" == "2" ]]; then
        echo "" > "$tmp_cron"
    else
        crontab -l 2>/dev/null \
            | grep -v "remnabackup.sh" \
            | grep -v "$SCRIPT_PATH" \
            > "$tmp_cron"
    fi

    local cron_expr
    cron_expr=$(build_cron_expression "$BACKUP_INTERVAL")
    echo "$cron_expr /bin/bash $SCRIPT_PATH --run >/dev/null 2>&1" >> "$tmp_cron"
    crontab "$tmp_cron"
    rm -f "$tmp_cron"

    echo -e "${LINE}"
    echo -e "  ${G}[OK] Cron updated.${NC}  ${DIM}[$cron_expr]  every ${BACKUP_INTERVAL} min${NC}"
    echo -e "  ${DIM}Sending initial backup...${NC}"
    if run_full_process; then
        echo -e "  ${G}[OK] Initial backup sent.${NC}"
    else
        echo -e "  ${R}[FAIL] Initial backup failed. Check configuration.${NC}"
    fi
    read -p "  Press Enter..."
}

# ── Remove ───────────────────────────────────────────────────
remove_script() {
    banner
    echo -e "${BOLD}${R}  🗑️  Remove RemnaBackuper${NC}"
    echo -e "${LINE}"
    echo -e "  ${Y}This will remove the script, config, cron job, and bot daemon.${NC}"
    echo -e "${LINE}"
    read -p "  Confirm? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && return

    stop_bot_daemon 2>/dev/null
    crontab -l 2>/dev/null \
        | grep -v "remnabackup.sh" \
        | grep -v "$SCRIPT_PATH" \
        | crontab -
    rm -f "$CONFIG_FILE" "$BOT_PID_FILE"
    echo -e "  ${G}[OK] Uninstalled successfully.${NC}"
    rm -f "$SCRIPT_PATH"
    exit 0
}

# ── Telegram bot listener (long-polling daemon) ───────────────
poll_telegram_bot() {
    local offset=0

    while true; do
        local raw
        raw=$(curl -s --max-time 35 \
            "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${offset}&timeout=30&allowed_updates=%5B%22message%22%5D")

        local updates
        updates=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for r in d.get('result', []):
        print(json.dumps(r))
except:
    pass
" 2>/dev/null)

        while IFS= read -r upd; do
            [[ -z "$upd" ]] && continue

            local upd_id chat_id from_id text
            upd_id=$(echo "$upd"  | python3 -c "import sys,json; print(json.load(sys.stdin).get('update_id',''))"                                      2>/dev/null)
            chat_id=$(echo "$upd" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',{}).get('chat',{}).get('id',''))"            2>/dev/null)
            from_id=$(echo "$upd" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',{}).get('from',{}).get('id',''))"            2>/dev/null)
            text=$(echo    "$upd" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',{}).get('text',''))"                         2>/dev/null)

            [[ -n "$upd_id" ]] && offset=$(( upd_id + 1 ))

            # Only respond to configured admin
            [[ "$from_id" != "$ADMIN_ID" ]] && continue

            # Strip bot username suffix (e.g. /backup@MyBot -> /backup)
            text="${text%%@*}"

            case "$text" in
                /backup)
                    tg_send_message "$chat_id" "⏳ Taking backup, please wait..."
                    if run_full_process >/dev/null 2>&1; then
                        tg_send_message "$chat_id" "✅ Backup sent successfully!"
                    else
                        tg_send_message "$chat_id" "❌ Backup failed. Check server logs."
                    fi
                    ;;
                /status)
                    local ip cron_line sched
                    ip=$(get_server_ip)
                    cron_line=$(crontab -l 2>/dev/null | grep "$SCRIPT_PATH" | head -1)
                    sched="Not scheduled"
                    [[ -n "$cron_line" ]] && sched="Active (every ${BACKUP_INTERVAL} min)"
                    tg_send_message "$chat_id" \
                        "$(printf '📊 RemnaBackuper Status\n🖥 IP: %s\n⏱ Schedule: %s' "$ip" "$sched")"
                    ;;
                /help)
                    tg_send_message "$chat_id" \
                        "$(printf '🤖 RemnaBackuper Bot\n\n/backup — Take a manual backup now\n/status — Show server and schedule info\n/help   — Show this message')"
                    ;;
            esac
        done <<< "$updates"

        sleep 1
    done
}

# ── Bot daemon management ─────────────────────────────────────
start_bot_daemon() {
    load_config
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        echo -e "${R}  [ERR] BOT_TOKEN or ADMIN_ID not configured.${NC}"
        return 1
    fi
    stop_bot_daemon 2>/dev/null
    nohup /bin/bash "$SCRIPT_PATH" --bot >> /tmp/remnabackuper_bot.log 2>&1 &
    local pid=$!
    echo $pid > "$BOT_PID_FILE"
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${G}  [OK] Bot daemon started (PID: ${pid}).${NC}"
    else
        echo -e "${R}  [ERR] Bot daemon failed. Check /tmp/remnabackuper_bot.log${NC}"
    fi
}

stop_bot_daemon() {
    if [[ -f "$BOT_PID_FILE" ]]; then
        local pid
        pid=$(cat "$BOT_PID_FILE")
        kill "$pid" 2>/dev/null && echo -e "${G}  [OK] Bot daemon stopped.${NC}" || true
        rm -f "$BOT_PID_FILE"
    else
        echo -e "${Y}  [INFO] Bot daemon is not running.${NC}"
    fi
}

bot_daemon_running() {
    [[ -f "$BOT_PID_FILE" ]] || return 1
    local pid; pid=$(cat "$BOT_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then return 0; fi
    rm -f "$BOT_PID_FILE"
    return 1
}

# ── Banner ───────────────────────────────────────────────────
banner() {
    clear
    echo -e "${G}"
    echo "  ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗ "
    echo "  ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗"
    echo "  ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝"
    echo "  ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝ "
    echo "  ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║     "
    echo "  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
    echo -e "${NC}"
    echo -e "  ${BOLD}${W}RemnaBackuper${NC}  ${DIM}v1${NC}"
    echo -e "  ${DIM}Creator: Dnt3e${NC}"
    echo -e "${LINE}"
    _show_status_line
    echo -e "${LINE}"
}

_show_status_line() {
    load_config

    local cron_line sched_label interval_display
    cron_line=$(crontab -l 2>/dev/null | grep "$SCRIPT_PATH" | head -1)
    if [[ -n "$cron_line" ]]; then
        sched_label="${G}Active${NC}"
    else
        sched_label="${R}Not scheduled${NC}"
    fi
    if (( BACKUP_INTERVAL >= 60 && BACKUP_INTERVAL % 60 == 0 )); then
        interval_display="$(( BACKUP_INTERVAL / 60 ))h"
    else
        interval_display="${BACKUP_INTERVAL}m"
    fi
    echo -e "  ${W}Schedule :${NC} ${sched_label}  ${DIM}(every ${interval_display})${NC}"

    if [[ -n "$BOT_TOKEN" && -n "$ADMIN_ID" ]]; then
        echo -e "  ${W}Telegram :${NC} ${G}Configured${NC}  ${DIM}(Admin ID: ${ADMIN_ID})${NC}"
    else
        echo -e "  ${W}Telegram :${NC} ${R}Not configured${NC}"
    fi

    if bot_daemon_running; then
        local pid; pid=$(cat "$BOT_PID_FILE")
        echo -e "  ${W}Bot      :${NC} ${G}Running${NC}  ${DIM}(PID: ${pid})${NC}"
    else
        echo -e "  ${W}Bot      :${NC} ${Y}Stopped${NC}"
    fi
}

# ── Bot daemon menu ───────────────────────────────────────────
bot_daemon_menu() {
    while true; do
        banner
        echo -e "${BOLD}${C}  🤖 Bot Daemon${NC}"
        echo -e "${LINE}"
        echo -e "  ${DIM}Telegram commands available when bot is running:${NC}"
        echo -e "  ${DIM}  /backup  — trigger a manual backup now${NC}"
        echo -e "  ${DIM}  /status  — show server and schedule info${NC}"
        echo -e "  ${DIM}  /help    — list available commands${NC}"
        echo -e "${LINE}"
        echo -e "   ${W}1)${NC} ▶   Start Bot Daemon"
        echo -e "   ${W}2)${NC} ⏹   Stop Bot Daemon"
        echo -e "${LINE}"
        echo -e "   ${W}0)${NC} ←   Back"
        echo -e "${LINE}"
        read -p "  Select: " opt
        case $opt in
            1) start_bot_daemon; read -p "  Press Enter..." ;;
            2) stop_bot_daemon;  read -p "  Press Enter..." ;;
            0) return ;;
            *) echo -e "${R}  Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

# ── Configuration menu ────────────────────────────────────────
configure_script() {
    banner
    echo -e "${BOLD}${C}  ⚙️  Configuration${NC}"
    echo -e "${LINE}"

    printf "${W}  Telegram bot token ${DIM}[${BOT_TOKEN}]${NC}: "
    read -r input; BOT_TOKEN="${input:-$BOT_TOKEN}"

    printf "${W}  Telegram admin ID  ${DIM}[${ADMIN_ID}]${NC}: "
    read -r input; ADMIN_ID="${input:-$ADMIN_ID}"

    while true; do
        printf "${W}  Backup interval in minutes ${DIM}(1-1440, e.g. 360=6h) [${BACKUP_INTERVAL}]${NC}: "
        read -r input
        input="${input:-$BACKUP_INTERVAL}"
        if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input >= 1 && input <= 1440 )); then
            BACKUP_INTERVAL="$input"; break
        else
            echo -e "${R}  Invalid. Enter a number between 1 and 1440.${NC}"
        fi
    done

    printf "${W}  Backup file name   ${DIM}[${BACKUP_NAME}]${NC}: "
    read -r input; BACKUP_NAME="${input:-$BACKUP_NAME}"

    echo -e "${LINE}"
    echo -e "  ${BOLD}${C}Extra Backup Paths${NC}"
    echo -e "  ${DIM}Default paths: /opt/remnawave/  /opt/remnanode/${NC}"
    echo -e "${LINE}"

    local TEMP_PATHS="$EXTRA_PATHS"
    while true; do
        echo -e "  Type ${G}add${NC} to add a path, ${R}clear${NC} to reset extra paths, or ${W}done${NC} to finish."
        [[ -n "$TEMP_PATHS" ]] && echo -e "  ${DIM}Current extra paths:${TEMP_PATHS}${NC}"
        read -r action
        case "$action" in
            done)  break ;;
            clear) TEMP_PATHS=""; echo -e "  ${Y}[INFO] Extra paths cleared.${NC}" ;;
            add)
                printf "  Full path (e.g. /var/www/html): "
                read -r new_path
                if [[ -n "$new_path" ]]; then
                    TEMP_PATHS="$TEMP_PATHS $new_path"
                    echo -e "  ${G}[+] Added: $new_path${NC}"
                else
                    echo -e "${R}  Path cannot be empty.${NC}"
                fi
                ;;
            *) echo -e "${R}  Invalid. Type 'add', 'clear', or 'done'.${NC}" ;;
        esac
    done
    EXTRA_PATHS="${TEMP_PATHS# }"

    save_config
    echo -e "${LINE}"
    echo -e "  ${G}[OK] Configuration saved.${NC}"
    read -p "  Press Enter..."
}

# ── Main menu ─────────────────────────────────────────────────
show_menu() {
    while true; do
        banner
        echo -e "${BOLD}${W}  Main Menu${NC}"
        echo -e "${LINE}"
        echo -e "   ${W}1)${NC} 🔄  Restart / Update Cron"
        echo -e "   ${W}2)${NC} 📤  Manual Backup  ${DIM}(send now)${NC}"
        echo -e "   ${W}3)${NC} ⚙️   Edit Configuration"
        echo -e "   ${W}4)${NC} 🤖  Bot Daemon  ${DIM}(/backup, /status via Telegram)${NC}"
        echo -e "${LINE}"
        echo -e "   ${W}5)${NC} 🗑️   Remove Script"
        echo -e "${LINE}"
        echo -e "   ${W}0)${NC} 🚪  Exit"
        echo -e "${LINE}"
        read -p "  Select: " OPTION
        case $OPTION in
            1) setup_cron ;;
            2)
                banner
                echo -e "${BOLD}${C}  📤 Manual Backup${NC}"
                echo -e "${LINE}"
                if run_full_process; then
                    echo -e "  ${G}[OK] Backup sent successfully!${NC}"
                else
                    echo -e "  ${R}[FAIL] Backup failed. See errors above.${NC}"
                fi
                read -p "  Press Enter..."
                ;;
            3) configure_script ;;
            4) bot_daemon_menu ;;
            5) remove_script ;;
            0) echo -e "${G}  Goodbye.${NC}"; exit 0 ;;
            *) echo -e "${R}  Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

# ── Entry points ─────────────────────────────────────────────
case "${1:-}" in
    --run)
        load_config
        run_full_process
        exit $?
        ;;
    --bot)
        load_config
        poll_telegram_bot
        exit 0
        ;;
esac

# ── Main ─────────────────────────────────────────────────────
main() {
    install_dependencies
    load_config
    show_menu
}

main
