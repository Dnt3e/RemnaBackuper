#!/bin/bash

# ==============================
# RemnaBackuper
# Creator: Dnt3e
# ==============================

GREEN='\033[0;32m'
NC='\033[0m' # No Color

CONFIG_FILE="$HOME/.remnabackuper.conf"

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
    sudo apt install -y zip curl jq
}

get_server_ip() {
    hostname -I | awk '{print $1}'
}

backup_db() {
    TEMP_SQL="backup.sql"
    ZIPNAME="${BACKUP_NAME}.zip"
    
    echo "[*] Creating PostgreSQL backup..."
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$TEMP_SQL"
    
    echo "[*] Zipping backup..."
    rm -f "$ZIPNAME"
    zip -r "$ZIPNAME" "$TEMP_SQL" >/dev/null 2>&1
    
    echo "[*] Backup file created: $ZIPNAME"
}

send_to_telegram() {
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    SERVER_IP=$(get_server_ip)
    DESCRIPTION="Server IP: $SERVER_IP | Time: $TIMESTAMP"

    echo "[*] Sending backup to Telegram..."
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
         -F chat_id="$ADMIN_ID" \
         -F document=@"$ZIPNAME" \
         -F caption="$DESCRIPTION" >/dev/null
    echo "[*] Backup sent!"
}

cleanup() {
    rm -f "backup.sql" "$ZIPNAME"
    echo "[*] Local backup files removed."
}

test_send() {
    backup_db
    send_to_telegram
    cleanup
}

remove_script() {
    echo "[*] Removing RemnaBackuper..."
    rm -f "$0" "$CONFIG_FILE"
    echo "[*] Done!"
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
    echo "             BACKUPER"
    echo "------------------------------------------"
    echo "           Creator: Dnt3e"
    echo "=========================================="
    echo "1) Start scheduled backup"
    echo "2) Test Telegram send"
    echo "3) Edit configuration"
    echo "4) Remove script"
    echo "5) Exit"
    echo "=========================================="
    printf "${GREEN}Choose an option: ${NC}"
    read -r OPTION
    case $OPTION in
        1)
            echo "[*] Starting scheduled backup every $BACKUP_INTERVAL minutes..."
            while true; do
                backup_db
                send_to_telegram
                cleanup
                sleep "${BACKUP_INTERVAL}m"
            done
            ;;
        2)
            test_send
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
    echo "[*] Configuration saved!"
}

main() {
    install_dependencies
    load_config
    
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        echo "[*] First-time setup:"
        configure_script
    fi
    
    while true; do
        show_menu
    done
}

main
