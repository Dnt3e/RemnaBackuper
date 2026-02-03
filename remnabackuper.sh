#!/bin/bash

CONFIG_FILE="$HOME/.remnabackuper.conf"

BOT_TOKEN=""
ADMIN_ID=""
BACKUP_INTERVAL=60
BACKUP_NAME="backup"
DB_CONTAINER="remnawave-db"
DB_USER="postgres"
DB_NAME="postgres"

GREEN='\033[0;32m'
NC='\033[0m'

FILENAME="backup.sql"
ZIPNAME="RemnaBackuper.zip"

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
    echo "[*] Creating PostgreSQL backup..."
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$FILENAME"
    
    if [ -s "$FILENAME" ]; then
        echo "[*] Zipping backup with 5% recovery record..."
        zip -r -RE 5 "$ZIPNAME" "$FILENAME" >/dev/null 2>&1
        return 0
    else
        return 1
    fi
}

send_to_telegram() {
    local status=$1
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    SERVER_IP=$(get_server_ip)
    
    if [ "$status" -eq 0 ]; then
        CAPTION="✅ Backup Successful%0AServer IP: $SERVER_IP%0ATime: $TIMESTAMP"
        RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
             -F chat_id="$ADMIN_ID" \
             -F document=@"$ZIPNAME" \
             -F caption="$CAPTION")
        
        if echo "$RESPONSE" | grep -q '"ok":true'; then
            echo "[*] Backup sent successfully!"
        else
            echo "[!] Telegram API Error: $RESPONSE"
        fi
    else
        CAPTION="❌ Backup Failed!%0AServer IP: $SERVER_IP%0ATime: $TIMESTAMP"
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
             -d chat_id="$ADMIN_ID" \
             -d text="$CAPTION" >/dev/null
        echo "[!] Failure notification sent!"
    fi
}

cleanup() {
    rm -f "$FILENAME" "$ZIPNAME"
}

test_send() {
    if backup_db; then
        send_to_telegram 0
    else
        send_to_telegram 1
    fi
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
    echo "  ____  _____ __  __ _   _    _    "
    echo " |  _ \| ____|  \/  | \ | |  / \   "
    echo " | |_) |  _| | |\/| |  \| | / _ \  "
    echo " |  _ <| |___| |  | | |\  |/ ___ \ "
    echo " |_| \_\_____|_|  |_|_| \_/_/   \_\\"
    echo "            BACKUPER"
    echo "------------------------------------------"
    echo "          Creator: Dnt3e"
    echo "=========================================="
    echo "1) Start scheduled backup"
    echo "2) Test Telegram send"
    echo "3) Edit configuration"
    echo "4) Remove script"
    echo "5) Exit"
    echo "=========================================="
    echo -ne "${GREEN}Choose an option: ${NC}"
    read -r OPTION
    case $OPTION in
        1)
            echo "[*] Starting scheduled backup every $BACKUP_INTERVAL minutes..."
            while true; do
                if backup_db; then
                    send_to_telegram 0
                else
                    send_to_telegram 1
                fi
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
    echo -ne "${GREEN}Enter Telegram bot token [$BOT_TOKEN]: ${NC}"
    read -r input
    BOT_TOKEN=${input:-$BOT_TOKEN}
    
    echo -ne "${GREEN}Enter Telegram admin ID [$ADMIN_ID]: ${NC}"
    read -r input
    ADMIN_ID=${input:-$ADMIN_ID}
    
    echo -ne "${GREEN}Enter backup interval in minutes [$BACKUP_INTERVAL]: ${NC}"
    read -r input
    BACKUP_INTERVAL=${input:-$BACKUP_INTERVAL}
    
    echo -ne "${GREEN}Enter DB Container Name [$DB_CONTAINER]: ${NC}"
    read -r input
    DB_CONTAINER=${input:-$DB_CONTAINER}
    
    save_config
    echo "[*] Configuration saved!"
}

main() {
    install_dependencies
    load_config
    
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        echo "[*] First-time setup:"
        configure_script
        echo "[*] Running initial test backup..."
        test_send
    fi
    
    while true; do
        show_menu
    done
}

main
