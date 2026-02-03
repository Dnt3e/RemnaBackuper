#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'

# مسیر ثابت برای ذخیره اسکریپت روی سرور
SCRIPT_PATH="/usr/local/bin/remnabackuper.sh"
CONFIG_FILE="$HOME/.remnabackuper.conf"

DOCKER_BIN=$(which docker)
ZIP_BIN=$(which zip)
CURL_BIN=$(which curl)
BASH_BIN=$(which bash)

# تابع برای استقرار اسکریپت روی سرور (برای حل مشکل Pipe)
deploy_self() {
    if [[ "$0" == "bash" ]] || [[ "$0" == "/bin/bash" ]] || [[ "$0" == "sh" ]]; then
        echo -e "${GREEN}[*] Deploying script to $SCRIPT_PATH for permanent scheduling...${NC}"
        # کپی کردن محتوای در حال اجرا به فایل ثابت
        cat "$0" > "$SCRIPT_PATH" 2>/dev/null || cat /dev/stdin > "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
}

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
    sudo apt update -y && sudo apt install -y zip curl jq cron
    sudo systemctl enable cron && sudo systemctl start cron
}

backup_db() {
    load_config
    TEMP_SQL="/tmp/backup_temp.sql"
    ZIPNAME="/tmp/${BACKUP_NAME}.zip"
    $DOCKER_BIN exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$TEMP_SQL"
    rm -f "$ZIPNAME"
    $ZIP_BIN -j "$ZIPNAME" "$TEMP_SQL" >/dev/null 2>&1
}

send_to_telegram() {
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    SERVER_IP=$(hostname -I | awk '{print $1}')
    ZIP_PATH="/tmp/${BACKUP_NAME}.zip"
    if [ -f "$ZIP_PATH" ]; then
        $CURL_BIN -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
             -F chat_id="$ADMIN_ID" \
             -F document=@"$ZIP_PATH" \
             -F caption="Server IP: $SERVER_IP | Time: $TIMESTAMP" >/dev/null
    fi
}

setup_cron() {
    # استفاده از مسیر ثابت SCRIPT_PATH برای کرون
    (crontab -l 2>/dev/null | grep -v "remnabackuper.sh") > /tmp/cron_tmp
    echo "*/$BACKUP_INTERVAL * * * * $BASH_BIN $SCRIPT_PATH --run > /dev/null 2>&1" >> /tmp/cron_tmp
    crontab /tmp/cron_tmp
    rm /tmp/cron_tmp
}

if [[ "$1" == "--run" ]]; then
    run_full_process() { backup_db; send_to_telegram; rm -f "/tmp/backup_temp.sql" "/tmp/${BACKUP_NAME}.zip"; }
    run_full_process
    exit 0
fi

# ------------------------------
# MENU & UI
# ------------------------------
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
    echo "1) Update scheduled backup (Cron)"
    echo "2) Test Telegram send"
    echo "3) Edit configuration"
    echo "4) Remove script"
    echo "5) Exit"
    echo "=========================================="
    printf "${GREEN}Choose an option: ${NC}"
    read -r OPTION
    case $OPTION in
        1) setup_cron; echo -e "${GREEN}[*] Cron job updated!${NC}" ;;
        2) backup_db; send_to_telegram; echo -e "${GREEN}[*] Test sent!${NC}" ;;
        3) configure_script; setup_cron ;;
        4) crontab -l | grep -v "remnabackuper.sh" | crontab -; rm -f "$CONFIG_FILE" "$SCRIPT_PATH"; exit 0 ;;
        5) exit 0 ;;
    esac
}

configure_script() {
    printf "${GREEN}Enter Telegram bot token [$BOT_TOKEN]: ${NC}"
    read -r input; BOT_TOKEN=${input:-$BOT_TOKEN}
    printf "${GREEN}Enter Telegram admin ID [$ADMIN_ID]: ${NC}"
    read -r input; ADMIN_ID=${input:-$ADMIN_ID}
    printf "${GREEN}Enter backup interval in minutes [$BACKUP_INTERVAL]: ${NC}"
    read -r input; BACKUP_INTERVAL=${input:-$BACKUP_INTERVAL}
    printf "${GREEN}Enter backup file name (default: RemnaBackuper): ${NC}"
    read -r input; BACKUP_NAME=${input:-$BACKUP_NAME}
    save_config
}

main() {
    # اول از همه تلاش برای ذخیره فایل روی دیسک
    deploy_self
    install_dependencies
    if [[ ! -f "$CONFIG_FILE" ]]; then
        configure_script
        backup_db; send_to_telegram
        setup_cron
    else
        load_config
    fi
    while true; do show_menu; done
}

main
