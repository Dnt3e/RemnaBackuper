#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'

CONFIG_FILE="$HOME/.remnabackuper.conf"
SCRIPT_PATH=$(readlink -f "$0")

DOCKER_BIN=$(which docker)
ZIP_BIN=$(which zip)
CURL_BIN=$(which curl)

BOT_TOKEN=""
ADMIN_ID=""
BACKUP_INTERVAL=60
BACKUP_NAME="RemnaBackuper"
DB_CONTAINER="remnawave-db"
DB_USER="postgres"
DB_NAME="postgres"

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
    TEMP_SQL="$HOME/backup.sql"
    ZIPNAME="$HOME/${BACKUP_NAME}.zip"
    $DOCKER_BIN exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$TEMP_SQL"
    rm -f "$ZIPNAME"
    cd "$HOME" || exit
    $ZIP_BIN -r "${BACKUP_NAME}.zip" "backup.sql" >/dev/null 2>&1
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
    load_config
    backup_db
    send_to_telegram
    cleanup
}

setup_cron() {
    echo -e "${GREEN}Do you want to clear existing crontab entries or keep them?${NC}"
    echo "1) Keep existing and add new backup schedule"
    echo "2) Clear all existing crontab entries and add new"
    read -p "Choice [1/2]: " cron_choice

    if [[ "$cron_choice" == "2" ]]; then
        echo "" > /tmp/cron_tmp
    else
        crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" > /tmp/cron_tmp
    fi

    echo "*/$BACKUP_INTERVAL * * * * /bin/bash $SCRIPT_PATH --run >/dev/null 2>&1" >> /tmp/cron_tmp
    crontab /tmp/cron_tmp
    rm /tmp/cron_tmp
    
    echo -e "${GREEN}[+] Installation Successful! Cron job updated.${NC}"
    echo "[*] Sending a test backup to Telegram..."
    run_full_process
    echo -e "${GREEN}[+] Test backup sent successfully!${NC}"
}

remove_script() {
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    rm -f "$CONFIG_FILE" "$0"
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
    echo "1) Start/Update scheduled backup (Cron)"
    echo "2) Test Telegram send"
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
            echo "[*] Test backup sent!"
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
    printf "${GREEN}Enter backup interval in minutes [$BACKUP_INTERVAL]: ${NC}"
    read -r input
    BACKUP_INTERVAL=${input:-$BACKUP_INTERVAL}
    printf "${GREEN}Enter backup file name (default: RemnaBackuper): ${NC}"
    read -r input
    BACKUP_NAME=${input:-$BACKUP_NAME}
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
    fi
    while true; do
        show_menu
    done
}

main
