# Player Pulse — On-Premise Installation Guide

This guide walks you through installing Player Pulse on your own server, from a
bare Linux machine to a fully running, publicly accessible CRM.

---

## 1. Overview

Player Pulse runs as a set of Docker containers on your server:

| Service                      | What it does                                                     |
|------------------------------|------------------------------------------------------------------|
| `api`                        | Main CRM backend                                                 |
| `connector`                  | API for your game platform / integrations to push player data in |
| `frontend`                   | The CRM web interface your team uses                             |
| `superadmin`                 | Admin panel for managing tenants and users                       |
| `outbox_worker`              | Background worker for async email/event delivery                 |
| `postgres`, `redis`, `minio` | Database, cache, and file storage                                |

Everything ships as public, pre-built Docker images — no credentials needed
to pull them. The one thing that gates access is your **license key**,
provided when your contract is signed.

---

## 2. Prerequisites

- A Linux server (Ubuntu/Debian recommended) with root or sudo access
- **Docker** and **Docker Compose v2** installed
- `openssl` and `curl` installed (used by the install script)
- Three domains (or subdomains) pointed at your server's IP:
    - One for the main CRM (e.g. `crm.yourcompany.com`)
    - One for the super admin panel (e.g. `admin.yourcompany.com`)
    - One for the connector API, if you'll integrate external systems (e.g. `connector.yourcompany.com`)
- Your **license key** (sent to you separately, at contract signing)
- A way to send email — either a Mailgun account, or SMTP credentials from any provider (your own mail server, Amazon
  SES, SendGrid, Postmark, etc.)

You do **not** need any GitHub account, token, or credentials of any kind to
pull the Docker images or clone this repository — everything is public.

---

## 3. Getting the Files

```bash
git clone https://github.com/Moai-Team-LLC/player-pulse-on-premise.git
cd player-pulse-on-premise
chmod +x install.sh update.sh
```

---

## 4. Running the Installer

Run the installer and answer the prompts:

```bash
./install.sh
```

You'll be asked for:

| Prompt                                          | What to enter                                                                                         |
|-------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| Domain for the main CRM                         | e.g. `crm.yourcompany.com`                                                                            |
| Domain for the super admin panel                | e.g. `admin.yourcompany.com`                                                                          |
| License key                                     | Provided at contract signing                                                                          |
| Mail provider                                   | `mailgun` or `smtp`                                                                                   |
| *(if mailgun)* Mailgun domain, API key, region  | From your Mailgun dashboard — region is `us` or `eu`, check which your Mailgun account uses           |
| *(if smtp)* SMTP host, port, username, password | From your mail provider                                                                               |
| Sender email address                            | What "from" address password-reset/invite emails should use                                           |
| Email for the initial super admin account       | This becomes your first login                                                                         |
| MinIO public URL (optional)                     | Only needed if you want uploaded files reachable directly from a browser; safe to leave blank for now |

The script then:

1. Generates all internal secrets (DB password, signing keys, encryption keys) automatically
2. Pulls the Docker images
3. Starts every service
4. Waits for the API to report healthy
5. Prints your login credentials and next steps

If it fails partway through, **don't re-run it from scratch** — your secrets
are already generated and saved. Run `./install.sh --resume` instead, which
picks up where it left off without regenerating anything.

Automated / scripted install (skip all prompts) is also supported — pass any
of the values as flags instead and the script won't ask for them. Full
reference (also available any time via `./install.sh --help`):

```
Usage: ./install.sh [flags]

Runs interactively by default, prompting for anything not passed as a flag.
Pass all required flags to run fully non-interactively.

  --domain=...                   Domain for the main CRM
  --super-admin-domain=...       Domain for the super admin panel
  --license=...                  License key (provided at contract signing)

  --mail-provider=mailgun|smtp   Which mail provider to use

  --mailgun-domain=...           Mailgun domain
  --mailgun-api-key=...          Mailgun API key
  --mailgun-region=us|eu         Mailgun account region — check your Mailgun dashboard

  --smtp-host=...                SMTP server host
  --smtp-port=...                SMTP server port (defaults to 587 if left blank interactively)
  --smtp-username=...            SMTP username
  --smtp-password=...            SMTP password

  --mail-sender=...              Sender email, e.g. "Your Company <noreply@yourcompany.com>"
  --cors-origins=...             Optional, derived from the two domains above if omitted
  --s3-public-url=...            Optional, only needed for public file URLs
  --super-admin-email=...        Email for the initial super admin account

  --resume                       Reuse an existing .env instead of generating a new one
                                  (use this to retry after a failed first-time install)

  --help, -h                     Show this message and exit
```

Example, fully non-interactive:

```bash
./install.sh --domain=crm.yourcompany.com --super-admin-domain=admin.yourcompany.com \
  --license=<your-license> --mail-provider=smtp --smtp-host=... --smtp-port=587 \
  --smtp-username=... --smtp-password=... --mail-sender="Your Company <noreply@yourcompany.com>" \
  --super-admin-email=you@yourcompany.com
```

