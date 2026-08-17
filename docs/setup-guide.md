# Player Pulse — On-Premise Installation Guide

This guide walks you through installing Player Pulse on your own server, from a
bare Linux machine to a fully running, publicly accessible CRM.

---

## 1. Overview

Player Pulse runs as a set of Docker containers on your server:

| Service                      | What it does                                                                                                                              |
|------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| `api`                        | Main CRM backend                                                                                                                          |
| `connector`                  | API for your game platform / integrations to push player data in                                                                          |
| `frontend`                   | The CRM web interface your team uses                                                                                                      |
| `superadmin`                 | Admin panel for managing tenants and users                                                                                                |
| `outbox_worker`              | Background worker for async email/event delivery                                                                                          |
| `postgres`, `redis`, `minio` | Database, cache, and file storage                                                                                                         |
| adapters                     | Optional integrations (email, telephony, SMS, chat ...) — each only runs if you activate it; see section 4 for what's currently available |

Everything ships as public, pre-built Docker images — no credentials needed
to pull them. The one thing that gates access is your **license key**,
provided when your contract is signed.

`postgres`, `redis`, and the adapter containers are always defined in the
stack; adapters simply don't start until activated. `minio` is the default
file storage and can be swapped for your own S3-compatible provider — see
"Using External Object Storage" in section 5.

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

You do **not** need credentials for any optional adapter (Mailgun for player
communication, Voiso, SMS-RETAIL, etc.) to install. Activating an adapter
just starts its container; the actual account credentials for that
integration are entered later, per project, inside the CRM's project
settings once you're logged in — see section 4.

---

## 3. Getting the Files

```bash
git clone https://github.com/Moai-Team-LLC/player-pulse-on-premise.git
cd player-pulse-on-premise
chmod +x install.sh update.sh
```

---

## 4. Running the Installer

### Checking Readiness First (Optional)

`install.sh` runs this automatically as its first step, but you can also run
it standalone, any time — even days before you're ready to install:

```bash
./preflight.sh
```

It checks Docker, required tools, architecture, registry connectivity, disk
space, memory, DNS (if you pass `--domain=`/`--super-admin-domain=`), and
port availability/conflicts — printing every issue it finds in one pass
rather than stopping at the first. It's read-only; nothing it does changes
your system. If you already know which adapters and custom ports you'll
use, pass them the same way you would to `install.sh` so it checks the
right ports:

```bash
./preflight.sh --adapters=mailgun,voiso --api-port=8080
```

Exits 0 if nothing is blocking, 1 if something critical needs fixing first
(warnings never block).

### Running the Installer

Run the installer and answer the prompts:

```bash
./install.sh
```

You'll be asked for:

| Prompt                                          | What to enter                                                                                            |
|-------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| Domain for the main CRM                         | e.g. `crm.yourcompany.com`                                                                               |
| Domain for the super admin panel                | e.g. `admin.yourcompany.com`                                                                             |
| License key                                     | Provided at contract signing                                                                             |
| Mail provider                                   | `mailgun` or `smtp`                                                                                      |
| *(if mailgun)* Mailgun domain, API key, region  | From your Mailgun dashboard — region is `us` or `eu`, check which your Mailgun account uses              |
| *(if smtp)* SMTP host, port, username, password | From your mail provider                                                                                  |
| Sender email address                            | What "from" address password-reset/invite emails should use                                              |
| Email for the initial super admin account       | This becomes your first login                                                                            |
| Adapters to activate now (optional)             | Comma-separated, e.g. `mailgun,voiso`. Leave blank to start with none — see "Adapters" below             |
| Host ports (optional)                           | Press Enter to accept the defaults shown, or enter a different port if one conflicts — see "Ports" below |
| MinIO public URL (optional)                     | Only needed if you want uploaded files reachable directly from a browser; safe to leave blank for now    |

### Adapters

Adapters are optional integrations — each one is its own container that only
runs if you activate it. Currently available:

