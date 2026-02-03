#!/bin/bash

CONFIG_FILE="$HOME/.remnabackuper.conf"

BOT_TOKEN=""
ADMIN_ID=""
BACKUP_INTERVAL=60
BACKUP_NAME="RemnaBackuper"
DB_CONTAINER="remnawave-db"
DB_USER="postgres"
DB_NAME="postgres"

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
EOL
}

install_dependencies() {
    echo "[*] Installing dependencies..."
    local i=0
    while [ $i -le 100 ]; do
        echo -ne "Installing... $i%\r"
        sleep 0.05
        ((i+=5))
    done
    sudo apt update && sudo apt install -y zip curl jq >/dev/null 2>&1
    echo -e "Installing... 100%\n[*] Dependencies installed!"
}

get_server_ip() {
    hostname -I | awk '{print $1}'
}

backup_db() {
    FILENAME="backup.sql"
    ZIPNAME="${BACKUP_NAME}.zip"
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$FILENAME"
    zip -r -F "$ZIPNAME" "$FILENAME" >/dev/null 2>&1
    echo "[*] Backup ZIP created: $ZIPNAME"
}

send_to_telegram() {
    SERVER_IP=$(get_server_ip)
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    DESCRIPTION="Server IP: $SERVER_IP | Time: $TIMESTAMP"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
         -F chat_id="$ADMIN_ID" \
         -F document=@"$ZIPNAME" \
         -F caption="$DESCRIPTION" >/dev/null
    echo "[*] Backup sent!"
}

cleanup() {
    rm -f backup.sql "$ZIPNAME"
}

test_send() {
    backup_db
    send_to_telegram
    cleanup
}

remove_script() {
    rm -f "$0" "$CONFIG_FILE"
    echo "[*] RemnaBackuper removed!"
    exit 0
}

configure_script() {
    read -rp "Enter Telegram bot token [$BOT_TOKEN]: " input
    BOT_TOKEN=${input:-$BOT_TOKEN}
    read -rp "Enter Telegram admin ID [$ADMIN_ID]: " input
    ADMIN_ID=${input:-$ADMIN_ID}
    read -rp "Enter backup interval in minutes [$BACKUP_INTERVAL]: " input
    BACKUP_INTERVAL=${input:-$BACKUP_INTERVAL}
    read -rp "Enter backup ZIP name [$BACKUP_NAME]: " input
    BACKUP_NAME=${input:-$BACKUP_NAME}
    save_config
    echo "[*] Configuration saved!"
}

show_menu() {
    echo "=============================="
    echo "      RemnaBackuper"
    echo "      Creator: Dnt3e"
    echo "=============================="
    echo "1) Start scheduled backup"
    echo "2) Test Telegram send"
    echo "3) Edit configuration"
    echo "4) Remove script"
    echo "5) Exit"
    echo "=============================="
    read -rp "Choose an option: " OPTION
    case $OPTION in
        1)
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
