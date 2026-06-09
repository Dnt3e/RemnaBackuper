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

show_menu() {
    echo "=========================================="
    echo "  _____  ______ __  __ _   _          "
    echo " |  __ \|  ____|  \/  | \ | |   /\    "
    echo " | |__) | |__  | \  / |  \| |  /  \   "
    echo " |  _  /|  __| | |\/| | . \` | / /\ \  "
    echo " | | \ \| |____| |  | | |\  |/ ____ \ "
    echo " |_|  \_\______|_|  |_|_| \_/_/    \_\\"
    echo "               BACKUPER"
    echo "------------------------------------------"
    echo "            Creator: Dnt3e"
    echo "=========================================="
    echo "1) Restart Script (Update Cron)"
    echo "2) Manual Backup (Send Now)"
    echo "3) Edit configuration"
    echo "4) Remove script"
    echo "5) Exit"
    echo "=========================================="
    printf "${GREEN}Choose an option: ${NC}"
    read -r OPTION
    case $OPTION in
        1)
            setup_cron
            ;;
        2)
            run_full_process
            echo -e "${GREEN}[*] Manual backup sent!${NC}"
            ;;
        3)
            configure_script
            ;;
        4)
            remove_script
            ;;
        5)
            exit 0
            ;;
        *)
            echo "Invalid option!"
            ;;
    esac
}

configure_script() {
    printf "${GREEN}Enter Telegram bot token [$BOT_TOKEN]: ${NC}"
    read -r input
    BOT_TOKEN=${input:-$BOT_TOKEN}
    printf "${GREEN}Enter Telegram admin ID [$ADMIN_ID]: ${NC}"
    read -r input
    ADMIN_ID=${input:-$ADMIN_ID}
    while true; do
        printf "${GREEN}Enter backup interval in MINUTES (e.g., 360 = every 6 hours) [$BACKUP_INTERVAL]: ${NC}"
        read -r input
        input=${input:-$BACKUP_INTERVAL}
        if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input >= 1 && input <= 1440 )); then
            BACKUP_INTERVAL=$input
            break
        else
            echo "Invalid input. Please enter a number between 1 and 1440."
        fi
    done
    printf "${GREEN}Enter backup file name (default: RemnaBackuper): ${NC}"
    read -r input
    BACKUP_NAME=${input:-$BACKUP_NAME}

    # --- New Section for Custom Paths ---
    echo "------------------------------------------------------"
    echo -e "${GREEN}[INFO] By default, this script backs up the Database AND these paths if they exist:${NC}"
    echo -e "       - /opt/remnawave/"
    echo -e "       - /opt/remnanode/"
    echo "------------------------------------------------------"
    echo "Do you want to add MORE custom paths/folders to the backup?"
    
    TEMP_PATHS="$EXTRA_PATHS" 
    
    while true; do
        echo -e "Type '${GREEN}add${NC}' to add a path, or '${GREEN}done${NC}' to finish configuration."
        read -r action
        
        if [[ "$action" == "done" ]]; then
            break
        elif [[ "$action" == "add" ]]; then
            printf "Enter full path (e.g., /var/www/html): "
            read -r new_path
            if [[ -n "$new_path" ]]; then
                TEMP_PATHS="$TEMP_PATHS $new_path"
                echo -e "${GREEN}Path added: $new_path${NC}"
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
    echo "[*] Configuration updated!"
}

if [[ "$1" == "--run" ]]; then
    run_full_process
    exit 0
fi

main() {
    install_dependencies
    load_config
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        configure_script
        setup_cron
    fi
    while true; do
        show_menu
    done
}

main