| Adapter      | What it's for                           |
|--------------|-----------------------------------------|
| `mailgun`    | Sending player-facing email             |
| `voiso`      | Telephony (click-to-call, call logging) |
| `sms-retail` | SMS messaging                           |

You don't need to decide everything up front — activating an adapter is a
one-line edit to `.env` at any time, no reinstall needed:

```
COMPOSE_PROFILES=mailgun,voiso
```

Then:

```bash
docker compose -f docker-compose.on-premise.yml up -d
```

The newly-activated adapter's container starts; everything else is
untouched. Once running, configure that integration's actual account
credentials inside the CRM — Project Settings → Adapter Credentials.

### Ports

Each service is reachable on a host port — defaults shown below. Press
Enter during the interactive prompts to accept a default, or override any
of them (via the prompt, or the matching flag) if it conflicts with
something already running on your server.

| Service            | Default | Flag                         |
|--------------------|--------:|------------------------------|
| API                |    8000 | `--api-port=`                |
| Connector          |    8001 | `--connector-port=`          |
| Frontend           |    3000 | `--frontend-port=`           |
| Super admin        |    3001 | `--superadmin-port=`         |
| MinIO S3 API       |    9000 | `--minio-port=`              |
| MinIO console      |    9001 | `--minio-console-port=`      |
| Mailgun adapter    |    8002 | `--adapter-mailgun-port=`    |
| Voiso adapter      |    8003 | `--adapter-voiso-port=`      |
| SMS-RETAIL adapter |    8004 | `--adapter-sms-retail-port=` |

Every port must be unique — even for an adapter you haven't activated yet,
since its port is still reserved in `.env` for whenever you do activate it.
`install.sh` validates this and refuses to continue if two ports collide.

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

  --adapters=...                 Optional, comma-separated. Leave empty to run with none —
                                 you can add adapters later by editing COMPOSE_PROFILES in
                                 .env and running docker compose up -d.

  --api-port=...                 Host port for the API (defaults to 8000 if left blank interactively)
  --connector-port=...           Host port for the connector (defaults to 8001)
  --frontend-port=...            Host port for the CRM frontend (defaults to 3000)
  --superadmin-port=...          Host port for the super admin panel (defaults to 3001)
  --minio-port=...               Host port for the MinIO S3 API (defaults to 9000)
  --minio-console-port=...       Host port for the MinIO web console (defaults to 9001)
  --adapter-mailgun-port=...     Host port for the mailgun adapter (defaults to 8002)
  --adapter-voiso-port=...       Host port for the voiso adapter (defaults to 8003)
  --adapter-sms-retail-port=...  Host port for the sms-retail adapter (defaults to 8004)

  --resume                       Reuse an existing .env instead of generating a new one
                                 (use this to retry after a failed first-time install)

  --help, -h                     Show this message and exit
```

`install.sh` runs `./preflight.sh` before any of this, forwarding whatever
flags you passed — see "Checking Readiness First" above.

Example, fully non-interactive:

```bash
./install.sh --domain=crm.yourcompany.com --super-admin-domain=admin.yourcompany.com \
  --license=<your-license> --mail-provider=smtp --smtp-host=... --smtp-port=587 \
  --smtp-username=... --smtp-password=... --mail-sender="Your Company <noreply@yourcompany.com>" \
  --super-admin-email=you@yourcompany.com --adapters=mailgun,voiso
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

### Using External Object Storage (Optional)

MinIO ships bundled by default — zero extra setup, works out of the box for
tenant branding assets (logos) and call recordings (once you activate a
telephony adapter). If you'd rather use your own S3-compatible storage (AWS
S3, DigitalOcean Spaces, Cloudflare R2, Backblaze B2, Wasabi, or anything
else that speaks the S3 API), you can swap it in instead. This is entirely
optional — skip this if MinIO is fine for you.

1. Create the bucket on your provider and generate an access key/secret pair
   for it.
