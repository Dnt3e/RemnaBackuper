#!/bin/bash

# ==============================
# RemnaBackuper 
# Creator: Dnt3e
# ==============================

GREEN='\033[0;32m'
NC='\033[0m'

CONFIG_FILE="$HOME/.remnabackuper.conf"

if [[ "$0" == *"pipe"* ]] || [[ "$0" == "bash" ]] || [[ "$0" == "/dev/fd/"* ]]; then
    SCRIPT_PATH="/root/remnabackup.sh"
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        curl -fsSL https://raw.githubusercontent.com/Dnt3e/RemnaBackuper/main/remnabackuper.sh -o "$SCRIPT_PATH"
    fi
    chmod +x "$SCRIPT_PATH"
else
    SCRIPT_PATH=$(readlink -f "$0")
    chmod +x "$SCRIPT_PATH"
fi

DOCKER_BIN=$(which docker)
ZIP_BIN=$(which zip)
CURL_BIN=$(which curl)

BOT_TOKEN=""
ADMIN_ID=""
BACKUP_INTERVAL=360
BACKUP_NAME="RemnaBackuper"
DB_CONTAINER="remnawave-db"
DB_USER="postgres"
DB_NAME="postgres"
EXTRA_PATHS=""

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
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
}

install_dependencies() {
    sudo apt update
    sudo apt install -y zip curl jq cron
    sudo systemctl enable cron
    sudo systemctl start cron
}

get_server_ip() {
    hostname -I | awk '{print $1}'
}

backup_db() {
    load_config
    TEMP_SQL="$HOME/backup.sql"
    ZIPNAME="$HOME/${BACKUP_NAME}.zip"
    
    # 1. Dump Database
    $DOCKER_BIN exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$TEMP_SQL"
    
    rm -f "$ZIPNAME"
    cd "$HOME" || exit
    
    # 2. Prepare files list (DB + Default Paths + User Paths)
    DEFAULT_DIRS="/opt/remnawave/ /opt/remnanode/"
    
    # Combine SQL backup with directories
    ALL_TARGETS="backup.sql"
    
    # Check default paths and user custom paths, add only if they exist
    for dir in $DEFAULT_DIRS $EXTRA_PATHS; do
        if [[ -e "$dir" ]]; then
            ALL_TARGETS="$ALL_TARGETS $dir"
        fi
    done
    
    # 3. Create Zip (Simultaneous backup)
    $ZIP_BIN -r "${BACKUP_NAME}.zip" $ALL_TARGETS >/dev/null 2>&1
}

send_to_telegram() {
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    SERVER_IP=$(get_server_ip)
    DESCRIPTION="Server IP: $SERVER_IP | Time: $TIMESTAMP"
    ZIP_PATH="$HOME/${BACKUP_NAME}.zip"
    $CURL_BIN -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
         -F chat_id="$ADMIN_ID" \
         -F document=@"$ZIP_PATH" \
         -F caption="$DESCRIPTION" >/dev/null
}

cleanup() {
    rm -f "$HOME/backup.sql" "$HOME/${BACKUP_NAME}.zip"
}

run_full_process() {
    backup_db
    send_to_telegram
    cleanup
}

build_cron_expression() {
    local interval_minutes=$1
    local cron_expr

    if (( interval_minutes < 60 )); then
        cron_expr="*/$interval_minutes * * * *"
    elif (( interval_minutes % 60 == 0 )); then
        local hours=$(( interval_minutes / 60 ))
        cron_expr="0 */$hours * * *"
    else
        local hours=$(( interval_minutes / 60 ))
        local mins=$(( interval_minutes % 60 ))
        echo -e "${GREEN}[WARN] $interval_minutes minutes is not a clean hour multiple.${NC}" >&2
        echo -e "       Using schedule: at minute $mins of every $hours hours" >&2
        cron_expr="$mins */$hours * * *"
    fi

    echo "$cron_expr"
}

setup_cron() {
    echo -e "${GREEN}Do you want to clear existing crontab entries or keep them?${NC}"
    echo "1) Keep existing and add new backup schedule"
    echo "2) Clear all existing crontab entries and add new"
    read -p "Choice [1/2]: " cron_choice

    if [[ "$cron_choice" == "2" ]]; then
        echo "" > /tmp/cron_tmp
    else
        crontab -l 2>/dev/null | grep -v "remnabackup.sh" | grep -v "$SCRIPT_PATH" > /tmp/cron_tmp
    fi

    CRON_EXPR=$(build_cron_expression "$BACKUP_INTERVAL")
    echo "$CRON_EXPR /bin/bash $SCRIPT_PATH --run >/dev/null 2>&1" >> /tmp/cron_tmp
    crontab /tmp/cron_tmp
    rm /tmp/cron_tmp

    echo -e "${GREEN}[+] Installation/Restart Successful! Cron job updated.${NC}"
    echo -e "    Schedule: [$CRON_EXPR] = every $BACKUP_INTERVAL minutes"
    echo "[*] Sending an initial backup to Telegram..."
    run_full_process
    echo -e "${GREEN}[+] Initial backup sent successfully!${NC}"
}

