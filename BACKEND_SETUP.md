# JobCard Tracker - Backend Setup Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Termux Setup on Android](#termux-setup-on-android)
4. [Nginx Installation & Configuration](#nginx-installation--configuration)
5. [PocketBase Installation & Setup](#pocketbase-installation--setup)
6. [Database Collections / Tables](#database-collections--tables)
7. [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
8. [Puppeteer for PDF Generation](#puppeteer-for-pdf-generation)
9. [Resend Email Service](#resend-email-service)
10. [Flutter App Configuration](#flutter-app-configuration)
11. [Testing the Full Stack](#testing-the-full-stack)

---

## Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Architecture                           │
│                                                          │
│  Flutter App (Android)                                    │
│       │                                                   │
│       ▼ (HTTPS via Cloudflare)                           │
│  Cloudflare Tunnel ──── Cloudflare Edge                   │
│       │                                                   │
│       ▼ (Local)                                          │
│  Nginx (Reverse Proxy on Android via Termux)              │
│       │                                                   │
│       ├──► PocketBase (Port 8090) - Database + Auth      │
│       │                                                   │
│       ├──► Puppeteer (Port 3001) - PDF Generation        │
│       │                                                   │
│       └──► Resend API - Email Service                     │
│                                                          │
│  All Free / Open-Source Tools                             │
│  - PocketBase: Self-hosted OSS Backend                    │
│  - Cloudflare Tunnel: Free tier                           │
│  - Resend: 100 emails/day free tier                       │
│  - Puppeteer: Open-source                                 │
│  - Nginx: Open-source                                     │
└─────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- Android device (phone or tablet)
- Termux app installed from F-Droid (not Google Play)
- Internet connection
- A domain name (for Cloudflare)
- A Resend account (free tier)

---

## Termux Setup on Android

### 1. Install Termux

Download Termux from **F-Droid** (NOT Google Play):
- Open F-Droid: https://f-droid.org/packages/com.termux/
- Install Termux
- Also install Termux:API for storage access

### 2. Initial Termux Setup

Open Termux and run:

```bash
# Update packages
pkg update && pkg upgrade -y

# Grant storage permission (accept on phone)
termux-setup-storage

# Install essential packages
pkg install -y \
  git \
  wget \
  curl \
  nano \
  nginx \
  nodejs \
  openssh \
  sqlite \
  unzip \
  build-essential

# Update npm
npm install -g npm@latest
```

### 3. Install Additional Tools

```bash
# Install puppeteer dependencies for Chromium
pkg install -y \
  chromium \
  tur-repo \
  libnss \
  nspr \
  atk \
  at-spi2-atk \
  gtk3 \
  cairo \
  pango \
  libxkbcommon

# Install cloudflared (Cloudflare Tunnel)
pkg install -y cloudflared
```

---

## Nginx Installation & Configuration

### 1. Install Nginx

```bash
# Nginx should already be installed from the packages above
# Verify installation
nginx -v
```

### 2. Create Nginx Configuration

```bash
# Create config directory
mkdir -p $PREFIX/etc/nginx/sites-enabled

# Create the JobCard Tracker config
nano $PREFIX/etc/nginx/sites-enabled/jobcard_tracker.conf
```

Add the following configuration:

```nginx
server {
    listen 80;
    server_name localhost;

    # Increase max body size for file uploads (signatures)
    client_max_body_size 50M;

    # PocketBase API
    location /api/ {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # PocketBase Admin UI
    location /_/ {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Puppeteer PDF generation service
    location /pdf/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Default route
    location / {
        return 404;
    }
}
```

### 3. Start Nginx

```bash
# Edit main nginx.conf to include sites-enabled
nano $PREFIX/etc/nginx/nginx.conf
```

Add this line inside the `http { }` block:
```nginx
include $PREFIX/etc/nginx/sites-enabled/*;
```

```bash
# Start Nginx
nginx

# Verify it's running
ps aux | grep nginx

# To stop (if needed)
# nginx -s stop

# To reload config after changes
# nginx -s reload
```

---

## PocketBase Installation & Setup

### 1. Download PocketBase

```bash
# Find the latest ARM64 release for Android/Termux
# Go to: https://github.com/pocketbase/pocketbase/releases
# Download the linux_arm64 version

# Using wget (replace VERSION with latest, e.g., 0.22.0):
cd ~
wget https://github.com/pocketbase/pocketbase/releases/download/v0.22.0/pocketbase_0.22.0_linux_arm64.zip

# Unzip
unzip pocketbase_0.22.0_linux_arm64.zip

# Make executable
chmod +x pocketbase

# Move to a permanent location
mv pocketbase $PREFIX/bin/
```

### 2. Create PocketBase Data Directory

```bash
# Create a directory for PocketBase data
mkdir -p ~/pocketbase_data
cd ~/pocketbase_data
```

### 3. Start PocketBase

```bash
# Start PocketBase
cd ~/pocketbase_data
pocketbase serve --http="127.0.0.1:8090"
```

**Note:** Keep this terminal running. Use Termux's notification panel to keep it alive, or use `tmux`:

```bash
# Install tmux
pkg install -y tmux

# Create a session
tmux new -s pocketbase

# Inside tmux, start PocketBase
pocketbase serve --http="127.0.0.1:8090"

# Detach with Ctrl+B then D
# Reattach with: tmux attach -t pocketbase
```

### 4. Create Admin User

1. Open a browser on your phone (or another device on same network)
2. Go to: `http://YOUR_PHONE_IP:8090/_/`
   - Find your IP with: `ifconfig` or `ip a`
3. Create the admin account:
   - Email: `admin@yourdomain.com`
   - Password: (choose a strong password - min 10 characters)

### 5. Enable CORS for Flutter App

In PocketBase admin panel:
1. Go to **Settings** → **Application**
2. Find **CORS** section
3. Add your domain to `Allowed Origins`:
   - `*` (for development)
   - Or your specific Cloudflare domain
4. Save settings

### 6. Create API Rules (Permissions)

For each collection, you'll need to set appropriate API rules so the Flutter app can read/write data.

---

## Database Collections / Tables

You can create collections either through the PocketBase Admin UI or via the API.

### Method A: Via Admin UI

Go to `http://YOUR_PHONE_IP:8090/_/` → **Collections** → **New Collection**

### Method B: Via API (Recommended)

Save this as a shell script or run each `curl` command:

#### Collection 1: `users` (Built-in)

PocketBase comes with a built-in `users` collection. It has these fields:
- `id` (auto)
- `email` (text, required, unique)
- `password` (password, hidden)
- `username` (text, optional)
- `avatar` (file, optional)
- `verified` (bool)
- `created` (auto)
- `updated` (auto)

**No need to create this** - it exists by default.

#### Collection 2: `clients`

**Fields:**

| Field Name | Type     | Required | Other              |
|------------|----------|----------|--------------------|
| name       | text     | Yes      | -                  |
| email      | text     | No       | -                  |
| phone      | text     | No       | -                  |
| address    | text     | No       | -                  |

**API Rules (under "Collection" settings):**
- **List Rule:** `@request.auth.id != ""`
- **View Rule:** `@request.auth.id != ""`
- **Create Rule:** `@request.auth.id != ""`
- **Update Rule:** `@request.auth.id != ""`
- **Delete Rule:** `@request.auth.id != ""`

#### Collection 3: `jobs`

**Fields:**

| Field Name    | Type        | Required | Other                                 |
|---------------|-------------|----------|---------------------------------------|
| client        | relation    | Yes      | Collection: clients                   |
| user          | relation    | Yes      | Collection: users                     |
| status        | select      | Yes      | Options: pending, accepted, on_route, on_site, completed |
| description   | editor      | No       | -                                     |
| signature     | file        | No       | -                                     |
| email_sent    | bool        | No       | Default: false                        |
| calendar_date | text        | No       | -                                     |

**API Rules:**
- **List Rule:** `@request.auth.id != "" && user = @request.auth.id`
- **View Rule:** `@request.auth.id != "" && user = @request.auth.id`
- **Create Rule:** `@request.auth.id != "" && user = @request.auth.id`
- **Update Rule:** `@request.auth.id != "" && user = @request.auth.id`
- **Delete Rule:** `@request.auth.id != "" && user = @request.auth.id`

---

## Cloudflare Tunnel Setup

### 1. Prerequisites

- A domain managed by Cloudflare
- Cloudflared installed (done in Termux setup)

### 2. Log in to Cloudflare

```bash
# Authenticate cloudflared
cloudflared tunnel login

# This opens a URL - copy it to your phone's browser
# Log in to your Cloudflare account
# Select your domain
```

### 3. Create a Tunnel

```bash
# Create tunnel (give it a name, e.g., "jobcard-tracker")
cloudflared tunnel create jobcard-tracker

# This creates a credentials file and gives you a Tunnel ID
# Example output:
# Created tunnel jobcard-tracker with id abc123-xxx-xxx-xxx
```

### 4. Configure the Tunnel

```bash
# Create config directory
mkdir -p ~/.cloudflared

# Create config file
nano ~/.cloudflared/config.yml
```

Add this configuration:

```yaml
tunnel: jobcard-tracker
credentials-file: /data/data/com.termux/files/home/.cloudflared/abc123-xxx-xxx-xxx.json  # Replace with actual ID

ingress:
  # Route everything to local Nginx
  - hostname: api.yourdomain.com  # Replace with your subdomain
    service: http://localhost:80
  - service: http_status:404
```

### 5. Configure DNS

```bash
# Route your domain through the tunnel
cloudflared tunnel route dns jobcard-tracker api.yourdomain.com

# Replace api.yourdomain.com with your desired subdomain
```

### 6. Start the Tunnel

Keep the tunnel running in a tmux session:

```bash
# Create a tmux session
tmux new -s tunnel

# Start the tunnel
cloudflared tunnel run jobcard-tracker

# Detach: Ctrl+B, then D
# Reattach: tmux attach -t tunnel
```

### 7. Auto-start Tunnel (Optional)

Create a startup script:

```bash
# Create a script
nano ~/start-services.sh
```

```bash
#!/data/data/com.termux/files/usr/bin/bash

# Start PocketBase
cd ~/pocketbase_data
pocketbase serve --http="127.0.0.1:8090" &

# Start Nginx
nginx

# Start Cloudflare Tunnel
cloudflared tunnel run jobcard-tracker &

# Start PDF service (next section)
node ~/pdf-service/server.js &
```

```bash
chmod +x ~/start-services.sh
```

---

## Puppeteer for PDF Generation

### 1. Create PDF Service Directory

```bash
# Create project directory
mkdir -p ~/pdf-service
cd ~/pdf-service

# Initialize Node.js project
npm init -y

# Install dependencies
npm install puppeteer express body-parser cors
```

### 2. Create PDF Server

```bash
nano server.js
```

```javascript
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const puppeteer = require('puppeteer');

const app = express();
const PORT = 3001;

app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '50mb' }));

// Generate PDF from job data
app.post('/generate-pdf', async (req, res) => {
  try {
    const { clientName, clientAddress, jobDate, description, signature, status, companyLogo } = req.body;

    // Build HTML template for the PDF
    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; margin: 40px; }
          .header { 
            background-color: #1976D2; 
            color: white; 
            padding: 20px; 
            text-align: center;
            border-radius: 8px;
          }
          .company-name { font-size: 24px; font-weight: bold; }
          .title { font-size: 18px; margin-top: 5px; }
          .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 8px; }
          .section-title { font-size: 16px; font-weight: bold; color: #1976D2; margin-bottom: 10px; }
          .label { font-weight: bold; color: #666; }
          .value { margin-bottom: 10px; }
          .signature-area { margin-top: 20px; padding: 15px; border: 1px solid #ddd; border-radius: 8px; }
          .signature-img { max-width: 300px; max-height: 100px; }
          .footer { margin-top: 30px; text-align: center; color: #999; font-size: 12px; }
          .status-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 15px;
            color: white;
            background-color: ${status === 'completed' ? '#4CAF50' : '#1976D2'};
            font-weight: bold;
            font-size: 14px;
          }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="company-name">JobCard Tracker</div>
          <div class="title">Job Completion Report</div>
        </div>

        <div class="section">
          <div class="section-title">Client Information</div>
          <div class="value">
            <span class="label">Name:</span> ${clientName || 'N/A'}
          </div>
          <div class="value">
            <span class="label">Address:</span> ${clientAddress || 'N/A'}
          </div>
          <div class="value">
            <span class="label">Job Date:</span> ${jobDate || 'N/A'}
          </div>
          <div class="value">
            <span class="label">Status:</span> 
            <span class="status-badge">${status ? status.toUpperCase() : 'COMPLETED'}</span>
          </div>
        </div>

        <div class="section">
          <div class="section-title">Work Description</div>
          <p>${description || 'No description provided.'}</p>
        </div>

        ${signature ? `
        <div class="signature-area">
          <div class="section-title">Client Signature</div>
          <img class="signature-img" src="${signature}" alt="Client Signature" />
        </div>
        ` : ''}

        <div class="footer">
          <p>Generated on ${new Date().toLocaleString()} | JobCard Tracker v1.0</p>
          <p>This is a computer-generated document.</p>
        </div>
      </body>
      </html>
    `;

    // Launch Puppeteer
    const browser = await puppeteer.launch({
      headless: 'new',
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
      executablePath: '/data/data/com.termux/files/usr/bin/chromium' // Termux path
    });

    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle0' });

    // Generate PDF
    const pdfBuffer = await page.pdf({
      format: 'A4',
      printBackground: true,
      margin: { top: '20px', right: '20px', bottom: '20px', left: '20px' }
    });

    await browser.close();

    // Send the PDF
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename=jobcard-${Date.now()}.pdf`);
    res.send(pdfBuffer);

  } catch (error) {
    console.error('PDF Generation Error:', error);
    res.status(500).json({ error: 'Failed to generate PDF', details: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'pdf-generator' });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`PDF Generator service running on port ${PORT}`);
});
```

### 3. Test PDF Service

```bash
# Start the service in a tmux session
tmux new -s pdf-service
node ~/pdf-service/server.js
# Detach: Ctrl+B, D

# Test it
curl -X POST http://127.0.0.1:3001/generate-pdf \
  -H "Content-Type: application/json" \
  -d '{
    "clientName": "Test Client",
    "clientAddress": "123 Test St",
    "jobDate": "2024-01-01",
    "description": "Test work completed",
    "status": "completed"
  }' --output test.pdf
```

---

## Resend Email Service

### 1. Create Resend Account

1. Go to https://resend.com
2. Sign up for a free account
3. Verify your domain (or use the test domain `onresend.com` for development)

### 2. Get API Key

1. In Resend dashboard, go to **API Keys**
2. Click **Create API Key**
3. Give it a name like "JobCard Tracker"
4. Copy the API key (starts with `re_...`)

### 3. Create Email Service (Backend)

```bash
# Create service directory
mkdir -p ~/email-service
cd ~/email-service
npm init -y
npm install express body-parser cors resend
```

```bash
nano server.js
```

```javascript
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { Resend } = require('resend');

// Initialize Resend with your API key
const resend = new Resend('re_YOUR_API_KEY_HERE'); // Replace with actual key

// For production, use environment variable:
// const resend = new Resend(process.env.RESEND_API_KEY);

const app = express();
const PORT = 3002;

app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));

// Send job completion email
app.post('/send-email', async (req, res) => {
  try {
    const { to, subject, clientName, clientAddress, jobDate, description, pdfBase64 } = req.body;

    const htmlContent = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background-color: #1976D2; padding: 20px; text-align: center; border-radius: 8px 8px 0 0;">
          <h1 style="color: white; margin: 0;">JobCard Tracker</h1>
        </div>
        
        <div style="padding: 20px; border: 1px solid #ddd; border-top: none;">
          <h2>Job Completed Successfully</h2>
          
          <p>Dear ${clientName},</p>
          <p>We are pleased to inform you that the job has been completed.</p>
          
          <div style="background-color: #f5f5f5; padding: 15px; border-radius: 8px; margin: 20px 0;">
            <p><strong>Client:</strong> ${clientName}</p>
            <p><strong>Address:</strong> ${clientAddress}</p>
            <p><strong>Date:</strong> ${jobDate}</p>
          </div>
          
          <h3>Work Completed</h3>
          <p>${description || 'No description provided.'}</p>
          
          <p>Please find the job card PDF attached to this email.</p>
          
          <p>Thank you for choosing our services.</p>
          
          <p style="color: #666; font-size: 12px; margin-top: 30px;">
            JobCard Tracker v1.0 | This is an automated email
          </p>
        </div>
      </div>
    `;

    // Send email with Resend
    const { data, error } = await resend.emails.send({
      from: 'JobCard Tracker <noreply@yourdomain.com>', // Replace with your verified domain
      to: [to],
      subject: subject || 'Job Completed - JobCard Tracker',
      html: htmlContent,
      attachments: pdfBase64 ? [
        {
          filename: `jobcard-${Date.now()}.pdf`,
          content: pdfBase64,
        }
      ] : [],
    });

    if (error) {
      console.error('Resend Error:', error);
      return res.status(400).json({ error: error.message });
    }

    res.json({ success: true, data });

  } catch (error) {
    console.error('Email Service Error:', error);
    res.status(500).json({ error: 'Failed to send email', details: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'email-service' });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`Email service running on port ${PORT}`);
});
```

### 4. Run the Email Service

```bash
# Start in tmux
tmux new -s email-service
node ~/email-service/server.js
# Detach: Ctrl+B, D
```

---

## Flutter App Configuration

### 1. Update API Config

Edit `lib/config/api_config.dart` in the Flutter app:

```dart
// For production (via Cloudflare tunnel):
static const String baseUrl = 'https://api.yourdomain.com';

// For local testing (Android emulator):
// static const String baseUrl = 'http://10.0.2.2:8090';

// For local testing (physical device on same network):
// static const String baseUrl = 'http://192.168.x.x:8090';
```

### 2. Build the Flutter App

```bash
# On your development machine (where Flutter SDK is installed):
cd jobcard_tracker

# Get dependencies
flutter pub get

# Build for Android
flutter build apk --release

# The APK will be at:
# build/app/outputs/flutter-apk/app-release.apk
```

### 3. Install on Android

- Transfer the APK to your phone
- Enable "Install from Unknown Sources" in Settings
- Install the APK
- Open the app

---

## Testing the Full Stack

### 1. Verify Services Are Running

In Termux, run:

```bash
# Check running processes
ps aux | grep -E "(pocketbase|cloudflared|nginx|node)"

# Expected output:
# - pocketbase serve
# - cloudflared tunnel
# - nginx (master + worker processes)
# - node (pdf-service + email-service)
```

### 2. Test Each Layer

```bash
# Test Nginx
curl http://127.0.0.1/api/health

# Test PocketBase
curl http://127.0.0.1:8090/api/health

# Test PDF service
curl http://127.0.0.1:3001/health

# Test Email service
curl http://127.0.0.1:3002/health

# Test via Cloudflare (from external device)
curl https://api.yourdomain.com/api/health
```

### 3. Troubleshooting

**PocketBase won't start:**
```bash
# Check if port is in use
lsof -i :8090

# Kill existing process
killall pocketbase
```

**Cloudflare Tunnel not connecting:**
```bash
# Check tunnel status
cloudflared tunnel info jobcard-tracker

# Restart tunnel
cloudflared tunnel run jobcard-tracker
```

**Nginx not starting:**
```bash
# Check config syntax
nginx -t

# Check error log
cat $PREFIX/var/log/nginx/error.log
```

**Flutter app can't connect:**
- Verify the device has internet access
- Check that Cloudflare tunnel is running
- Check CORS settings in PocketBase admin
- Make sure the URL in `api_config.dart` is correct

---

## Summary of Running Services

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| Nginx | 80 | Local/Cloudflare | Reverse proxy |
| PocketBase | 8090 | Local only | Database & Auth |
| PDF Generator | 3001 | Local only | Generate job PDFs |
| Email Service | 3002 | Local only | Send emails via Resend |
| Cloudflare Tunnel | - | Public | Expose services securely |

## Starting Everything

After restarting your phone, run:

```bash
# Create a startup script
~/start-services.sh

# Or manually start each in separate tmux sessions:
tmux new -s pocketbase -d 'cd ~/pocketbase_data && pocketbase serve --http="127.0.0.1:8090"'
tmux new -s nginx -d 'nginx'
tmux new -s tunnel -d 'cloudflared tunnel run jobcard-tracker'
tmux new -s pdf -d 'node ~/pdf-service/server.js'
tmux new -s email -d 'node ~/email-service/server.js'
```

---

## Security Notes

1. **Change default passwords** for PocketBase admin
2. **Use strong API keys** for Resend
3. **Keep Cloudflare tunnel credentials** secure
4. **Restrict CORS** to your domain only in production
5. **Use HTTPS** via Cloudflare (enforce it in Cloudflare dashboard)
6. **Regularly update** all packages in Termux: `pkg upgrade`
7. **Back up PocketBase data** regularly: `cp -r ~/pocketbase_data/pb_data ~/backup/`

---

## Free Tier Limits

| Service | Limit |
|---------|-------|
| Resend | 100 emails/day |
| Cloudflare Tunnel | Unlimited bandwidth (free tier) |
| PocketBase | Self-hosted, no limits |
| Puppeteer | Self-hosted, no limits |

---

## Next Steps / Future Enhancements

1. **2FA Authentication** - PocketBase supports TOTP 2FA via authenticator apps like Microsoft Authenticator
2. **Push Notifications** - Integrate Firebase Cloud Messaging for job alerts
3. **Offline Support** - Add local SQLite storage for offline job management
4. **File Uploads** - Add photo attachments to job cards
5. **Scheduling** - Calendar integration for job scheduling
6. **Analytics Dashboard** - Job completion rates, average times, etc.
7. **Multi-user Support** - Team management with different roles