2. Update these values in `.env`:
   ```
   S3_ENDPOINT=<your provider's endpoint, e.g. https://fra1.digitaloceanspaces.com>
   S3_REGION=<your region>
   S3_BUCKET=<your bucket name>
   S3_ACCESS_KEY=<your access key>
   S3_SECRET_KEY=<your secret key>
   S3_USE_ACL=true
   S3_PUBLIC_URL=<your provider's public/CDN URL for this bucket, if it has one>
   ```
   `S3_ENDPOINT` is the plain API endpoint only — no bucket name in it. Some
   providers publish public assets (like tenant branding logos) through a
   separate CDN/public URL that includes the bucket name — if yours does,
   that full URL goes in `S3_PUBLIC_URL`, not `S3_ENDPOINT`.
3. Remove MinIO from the compose file — open `docker-compose.on-premise.yml`
   and delete the `minio` and `minio-init` service blocks, the `minio_data`
   volume at the bottom, and the `minio-init:` entry under `depends_on:` in
   both `api` and `adapter_voiso` (only remove that dependency, not the whole
   `depends_on:` block — `api` and `adapter_voiso` still depend on `postgres`
   and `redis`).
4. Restart:
   ```bash
   docker compose -f docker-compose.on-premise.yml up -d --remove-orphans
   ```

**If you already have real files in MinIO**, they don't move automatically —
copy them to your new bucket yourself (e.g. with the
[`mc mirror`](https://min.io/docs/minio/linux/reference/minio-mc/mc-mirror.html)
tool) before cutting over, or existing branding assets/recordings will stop
loading. Easiest to do this before you have real data at all, if you know
upfront you'll want external storage.

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

    # Only needed for adapters you've activated (section 4) — each routes to
    # its own container's port. Harmless to leave in for an adapter you
    # haven't activated; it just never receives traffic since you won't have
    # given that webhook URL to the vendor.
    location /webhooks/mailgun {
        proxy_pass http://localhost:8002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /webhooks/voiso {
        proxy_pass http://localhost:8003;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /webhooks/sms-retail {
        proxy_pass http://localhost:8004;
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

**New configuration is handled automatically.** If a release adds something
new to `.env` (a new adapter's port, for example), `update.sh` fills it in
for you — generating a fresh secret or using a sensible default, whichever
applies. You don't need to track what changed between versions yourself.

The only time it stops and asks is when a new setting genuinely needs a
value only you can provide (e.g. a new integration's account details). In
that case it prints exactly which value(s) to add to `.env` and exits
without touching your running containers — add them, then re-run the same
`./update.sh <version>` command.

**Checking for updates**: `./update.sh --check` is read-only — it prints
your currently installed version and tells you whether a newer one is
available, without changing anything.

**Rollback**: `./update.sh --rollback` goes back to the last version that
was running before your most recent successful update. It tracks this in a
small `.version_history` file kept alongside `.env`, so you don't need to
remember version numbers yourself. Running it twice in a row keeps
continuing further back through your update history, rather than bouncing
between the same two versions. If there's nothing to roll back to (a fresh
install that's never been updated, or this file is missing), it says so
plainly and doesn't touch your running containers — you can still update or
roll back to any specific version manually with `./update.sh <version>`.

Every successful update or rollback also prints a link to that version's
release notes, so you can see what changed.

---

## 10. Troubleshooting

**`install.sh` stops immediately with "Preflight found critical issues"**
Not a bug — `install.sh` runs `./preflight.sh` automatically before touching
anything, and stops if something would guarantee failure (Docker not
running, wrong CPU architecture, a port conflict, etc). Run `./preflight.sh`
on its own to see the full list of what's wrong, fix it, then re-run
`./install.sh`.

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

**`update.sh` stops with "Bundle X requires new config you need to provide manually"**
Not an error — this update introduced a setting only you can supply (see
section 9). Add the listed key(s) to `.env` with a real value, then re-run
the same `./update.sh <version>` command. Nothing was restarted yet, so
there's nothing to roll back.

**An activated adapter isn't receiving anything from the vendor (e.g. no delivery-status webhooks)**
Check that your reverse proxy actually routes that adapter's `/webhooks/...`
path to its container's port (section 6), and that you've given the vendor
the correct public URL for it.

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