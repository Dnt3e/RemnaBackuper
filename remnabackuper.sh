#!/bin/bash

# ==============================
#  ██████╗ ███████╗███╗   ███╗███╗   ███╗ █████╗ ██████╗ ███████╗
# ██╔════╝ ██╔════╝████╗ ████║████╗ ████║██╔══██╗██╔══██╗██╔════╝
# ██║  ███╗█████╗  ██╔████╔██║██╔████╔██║███████║██████╔╝█████╗  
# ██║   ██║██╔══╝  ██║╚██╔╝██║██║╚██╔╝██║██╔══██║██╔═══╝ ██╔══╝  
# ╚██████╔╝███████╗██║ ╚═╝ ██║██║ ╚═╝ ██║██║  ██║██║     ███████╗
#  ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝
# RemnaBackuper
# Creator: Dnt3e
# ==============================

# ------------------------------
# CONFIG FILE
# ------------------------------
CONFIG_FILE="$HOME/.remnabackuper.conf"

# Default settings
BOT_TOKEN=""
ADMIN_ID=""
BACKUP_INTERVAL=60       # in minutes
BACKUP_NAME="RemnaBackuper"
DB_CONTAINER="remnawave-db"
DB_USER="postgres"
DB_NAME="postgres"

# ------------------------------
# COLORS
# ------------------------------
GREEN="\e[32m"
RESET="\e[0m"

# ------------------------------
# HELPER FUNCTIONS
# ------------------------------

# Load config
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Save config
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

# Install dependencies
install_dependencies() {
    sudo apt update
    sudo apt install -y zip curl jq
}

# Get server IP
get_server_ip() {
    hostname -I | awk '{print $1}'
}

# Backup DB and zip
backup_db() {
    FILENAME="backup.sql"                  # همیشه فایل داخل zip backup نام دارد
    ZIPNAME="${BACKUP_NAME}.zip"          # نام فایل zip فقط بر اساس BACKUP_NAME است

    echo "[*] Creating PostgreSQL backup..."
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$FILENAME"

    echo "[*] Zipping backup..."
    # ایجاد فایل zip با قابلیت ریکاوری 5%
    zip -r -Z store -q -FF 5 "$ZIPNAME" "$FILENAME" >/dev/null 2>&1

    echo "[*] Backup file created: $ZIPNAME"
}

# Send backup to Telegram
send_to_telegram() {
    SERVER_IP=$(get_server_ip)
    DESCRIPTION="Server IP: $SERVER_IP"

    echo "[*] Sending backup to Telegram..."
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
         -F chat_id="$ADMIN_ID" \
         -F document=@"$ZIPNAME" \
         -F caption="$DESCRIPTION" >/dev/null
    echo "[*] Backup sent!"
}

# Clean up
cleanup() {
    rm -f "$FILENAME" "$ZIPNAME"
}

# Test send
test_send() {
    backup_db
    send_to_telegram
    cleanup
}

# Remove script
remove_script() {
    echo "[*] Removing RemnaBackuper..."
    rm -f "$0" "$CONFIG_FILE"
    echo "[*] Done!"
    exit 0
}

# ------------------------------
# MENU
# ------------------------------
show_menu() {
    echo "================================================"
    echo "      ██████╗ ███████╗███╗   ███╗███╗   ███╗ "
    echo "     ██╔════╝ ██╔════╝████╗ ████║████╗ ████║"
    echo "     ██║  ███╗█████╗  ██╔████╔██║██╔████╔██║"
    echo "     ██║   ██║██╔══╝  ██║╚██╔╝██║██║╚██╔╝██║"
    echo "     ╚██████╔╝███████╗██║ ╚═╝ ██║██║ ╚═╝ ██║"
    echo "      ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝     ╚═╝"
    echo "      RemnaBackuper"
    echo "      Creator: Dnt3e"
    echo "================================================"
    echo "1) Start scheduled backup"
    echo "2) Test Telegram send"
    echo "3) Edit configuration"
    echo "4) Remove script"
    echo "5) Exit"
    echo "================================================"
    read -rp "Choose an option: " OPTION
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

# ------------------------------
# CONFIGURATION
# ------------------------------
configure_script() {
    read -rp -e -i "$BOT_TOKEN" -p "$(echo -e ${GREEN}Enter Telegram bot token: ${RESET})" input
    BOT_TOKEN=${input:-$BOT_TOKEN}

    read -rp -e -i "$ADMIN_ID" -p "$(echo -e ${GREEN}Enter Telegram admin ID: ${RESET})" input
    ADMIN_ID=${input:-$ADMIN_ID}

    read -rp -e -i "$BACKUP_INTERVAL" -p "$(echo -e ${GREEN}Enter backup interval in minutes: ${RESET})" input
    BACKUP_INTERVAL=${input:-$BACKUP_INTERVAL}

    read -rp -e -i "$BACKUP_NAME" -p "$(echo -e ${GREEN}Enter backup file base name: ${RESET})" input
    BACKUP_NAME=${input:-$BACKUP_NAME}

    save_config
    echo "[*] Configuration saved!"
}

# ------------------------------
# MAIN
# ------------------------------
main() {
    install_dependencies
    load_config

    # If config is empty, first-time setup
    if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
        echo "[*] First-time setup:"
        configure_script
    fi

    while true; do
        show_menu
    done
}

main