remove_script() {
    crontab -l 2>/dev/null | grep -v "remnabackup.sh" | grep -v "$SCRIPT_PATH" | crontab -
    rm -f "$CONFIG_FILE" "$SCRIPT_PATH"
    echo -e "${GREEN}[+] Uninstalled successfully! Settings and Cron jobs removed.${NC}"
    exit 0
}

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
    show_backup_status
    echo -e "${LINE}"
}

show_backup_status() {
    load_config
    local next_run=""
    local cron_line
    cron_line=$(crontab -l 2>/dev/null | grep "$SCRIPT_PATH" | head -1)
    if [[ -n "$cron_line" ]]; then
        next_run="${G}Active${NC}"
    else
        next_run="${R}Not scheduled${NC}"
    fi
    local interval_display="${BACKUP_INTERVAL} min"
    if (( BACKUP_INTERVAL >= 60 )) && (( BACKUP_INTERVAL % 60 == 0 )); then
        interval_display="$(( BACKUP_INTERVAL / 60 ))h"
    fi
    echo -e "  ${W}Schedule :${NC} ${next_run}  ${DIM}(every ${interval_display})${NC}"
    if [[ -n "$BOT_TOKEN" && -n "$ADMIN_ID" ]]; then
        echo -e "  ${W}Telegram :${NC} ${G}Configured${NC}  ${DIM}(ID: ${ADMIN_ID})${NC}"
    else
        echo -e "  ${W}Telegram :${NC} ${R}Not configured${NC}"
    fi
}

show_menu() {
    while true; do
        banner
        echo -e "${BOLD}${W}  Main Menu${NC}"
        echo -e "${LINE}"
        echo -e "   ${W}1)${NC} 🔄  Restart / Update Cron"
        echo -e "   ${W}2)${NC} 📤  Manual Backup  ${DIM}(send now)${NC}"
        echo -e "   ${W}3)${NC} ⚙️   Edit Configuration"
        echo -e "${LINE}"
        echo -e "   ${W}4)${NC} 🗑️   Remove Script"
        echo -e "${LINE}"
        echo -e "   ${W}0)${NC} 🚪  Exit"
        echo -e "${LINE}"
        read -p "  Select: " OPTION
        case $OPTION in
            1)
                setup_cron
                ;;
            2)
                run_full_process
                echo -e "${G}  [OK] Manual backup sent!${NC}"
                read -p "  Press Enter..."
                ;;
            3)
                configure_script
                ;;
            4)
                remove_script
                ;;
            0)
                echo -e "${G}  Goodbye.${NC}"; exit 0
                ;;
            *)
                echo -e "${R}  Invalid option.${NC}"; sleep 1
                ;;
        esac
    done
}

configure_script() {
    banner
    echo -e "${BOLD}${C}  ⚙️  Configuration${NC}"
    echo -e "${LINE}"
    printf "${W}  Telegram bot token ${DIM}[$BOT_TOKEN]${NC}: "
    read -r input
    BOT_TOKEN=${input:-$BOT_TOKEN}
    printf "${W}  Telegram admin ID ${DIM}[$ADMIN_ID]${NC}: "
    read -r input
    ADMIN_ID=${input:-$ADMIN_ID}
    while true; do
        printf "${W}  Backup interval in MINUTES ${DIM}(e.g. 360 = 6h)${NC} ${DIM}[$BACKUP_INTERVAL]${NC}: "
        read -r input
        input=${input:-$BACKUP_INTERVAL}
        if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input >= 1 && input <= 1440 )); then
            BACKUP_INTERVAL=$input
            break
        else
            echo "Invalid input. Please enter a number between 1 and 1440."
        fi
    done
    echo -e "${LINE}"
    printf "${W}  Backup file name ${DIM}[$BACKUP_NAME]${NC}: "
    read -r input
    BACKUP_NAME=${input:-$BACKUP_NAME}

    # --- New Section for Custom Paths ---
    echo -e "${LINE}"
    echo -e "  ${BOLD}${C}Extra Backup Paths${NC}"
    echo -e "  ${DIM}Default paths: /opt/remnawave/  /opt/remnanode/${NC}"
    echo -e "${LINE}"
    echo -e "  Add MORE custom paths/folders to the backup:"
    
    TEMP_PATHS="$EXTRA_PATHS" 
    
    while true; do
        echo -e "  Type ${G}add${NC} to add a path, or ${W}done${NC} to finish."
        read -r action
        
        if [[ "$action" == "done" ]]; then
            break
        elif [[ "$action" == "add" ]]; then
            printf "  Full path (e.g. /var/www/html): "
            read -r new_path
            if [[ -n "$new_path" ]]; then
                TEMP_PATHS="$TEMP_PATHS $new_path"
                echo -e "  ${G}[+] Path added: $new_path${NC}"
            else
                echo "Path cannot be empty."
            fi
        else
            echo "Invalid input. Please type 'add' or 'done'."
        fi
    done
    EXTRA_PATHS="$TEMP_PATHS"
    # ------------------------------------

    save_config
    echo -e "${LINE}"
    echo -e "  ${G}[OK] Configuration saved.${NC}"
    read -p "  Press Enter..."
}

if [[ "$1" == "--run" ]]; then
    run_full_process
    exit 0
fi

main() {
    install_dependencies
    load_config
    _cache_prereqs 2>/dev/null || true
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        configure_script
        setup_cron
    fi
    show_menu
}

_cache_prereqs() {
    : # placeholder — prereqs shown in banner via show_backup_status
}

main