---

## 5. Critical Post-Install Steps

The installer prints these at the end — don't skip them.

### Back up your PII encryption key immediately

The install output includes a line like:

```
PII_MASTER_KEY=<a long hex string>
```

This key encrypts all player personal data. **If it's lost, that data cannot
be recovered — not by you, not by us.** Copy it somewhere safe outside this
server right now (a password manager, a vault, anywhere durable).

### Back up your `.env` file

It contains every secret your installation uses. Keep a copy somewhere safe
and outside the server itself.

### Change the initial super admin password

Log in with the credentials printed at the end of the install, then change
the password immediately.

---

## 6. Setting Up Your Reverse Proxy

This is **your responsibility** — Player Pulse doesn't include or manage a
reverse proxy for you. Without it, your domains won't reach the running
containers, and you won't have HTTPS.

Below is a working `nginx` configuration. The one detail that matters most:
**every `location` block needs its own `proxy_set_header` lines** — nginx
does not inherit them between sibling locations, and missing them is the
single most common cause of a broken installation (it breaks tenant/domain
routing in a way that looks like a random 404).

```nginx
server {
    listen 80;
    server_name crm.yourcompany.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/v1 {
        client_max_body_size 75M;
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name admin.yourcompany.com;

    location / {
        proxy_pass http://localhost:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/v1 {
        client_max_body_size 75M;
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name connector.yourcompany.com;

    location / {
        client_max_body_size 75M;
        proxy_pass http://localhost:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Adjust the `proxy_pass` ports if you changed `API_PORT`/`FRONTEND_PORT`/
`SUPERADMIN_PORT`/`CONNECTOR_PORT` from the defaults in your `.env`.

**For HTTPS**, the simplest path is [certbot](https://certbot.eff.org/) with
the nginx plugin:

```bash
sudo certbot --nginx -d crm.yourcompany.com -d admin.yourcompany.com -d connector.yourcompany.com
```

### Set `TRUSTED_PROXIES`

Once your reverse proxy is running, find the Docker bridge network's gateway
IP — this is what nginx actually connects from, from the container's point of
view:

```bash
docker network ls | grep player-pulse
docker network inspect <network-name-from-above> | grep -A3 '"Gateway"'
```

Add that IP to `.env`:

```
TRUSTED_PROXIES=<the-gateway-ip>/32
```

Then restart the affected services:

```bash
docker compose -f docker-compose.on-premise.yml up -d --force-recreate api connector
```

Without this, your audit logs and login records will show the proxy's IP
instead of your actual users' IPs.

---

## 7. First Login

Go to your super admin domain (e.g. `https://admin.yourcompany.com`) and log
in with the credentials the installer printed.

**First login from any new location triggers a step-up verification code**
sent to your email — this is expected security behavior, not an error. Enter
the 6-digit code when prompted.

---

## 8. Creating Tenants and Users

Each "tenant" in Player Pulse represents one brand/operation with its own
isolated player data. From the super admin panel:

1. Create a tenant — give it a name and a domain (a subdomain of your own
   domain works fine, e.g. `royal.yourcompany.com`, as long as it also points
   at your server and has a matching nginx block).
2. Invite the tenant's first Admin user by email.
3. That person accepts the invite (link sent to their email), sets a
   password, and logs in at the tenant's own domain — from there, they
   manage their own team, branding, and everything else themselves.

You (the installation owner) only need to do this once per tenant — day-to-day
management from then on is fully self-service for that tenant's own Admin.

---

## 9. Updating

When a new version is released, update with:

```bash
./update.sh <version>
```

For example:

```bash
./update.sh 1.1.0
```

This downloads the new version's compose file, backs up your current one,
pulls the new images, and restarts everything. Your data is not affected —
only the application containers are replaced, your database/files stay as
they are.

**Rollback**: if something goes wrong, run `./update.sh` again with the
previous version number to go back.

---

## 10. Troubleshooting

**"API did not become healthy in time" during install/update**
Check the actual error:

```bash
docker compose -f docker-compose.on-premise.yml logs api
```

Common causes: wrong license key, database connection issue, or a port
conflict with something else already running on the server.

**A specific domain returns 404 or routes to the wrong page**
Almost always a reverse proxy misconfiguration — double check every
`location` block has its own `proxy_set_header` lines (see section 6).

**A log line like `[license] WARNING: license expired - N day(s) left in grace period, renew immediately`**
This is expected, not a bug. Your license has a fixed term; once it expires,
the app keeps running for a 14-day grace period so you have time to renew,
logging this warning daily. Contact us to renew before the grace period
ends — after that, the app will refuse to start
(`license expired and grace period has ended`) until a new license key is
in place.

---

## 11. Support

Contact us directly for help with your installation, to report an issue, or
to request a new license/version. Your support contact details were provided
at contract signing.