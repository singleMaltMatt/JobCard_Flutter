### 1. Install Essential Packages

# Update system
sudo pacman -Syu

# Install essential packages
sudo pacman -S --needed \
  git \
  wget \
  curl \
  nano \
  nginx \
  nodejs \
  npm \
  openssh \
  sqlite \
  unzip \
  base-devel

# Update npm
sudo npm install -g npm@latest

### 2. Install Additional Tools

# Install Chromium (for Puppeteer)
sudo pacman -S --needed chromium

# Install cloudflared via AUR
yay -S cloudflared

### Nginx Installation & Configuration
1. Verify Nginx Installation

nginx -v

2. Create Nginx Configuration

# Create sites-enabled directory
sudo mkdir -p /etc/nginx/sites-enabled

# Create the JobCard Tracker config
sudo nano /etc/nginx/sites-enabled/jobcard_tracker.conf

#### Add the following configuration

```
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

sudo nano /etc/nginx/nginx.conf

include /etc/nginx/sites-enabled/*;

# Start Nginx and enable on boot
sudo systemctl enable --now nginx

# Verify it's running
sudo systemctl status nginx

# To reload config after changes
sudo systemctl reload nginx

### PocketBase Installation & Setup
1. Download PocketBase

# Go to https://github.com/pocketbase/pocketbase/releases
# Download the linux_amd64 version (CachyOS is x86_64)

cd ~
wget https://github.com/pocketbase/pocketbase/releases/download/v0.22.0/pocketbase_0.22.0_linux_amd64.zip

# Unzip
unzip pocketbase_0.22.0_linux_amd64.zip

# Make executable and move to PATH
chmod +x pocketbase
sudo mv pocketbase /usr/local/bin/

2. Create PocketBase Data Directory

mkdir -p ~/pocketbase_data

3. Run PocketBase as a systemd Service
Rather than keeping a terminal open, run PocketBase as a proper background service:

sudo nano /etc/systemd/system/pocketbase.service

[Unit]
Description=PocketBase
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
ExecStart=/usr/local/bin/pocketbase serve --http="127.0.0.1:8090" --dir=/home/YOUR_USERNAME/pocketbase_data
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target

ou only need two collections: clients and jobs (users is built-in). The API method via curl requires an auth token first, so the UI is easier here. Let's do it that way.
Go to http://127.0.0.1:8090/_/ and log in, then:

Collection 1: clients

Click New collection → name it clients → type Base
Add these fields:

name — Text, required
email — Text
phone — Text
address — Text


Go to API Rules, set all five rules (List/View/Create/Update/Delete) to: @request.auth.id != ""
Save

Collection 2: jobs

New collection → name it jobs → type Base
Add these fields:

client — Relation → Collection: clients, required
user — Relation → Collection: users, required
status — Select, required → add options: pending, accepted, on_route, on_site, completed
description — Editor
signature — File
email_sent — Bool, default false
calendar_date — Text


Go to API Rules, set all five rules to: @request.auth.id != "" && user = @request.auth.id
Save

Easy. Since you already have cloudflared installed:

cloudflared tunnel --url http://localhost:80

Perfect, full stack is working end to end. Let's move on to the Puppeteer PDF service. Run this:

mkdir -p ~/pdf-service
cd ~/pdf-service
npm init -y
npm install puppeteer express body-parser cors

Now create the server file, but with the Chromium path updated for CachyOS (not the Termux path in the original doc):

nano ~/pdf-service/server.js

```
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const puppeteer = require('puppeteer');

const app = express();
const PORT = 3001;

app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '50mb' }));

app.post('/generate-pdf', async (req, res) => {
  try {
    const { clientName, clientAddress, jobDate, description, signature, status, companyLogo } = req.body;

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; margin: 40px; }
          .header { background-color: #1976D2; color: white; padding: 20px; text-align: center; border-radius: 8px; }
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
          <div class="value"><span class="label">Name:</span> ${clientName || 'N/A'}</div>
          <div class="value"><span class="label">Address:</span> ${clientAddress || 'N/A'}</div>
          <div class="value"><span class="label">Job Date:</span> ${jobDate || 'N/A'}</div>
          <div class="value"><span class="label">Status:</span> <span class="status-badge">${status ? status.toUpperCase() : 'COMPLETED'}</span></div>
        </div>
        <div class="section">
          <div class="section-title">Work Description</div>
          <p>${description || 'No description provided.'}</p>
        </div>
        ${signature ? `
        <div class="signature-area">
          <div class="section-title">Client Signature</div>
          <img class="signature-img" src="${signature}" alt="Client Signature" />
        </div>` : ''}
        <div class="footer">
          <p>Generated on ${new Date().toLocaleString()} | JobCard Tracker v1.0</p>
          <p>This is a computer-generated document.</p>
        </div>
      </body>
      </html>
    `;

    const browser = await puppeteer.launch({
      headless: 'new',
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
      executablePath: '/usr/bin/chromium'  // CachyOS path
    });

    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle0' });

    const pdfBuffer = await page.pdf({
      format: 'A4',
      printBackground: true,
      margin: { top: '20px', right: '20px', bottom: '20px', left: '20px' }
    });

    await browser.close();

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename=jobcard-${Date.now()}.pdf`);
    res.send(pdfBuffer);

  } catch (error) {
    console.error('PDF Generation Error:', error);
    res.status(500).json({ error: 'Failed to generate PDF', details: error.message });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'pdf-generator' });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`PDF Generator service running on port ${PORT}`);
});
```

Now set it up as a systemd service so it starts automatically like PocketBase:


sudo nano /etc/systemd/system/pdf-service.service

[Unit]
Description=JobCard PDF Generator
After=network.target

[Service]
Type=simple
User=matt
ExecStart=/usr/bin/node /home/matt/pdf-service/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target

sudo systemctl daemon-reload
sudo systemctl enable --now pdf-service
sudo systemctl status pdf-service

mkdir -p ~/email-service
cd ~/email-service
npm init -y
npm install express body-parser cors resend

nano ~/email-service/server.js

```
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { Resend } = require('resend');

const resend = new Resend('re_YOUR_API_KEY_HERE');

const app = express();
const PORT = 3002;

app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));

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

    const { data, error } = await resend.emails.send({
      from: 'onboarding@resend.dev',
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

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'email-service' });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`Email service running on port ${PORT}`);
});
```

sudo nano /etc/systemd/system/email-service.service

[Unit]
Description=JobCard Email Service
After=network.target

[Service]
Type=simple
User=matt
ExecStart=/usr/bin/node /home/matt/email-service/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target

sudo systemctl daemon-reload
sudo systemctl enable --now email-service
sudo systemctl status email-service

