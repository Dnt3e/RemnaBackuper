# RemnaBackuper

A simple, automated PostgreSQL backup solution for Docker environments with Telegram integration.

**RemnaBackuper** periodically backs up your PostgreSQL database running inside a Docker container, compresses it, sends it to a Telegram bot, and cleans up old files automatically.

**creator:** Dnt3e

---

## ✨ Features

* Automated PostgreSQL backup via Docker
* ZIP compression
* Telegram bot delivery
* Cron-based scheduling (minute-based)
* Semi-graphical menu (whiptail)
* Automatic dependency installation with progress bar
* Editable configuration
* Test backup without waiting for schedule
* Custom backup file names
* Server IP, date & time in Telegram caption
* Clean uninstall option

---

## 📦 Requirements

* Ubuntu 20.04+
* Docker
* PostgreSQL running inside Docker container

The script will automatically install these if missing:

* `curl`
* `zip`
* `whiptail`
* `docker.io`

---

## 🚀 Installation

### Manual Installation

```bash
sudo mkdir -p /opt/RemnaBackuper
sudo nano /opt/RemnaBackuper/remnabackuper.sh  # Paste the script here
sudo chmod +x /opt/RemnaBackuper/remnabackuper.sh
sudo /opt/RemnaBackuper/remnabackuper.sh
```

Follow the on-screen menu to complete installation.

### One-line Automatic Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Dnt3e/RemnaBackuper/main/remnabackuper.sh)
```

This will:

1. Download the latest `remnabackuper.sh` from GitHub.
2. Make it executable.
3. Run the script and guide you through the setup menu.

---

## ⚙️ Configuration Options

During installation or via **Edit Settings**:

* Telegram Bot Token
* Admin Chat ID
* Backup interval (minutes)
* Backup file base name

---

## 🧪 Test Backup

Use the menu option **Manual Backup (Send Now)** to send a backup immediately without waiting for cron.

---

## 🗑 Remove RemnaBackuper

Completely removes:

* Cron jobs
* Configuration files
* Backup directory
* Script itself

---

## 📁 Project Structure

```
/opt/RemnaBackuper/
├── remnabackuper.sh
├── config.conf
└── backup/
```

---

## 🛠 Docker Command Used

```bash
docker exec remnawave-db pg_dump -U postgres postgres
```

---

## 📄 Script Link

The main script is available here:

* [View or Download `remnabackuper.sh`](https://github.com/Dnt3e/RemnaBackuper/blob/main/remnabackuper.sh)
* [Download raw script](https://raw.githubusercontent.com/Dnt3e/RemnaBackuper/main/remnabackuper.sh)

---

## 🖼 Telegram Caption Example

```
📦 Database Backup
🖥 Server IP: 1.2.3.4
🕒 Date: 2026-02-03 14:22
📂 Name: remna_backup
```

---

## 🔗 Badges

![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Docker-green)
![Telegram](https://img.shields.io/badge/Notify-Telegram-blue)

---

## 👤 Author

**Dnt3e**

---

## 📄 License

MIT License

Feel free to fork, modify, and contribute.

---

⭐ If you find this project useful, consider giving it a star on GitHub!
