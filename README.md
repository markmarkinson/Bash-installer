# 🛡️ Debian Server Setup – Modular Installer

Dieses Projekt richtet einen **sicheren Debian-Server** (Debian 12/13) modular ein.  
Du wählst im Menü gezielt aus, was passieren soll: **Absicherung**, **Webstack**, **vHosts**, **Let's Encrypt**, **Restore**, **Remove vHost** – alles in **sauber getrennten Modulen**.

> **Highlights**
>
> - Zufälliger SSH-Port (35k–50k), Root-Login aus, Passwort-Auth an  
> - Zufällig generierter Systemnutzer (z. B. `berndStelter3313`, Login lowercase)  
> - UFW, Fail2ban (sshd + nginx-Jails), persistente Logs  
> - Nginx + PHP‑FPM + MariaDB + **phpMyAdmin unter `http://<SERVER-IP>/pma-db` mit Basic-Auth**  
> - Interaktive vHost-Erstellung (Domain, Prefix, optional Basic-Auth)  
> - **Let's Encrypt** (HTTP‑01, nginx), optional **HSTS**  
> - Restore-Modul für `.bak`-Backups, Remove-Modul für vHosts
>
> Alle generierten Zugangsdaten landen in **`/root/credentials.txt`**.

---

## 🧷 Installation & Updates mit Git

Du kannst das Projekt bequem mit **git** klonen und aktuell halten.

### Voraussetzungen
```bash
# Git installieren (Debian)
sudo apt update && sudo apt install -y git
```
```bash
# Beispiel: in /opt installieren
cd /opt
sudo git clone [<REPO_URL>](https://github.com/markmarkinson/Bash-installer.git) debian-installer-modular
cd debian-installer-modular

# Skripte ausführbar machen
sudo chmod +x installer.sh modules/*.sh

# (optional) Defaults anpassen
sudo cp installer.env.example installer.env
sudo nano installer.env

# Start
sudo ./installer.sh
```


## 📦 Inhalt & Struktur

```
debian-installer-modular/
├── installer.sh
├── installer.env.example
└── modules/
    ├── 00_common.sh           # Gemeinsame Helfer/Utilities
    ├── 10_updates.sh          # APT: update (keine Upgrades)
    ├── 20_harden.sh           # Absichern (User, SSH, UFW, Fail2ban, Logs)
    ├── 30_web.sh              # Nginx + PHP-FPM + MariaDB + phpMyAdmin
    ├── 40_vhosts.sh           # Interaktive vHost-Erstellung (mehrere)
    ├── 41_add_vhost.sh        # Schnelles Anlegen eines vHosts
    ├── 50_tls.sh              # Let's Encrypt (Certbot + nginx)
    ├── 60_remove_vhost.sh     # vHost entfernen (inkl. Webroot optional)
    └── 70_restore.sh          # Backups *.bak gezielt/alle zurückspielen
```

---

## 🔐 Sicherheit & Defaults

- **SSH**
  - Zufälliger Port **35000–50000**
  - `PermitRootLogin no`
  - `PasswordAuthentication yes`
  - `MaxAuthTries 3`, `MaxSessions 2`, `LoginGraceTime 30`
- **UFW**
  - Default: deny incoming / allow outgoing
  - erlaubt: **SSH (random Port)**, **80/tcp**, **443/tcp**
- **Fail2ban**
  - `sshd` (Basis)
  - Nginx-Jails: **404-Burst**, **Req-Limit (429/503)**, **phpMyAdmin**, **http-auth**
- **Logs**
  - Journald: `Storage=persistent`, Forward zu rsyslog
  - Optional **Remote-Syslog** (per `installer.env`)
- **Unattended-Upgrades**
  - Automatisches Security-Update (täglich), keine erzwungenen Upgrades im Scriptlauf.

---

## 🌐 Webstack-Details

- **phpMyAdmin**
  - URL: **`http://<SERVER-IP>/pma-db`**
  - **Nur IP-Host** erlaubt (Zugriff via Domain: 404).
  - **Basic-Auth** aktiviert, Zugang in `/root/credentials.txt`.
  - Internes Nginx-Snippet leitet `/pma-db` → `/pma-db/` um und behandelt **PHP in eigenem Regex-Block**, damit **nichts heruntergeladen** wird, sondern über **PHP‑FPM** läuft.
- **IP-Host-Redirect**
  - Alle IP-Aufrufe **außer** `/pma-db*` werden zu `https://www.google.com` weitergeleitet.
- **vHosts**
  - Pro Domain ein Server-Block, **Prefix‑basiert** (z. B. `/api`, `/app`), `alias` auf Webroot (z. B. `/var/www/example.com/api/public`).
  - **PHP** via `location ~ ^/PREFIX/(.+\.php)$` → `fastcgi_pass` (Socket wird automatisch erkannt).
  - Optional **Basic-Auth** pro vHost-Prefix.

---

## ⚙️ Konfiguration via `installer.env` (optional)

Lege neben `installer.sh` eine Datei `installer.env` an (Beispiel siehe `installer.env.example`):

```bash
SILENT="yes"          # "yes" = still, "no" = mehr Logs
REMOTE_SYSLOG=""      # z. B. "logs.example.net" (leer lassen zum Deaktivieren)
```

