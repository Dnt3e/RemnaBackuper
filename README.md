# 🤖 RemnaBot

A Telegram-controlled backup manager for **Remnawave** Panel. It dumps your Postgres database, packages it with your app folders, and delivers the archive straight to your Telegram chat — on schedule or on demand.

---

## ✨ Features

- 💬 **Interactive Telegram bot** — `/start` opens an inline menu:
  - 📦 Manual Backup — trigger instantly from Telegram
  - ⏱ Set Backup Interval — change schedule from chat, with built-in guide
  - ❌ Exit
- 🕒 **Flexible scheduling** — minutes or `H:MM` format (e.g. `1:30` = 90 min)
- 🐘 **Smart DB dump** — auto-detects Docker (`remnawave-db`) or host Postgres, no credentials to configure
- 📁 **Full app backup** — includes `/opt/remnawave/`, `/opt/remnanode/`, plus any custom paths
- 🛡️ **Reliable cron** — lock-protected checker instead of raw `*/N`, so any interval actually works
- ⚙️ **systemd service** — auto-restarts on crash or reboot
- 🔄 **One-click cache fix** — resets the Telegram API session after moving to a new server/IP
- 📊 **Live CLI dashboard** — service state, interval, last/next backup, all in one menu

---

## 📋 Requirements

- Ubuntu/Debian VPS with root access
- A Remnawave/Remnanode server (or any Postgres DB to back up)
- A Telegram bot token from [@BotFather](https://t.me/BotFather) + your chat ID

---

## 🚀 Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Dnt3e/RemnaBackuper/main/remnabackuper.sh)
```

Run as root. First run installs prerequisites with a progress bar, then asks for:

1️⃣ Bot token 2️⃣ Admin chat ID 3️⃣ Backup name 4️⃣ Backup interval 5️⃣ Extra folders

---

## 🧭 Menu

```
1) Install & Setup Bot     – full setup wizard + systemd service
2) Manual Backup           – runs a backup instantly from the CLI
3) Fix Bot Cache           – resets Telegram API session (new server/IP)
4) Edit Bot
     1) Edit Bot Settings  – token, admin ID, name, interval, paths
     2) Edit Cron Job      – quick interval-only change
5) Remove Bot              – full uninstall
```

---

## 🔧 How It Works

1. `pg_dump` runs via Docker if `remnawave-db` exists, otherwise directly on the host.
2. App folders + SQL dump are zipped together.
3. The archive is sent to Telegram with server IP + timestamp.
4. Temp files are cleaned up automatically.

Scheduled backups check every minute whether the configured interval has elapsed — so odd intervals like 90 minutes work correctly, unlike plain cron.

---

## 🆘 Stuck Bot?

If Telegram keeps conflicting after moving the bot to a new server, use **option 3 (Fix Bot Cache)** — it clears the webhook, pending updates, and offset, then reconnects cleanly.

---

## 🗑️ Uninstall

Option **5** in the menu — stops the service, removes cron, config, and install files.

---

## 📄 License

MIT — use, modify, and share freely.
