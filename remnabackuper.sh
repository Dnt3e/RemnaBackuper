#!/bin/bash
# ==================================================
# RemnaBackuper
# creator: dnt3e
# ==================================================

BASE_DIR="/opt/RemnaBackuper"
BACKUP_DIR="$BASE_DIR/backup"
CONFIG_FILE="$BASE_DIR/config.conf"
SCRIPT_PATH="$BASE_DIR/remnabackuper.sh"

APP_TITLE="RemnaBackuper"
APP_FOOTER="creator: dnt3e"

mkdir -p "$BACKUP_DIR"

# -------- Dependency Installer --------
install_dependencies() {
(
echo 10
echo "Checking dependencies..."

deps=(curl zip whiptail docker.io)
count=0
total=${#deps[@]}

for pkg in "${deps[@]}"; do
    count=$((count+1))
    percent=$((count*80/total+10))
    echo $percent
    echo "Installing $pkg ..."
    dpkg -s "$pkg" &>/dev/null || apt install -y "$pkg" &>/dev/null
    sleep 1
done

echo 100
echo "Done"
) | whiptail --gauge "Installing required packages..." 8 60 0
}

# -------- Load Config --------
load_config() {
    source "$CONFIG_FILE" 2>/dev/null
}

# -------- Save Config --------
save_config() {
cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
ADMIN_ID="$ADMIN_ID"
INTERVAL_MIN="$INTERVAL_MIN"
BACKUP_NAME="$BACKUP_NAME"
EOF
}

# -------- Telegram Send --------
send_telegram() {
    FILE="$1"
    IP=$(curl -s ifconfig.me)
    DATE=$(date "+%Y-%m-%d %H:%M:%S")

    CAPTION="📦 Database Backup
🖥 Server IP: $IP
🕒 Date: $DATE
📂 Name: $BACKUP_NAME"

    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        -F chat_id="$ADMIN_ID" \
        -F document=@"$FILE" \
        -F caption="$CAPTION" > /dev/null
}

# -------- Backup Function --------
do_backup() {
    TIMESTAMP=$(date +%Y%m%d_%H%M)
    SQL_FILE="$BACKUP_DIR/${BACKUP_NAME}_$TIMESTAMP.sql"
    ZIP_FILE="$BACKUP_DIR/${BACKUP_NAME}_$TIMESTAMP.zip"

    docker exec remnawave-db pg_dump -U postgres postgres > "$SQL_FILE"
    zip -j "$ZIP_FILE" "$SQL_FILE" > /dev/null

    send_telegram "$ZIP_FILE"

    rm -f "$SQL_FILE" "$ZIP_FILE"
}

# -------- Cron Setup --------
setup_cron() {
    crontab -l 2>/dev/null | grep -v RemnaBackuper > /tmp/cron.tmp
    echo "*/$INTERVAL_MIN * * * * $SCRIPT_PATH --run # RemnaBackuper" >> /tmp/cron.tmp
    crontab /tmp/cron.tmp
    rm /tmp/cron.tmp
}

# -------- Install --------
install_script() {
    install_dependencies

    BOT_TOKEN=$(whiptail --title "$APP_TITLE" --inputbox "Enter Telegram Bot Token:" 10 60 3>&1 1>&2 2>&3)
    ADMIN_ID=$(whiptail --title "$APP_TITLE" --inputbox "Enter Admin Chat ID:" 10 60 3>&1 1>&2 2>&3)
    INTERVAL_MIN=$(whiptail --title "$APP_TITLE" --inputbox "Backup interval (minutes):" 10 60 3>&1 1>&2 2>&3)
    BACKUP_NAME=$(whiptail --title "$APP_TITLE" --inputbox "Backup file base name:" 10 60 "remna_backup" 3>&1 1>&2 2>&3)

    save_config
    setup_cron

    whiptail --title "$APP_TITLE" --msgbox "Installation completed successfully!" 10 50
}

# -------- Edit Config --------
edit_config() {
    load_config

    BOT_TOKEN=$(whiptail --title "$APP_TITLE" --inputbox "Bot Token:" 10 60 "$BOT_TOKEN" 3>&1 1>&2 2>&3)
    ADMIN_ID=$(whiptail --title "$APP_TITLE" --inputbox "Admin ID:" 10 60 "$ADMIN_ID" 3>&1 1>&2 2>&3)
    INTERVAL_MIN=$(whiptail --title "$APP_TITLE" --inputbox "Interval (minutes):" 10 60 "$INTERVAL_MIN" 3>&1 1>&2 2>&3)
    BACKUP_NAME=$(whiptail --title "$APP_TITLE" --inputbox "Backup Name:" 10 60 "$BACKUP_NAME" 3>&1 1>&2 2>&3)

    save_config
    setup_cron
}

# -------- Test Backup --------
test_backup() {
    load_config
    do_backup
    whiptail --title "$APP_TITLE" --msgbox "Test backup sent successfully!" 10 50
}

# -------- Remove Script --------
remove_script() {
    crontab -l 2>/dev/null | grep -v RemnaBackuper | crontab -
    rm -rf "$BASE_DIR"
    whiptail --msgbox "RemnaBackuper removed!" 10 40
    exit
}

# -------- Menu --------
main_menu() {
    CHOICE=$(whiptail --title "$APP_TITLE" \
    --menu "$APP_TITLE\n$APP_FOOTER\n\nChoose an option:" 18 60 7 \
    "1" "Install / Setup" \
    "2" "Edit Settings" \
    "3" "Test Backup Now" \
    "4" "Restart Cron Job" \
    "5" "Remove Script" \
    "6" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) install_script ;;
        2) edit_config ;;
        3) test_backup ;;
        4) load_config; setup_cron ;;
        5) remove_script ;;
        6) exit ;;
    esac
}

# -------- Run from Cron --------
if [[ "$1" == "--run" ]]; then
    load_config
    do_backup
    exit
fi

main_menu