---

## 🧑‍💻 Module im Detail

| Modul | Zweck | Bemerkungen |
|------:|------|-------------|
| `10_updates.sh` | `apt update` | keine Upgrades |
| `20_harden.sh` | User + SSH + UFW + Fail2ban + Logs | SSH-Port random, Zugangsdaten → `/root/credentials.txt` |
| `30_web.sh` | Nginx + PHP‑FPM + MariaDB + **phpMyAdmin** | pMA nur IP-Host, Basic-Auth, Ratelimit; Nginx gehärtet |
| `40_vhosts.sh` | Interaktiv **mehrere** vHosts anlegen | Domain, Prefix, optional Basic-Auth |
| `41_add_vhost.sh` | **Ein** vHost schnell anlegen | ideal für Skripting/Einzelanlage |
| `50_tls.sh` | **Let's Encrypt** (nginx) | Staging/Prod, optional **HSTS** |
| `60_remove_vhost.sh` | vHost entfernen | löscht Config + optional Webroot |
| `70_restore.sh` | `.bak` wiederherstellen | erkennt Änderungen & lädt Dienste neu |

---

## 🔑 Zugangsdaten & wichtige Pfade

- **Zugangsdaten:** `sudo cat /root/credentials.txt`
  - `NEW_USER_LOGIN`, `NEW_USER_PASSWORD`
  - `SSH_PORT`
  - `PMA_BASIC_AUTH_USER`, `PMA_BASIC_AUTH_PASS`
  - ggf. vHost‑Basic‑Auth‑Credentials
- **phpMyAdmin:** `http://<SERVER-IP>/pma-db`
- **vHost-Webroots:** `/var/www/<domain>/<prefix>/public`
- **Nginx-Configs:**
  - `/etc/nginx/sites-available/*.conf` (aktivieren via Symlink in `sites-enabled`)
  - Snippet: `/etc/nginx/snippets/pma_protected.conf`

---

## 🔐 Let's Encrypt (Modul `50_tls.sh`)

- Benötigt **öffentliche DNS-A‑Records** → auf den Server zeigen.
- Das Modul kann bei fehlenden vHost-Configs **Minimalblöcke** anlegen, um ACME-Challenges zu bedienen.
- **HSTS** optional aktivierbar (fügt Header nach `server_name` ein).
- **Renewals** via `certbot.timer` aktiviert.

**Aufruf im Menü:** Option **6**

---

## 🧰 Restore & Remove

- **Restore (`70_restore.sh`)**  
  Sucht `.bak` in sinnvollen Pfaden (`/etc/nginx`, `/etc/ssh`, `/etc/fail2ban`, `/etc/systemd`, `/etc/rsyslog.d`), stellt gezielt oder alle wieder her und lädt betroffene Dienste neu.

- **Remove vHost (`60_remove_vhost.sh`)**  
  Wähle einen oder mehrere vHosts zur Entfernung. Optional wird das zugehörige **Webroot** gelöscht (sicherheitsabfrage).

---

## ❓ Troubleshooting

**phpMyAdmin lädt als Download**  
→ In dieser Version ist das behoben: PHP unter `/pma-db` wird über eine **Regex-Location** bedient und nicht vom Prefix-Block „verschluckt“.  
Prüfe bei Bedarf den PHP‑FPM‑Socket:
```bash
ls /run/php/php*-fpm.sock
# ggf. in /etc/nginx/snippets/pma_protected.conf fastcgi_pass anpassen
```

**`nginx -t` fehlschlägt (Syntax/Semikolon)**  
→ Achte auf `server_name <domain>;` mit **Semikolon**. Unsere Generatoren schreiben gültige Syntax.

**Exitcode 141 / SIGPIPE in Shell**  
→ Alle relevanten Stellen sind **pipefail-sicher**. Falls du Skripte selbst änderst, vermeide Pipes mit „kurzschlussenden“ Filtern à la `| head -n1` bei aktivem `set -o pipefail`.

**Port 22 noch offen?**  
→ Nach Hardening erlaubt UFW den **zufälligen SSH-Port**. Port 22 wird nicht geöffnet (nur falls vorher offen war).

---

## 🧪 Getestete Plattformen

- Debian **12 (bookworm)**
- Debian **13 (trixie)**

> Für Container (LXC/Docker) werden Kernel‑Pakete auf **HOLD** gesetzt.

---

## 📝 Best Practices (Empfehlungen)

- Sichere **`/root/credentials.txt`** extern.
- Richte **regelmäßige Backups** (Configs + Datenbanken) ein.
- Aktiviere **TLS** (Modul `50_tls.sh`) und **HSTS** in Produktion.
- Nutze **separate Prefixe** pro Anwendung (`/api`, `/app`, `/admin`).
- Prüfe **Fail2ban‑Jails** und Logfiles regelmäßig.

---

## 📜 Lizenz & Haftung

Dieses Setup wird **ohne Gewähr** bereitgestellt. Verwende es auf eigene Verantwortung und prüfe die Konfigurationen für deine Umgebung.

---

Viel Erfolg & sichere Server! ✨

---
