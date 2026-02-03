# RemnaBackuper

A simple, automated PostgreSQL backup solution for Docker environments with Telegram integration.

**RemnaBackuper** periodically backs up your PostgreSQL database running inside a Docker container, compresses it, sends it to a Telegram bot, and cleans up old files automatically.

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

```bash
sudo mkdir -p /opt/RemnaBackuper
sudo nano /opt/RemnaBackuper/remnabackuper.sh
sudo chmod +x /opt/RemnaBackuper/remnabackuper.sh
sudo /opt/RemnaBackuper/remnabackuper.sh
```

Follow the on-screen menu to complete installation.

---

## ⚙️ Configuration Options

During installation or via **Edit Settings**:

* Telegram Bot Token
* Admin Chat ID
* Backup interval (minutes)
* Backup file base name

---

## 🧪 Test Backup

Use the menu option **Test Backup Now** to send a backup immediately without waiting for cron.

---

## 🗑 Remove RemnaBackuper

Completely removes:

* Cron jobs
* Configuration files
* Backup directory
* Script itself

---

## 🖼 Telegram Caption Example

```
📦 Database Backup
🖥 Server IP: 1.2.3.4
🕒 Date: 2026-02-03 14:22
📂 Name: remna_backup
```

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

## 👤 Author

**Dnt3e**

---

## 📄 License

MIT License

Feel free to fork, modify, and contribute.

---

⭐ If you find this project useful, consider giving it a star on GitHub!
