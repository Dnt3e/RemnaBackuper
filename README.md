# RemnaBackuper

**RemnaBackuper** is an automated backup tool designed specifically for **Remnawave panel** environments. It safely backs up the PostgreSQL database running inside the Remnawave Docker container, compresses it, sends it to Telegram, and automatically cleans temporary files.

Creator: **Dnt3e**

---

## ✨ Features

* Designed specifically for **Remnawave panel**
* Automated PostgreSQL backup from Docker container
* ZIP compression for efficient storage
* Automatic delivery to Telegram bot
* Cron-based scheduling (minute-based intervals)
* Interactive CLI configuration menu
* Automatic dependency installation
* Manual backup testing without waiting for schedule
* Custom backup file naming
* Backup caption includes server IP, date, and time
* Clean uninstall option (removes cron jobs and configs)

---

## 📦 Requirements

* Ubuntu / Debian based Linux
* Docker installed
* Remnawave PostgreSQL database container
* Telegram Bot Token
* Internet connection

Required packages are installed automatically if missing.

---

## 🚀 Installation

### One-line Automatic Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Dnt3e/RemnaBackuper/main/remnabackuper.sh)
```

This command will:

* Download the latest script
* Install required dependencies
* Launch setup menu
* Configure automatic scheduled backups

---

## ⚙️ Configuration

During setup or from the script menu you can configure:

* Telegram Bot Token
* Telegram Admin Chat ID
* Backup interval (minutes)
* Backup file name

---

## 🧪 Manual Backup

You can instantly send a backup using the menu option:

```
Manual Backup (Send Now)
```

---

## 🗑 Uninstall

RemnaBackuper can fully remove itself including:

* Cron jobs
* Configuration files
* Script files

---

## ⭐ Support The Project

If you find this project useful, please consider giving it a **star ⭐ on GitHub**. Your support helps the project grow and motivates further development.
