#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

REAL_PATH="$HOME/remnabackuper.sh"
CONFIG_FILE="$HOME/.remnabackuper.conf"

DOCKER_BIN=$(which docker)
ZIP_BIN=$(which zip)
CURL_BIN=$(which curl)
BASH_BIN=$(which bash)

deploy_logic() {
    if [[ "$0" == "bash" || "$0" == "sh" || "$0" == "/bin/bash" ]]; then
        if [[ ! -f "$REAL_PATH" ]]; then
            curl -fsSL https://raw.githubusercontent.com/Dnt3e/RemnaBackuper/main/remnabackuper.sh -o "$REAL_PATH"
            chmod +x "$REAL_PATH"
        fi
        exec "$REAL_PATH" "$@"
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
    TEMP_SQL="$HOME/backup_temp.sql"
    ZIP_OUT="$HOME/${BACKUP_NAME}.zip"
    rm -f "$TEMP_SQL" "$ZIP_OUT"
    $DOCKER_BIN exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$TEMP_SQL" 2>/dev/null
    if [[ -s "$TEMP_SQL" ]]; then
        $ZIP_BIN -j "$ZIP_OUT" "$TEMP_SQL" >/dev/null 2>&1
    fi
}

send_to_telegram() {
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    SERVER_IP=$(hostname -I | awk '{print $1}')
    ZIP_PATH="$HOME/${BACKUP_NAME}.zip"
    if [[ -s "$ZIP_PATH" ]]; then
        $CURL_BIN -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
             -F chat_id="$ADMIN_ID" \
             -F document=@"$ZIP_PATH" \
             -F caption="Server IP: $SERVER_IP | Time: $TIMESTAMP" >/dev/null
    fi
}

setup_cron() {
    (crontab -l 2>/dev/null | grep -v "remnabackuper.sh") > /tmp/cron_tmp
    echo "*/$BACKUP_INTERVAL * * * * $BASH_BIN $REAL_PATH --run > /dev/null 2>&1" >> /tmp/cron_tmp
    crontab /tmp/cron_tmp
    rm /tmp/cron_tmp
}

if [[ "$1" == "--run" ]]; then
    backup_db
    send_to_telegram
    rm -f "$HOME/backup_temp.sql" "$HOME/${BACKUP_NAME}.zip"
    exit 0
fi

remove_script() {
    crontab -l 2>/dev/null | grep -v "remnabackuper.sh" | crontab -
    rm -f "$CONFIG_FILE" "$REAL_PATH"
    echo -e "${RED}[!] RemnaBackuper has been removed successfully.${NC}"
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
    echo "1) Update Cron Job"
    echo "2) Test Backup"
    echo "3) Edit Config"
    echo "4) Remove Script"
    echo "5) Exit"
    echo "=========================================="
    printf "${GREEN}Choose an option: ${NC}"
    read -r OPTION
    case $OPTION in
        1) setup_cron; echo -e "${GREEN}[*] Cron job updated!${NC}" ;;
        2) backup_db; send_to_telegram; echo -e "${GREEN}[*] Test backup sent!${NC}" ;;
        3) configure_script; setup_cron ;;
        4) remove_script ;;
        5) exit 0 ;;
    esac
}

configure_script() {
    printf "${GREEN}Enter Token: ${NC}"; read -r input; BOT_TOKEN=${input:-$BOT_TOKEN}
    printf "${GREEN}Enter Admin ID: ${NC}"; read -r input; ADMIN_ID=${input:-$ADMIN_ID}
    printf "${GREEN}Enter Interval (Min): ${NC}"; read -r input; BACKUP_INTERVAL=${input:-$BACKUP_INTERVAL}
    printf "${GREEN}Enter Backup Name: ${NC}"; read -r input; BACKUP_NAME=${input:-$BACKUP_NAME}
    save_config
}

main() {
    deploy_logic "$@"
    install_dependencies
    if [[ ! -f "$CONFIG_FILE" ]]; then
        configure_script
        backup_db; send_to_telegram
        setup_cron
        echo -e "${GREEN}[V] Installation successful!${NC}"
    else
        load_config
    fi
    while true; do show_menu; done
}

main "$@"
