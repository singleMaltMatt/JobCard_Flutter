# JobCard Tracker — Project Context & Reference

_Last updated: 24 Aug 2026 (sales portal steps 1–3c complete, pre-deploy)_

## What this is
Internal MSP job-card tracking system for GlobalSense (globalsense.co.za, "Make IT happen"). Technicians create/complete jobs on-site via a Flutter Android app; completed jobs generate a branded PDF job card, optionally emailed to the client, with analytics in Metabase. A **sales portal** (`/sales/`) lets the sales user schedule deliveries/collections and assign them to technicians. Built and tested on a CachyOS dev machine, migrated to production on an Arch (EndeavourOS) VM at the office.

## People / Users
- **Matthew van Schalkwyk** (matthew@globalsense.co.za) — developer/admin, does Gauteng Akeso sites. Dev machine: CachyOS, username `matt`. **Repo path: `/home/matt/Development/JobCard_Flutter`** (moved from `~/JobCard_Flutter` with the new laptop).
- Head office staff: Johan du Toit, Thabiso Macanda (is_head_office = true).
- **Kelly Kruger** — sales (is_sales = true), uses the `/sales/` portal.
- **Outsourced techs** (B2E Technologies, CNM IT, IT Experts, IT Outlook, IT Vision, Landmate, Leaf Technologies, Micro Ellis) — only service Akeso sites; restricted client visibility. Excluded from sales orders (they log deliveries/collections as `call_out` jobs instead).

## User flags (`users` collection)
| Flag | Meaning |
|---|---|
| `is_head_office` | Head office staff — sees all clients and all jobs |
| `is_sales` | Access to the `/sales/` portal; sees all clients, jobs, users |
| `is_internal` | Internal (non-outsourced) technician — eligible for sales-order assignment; populates the portal's tech dropdown |

## Production server
- Arch/EndeavourOS VM `GS-JobTracking`, user `globaladmin`, IP `10.0.9.40`, hosted on PetaSAN-backed hypervisor.
- Public domain: **https://jobtracking.globalsense.co.za** (Let's Encrypt via certbot, auto-renew). MikroTik forwards ports 80/443 → 10.0.9.40. NAT hairpinning NOT supported — test HTTPS locally with `curl -k https://127.0.0.1/...` (port 80 server block is certbot redirect-only, always 404s).

## Architecture (all services bind 127.0.0.1, systemd-managed, nginx reverse proxy)
| Service | Port | Path | Notes |
|---|---|---|---|
| PocketBase v0.39 | 8090 | /api/, /_/ | binary /usr/local/bin/pocketbase, data ~/pocketbase_data, hooks via `--hooksDir` flag (required!) |
| PDF service (Node/Puppeteer) | 3001 | /pdf/ | ~/pdf-service/server.js, Chromium at /usr/bin/chromium, logo embedded as base64 const. Also uses **pdf-lib** for merging. |
| Email service (Node/nodemailer) | 3002 | /email/ | ~/email-service/server.js, SMTP mail.globalsense.co.za:2525, user relaygs@globalsense.co.za, from info@globalsense.co.za, secure:false, rejectUnauthorized:false; splits `to` on `;` for multi-recipient |
| Metabase | 3003 | /analytics/ | ~/metabase/metabase.jar, H2 db ~/metabase/metabase.db(.mv.db), MB_DB_FILE env var |
| Static | — | /static/, /download/, /app/, /sales/ | logo, APK distribution + version.json, Flutter web builds |

nginx config: /etc/nginx/sites-enabled/jobcard_tracker.conf (include line added to nginx.conf http block; mime.types had to be manually downloaded — Arch nginx package quirk).

## PocketBase
- **Superuser**: admin@globalsense.co.za. App users are in `users` collection (cannot access admin panel). Superusers are a **separate auth collection** (`_superusers`) with their own endpoint — superuser creds fail against the `users` login endpoint.
- **Collections**: users, clients, jobs, **suppliers**, **sales_orders**.
- **jobs fields**: client (rel), user (rel), status (pending/accepted/on_route/on_site/completed — lowercase!), description, signature (file — **now wired up and working**), email_sent, calendar_date (plain YYYY-MM-DD string), on_site_started_at, on_site_ended_at, job_type (site_visit/maintenance/call_out), job_number, is_recurring, recurrence_interval, job_card_pdf.
- **job_number**: auto GS_XXXX via pb_hooks/job_number.pb.js using `onRecordCreate` + `e.next()`. Service MUST have `--hooksDir=/home/globaladmin/pocketbase_data/pb_hooks`.

### API rules (current)
- **clients** List/View: `@request.auth.id != "" && (@request.auth.is_head_office = true || @request.auth.is_sales = true || @request.auth.assigned_clients.id ?= id)` — outsourced techs still only see assigned Akeso sites (poaching protection).
- **jobs** List/View: `@request.auth.id != "" && (user = @request.auth.id || @request.auth.is_head_office = true || @request.auth.is_sales = true)`. Create/Update/Delete unchanged (own records only) — sales has no write access to jobs.
- **users** List/View: `id = @request.auth.id || @request.auth.is_head_office = true || @request.auth.is_sales = true`. (Needed so the portal can resolve `assigned_to` expands and populate the tech dropdown.)
- **sales_orders** List/View: head office, sales, or `assigned_to = @request.auth.id`. Create/Delete: head office or sales. Update: those plus the assigned tech (needed to attach signature + generated PDF).
- **Note**: expands fail *silently* (field just comes back empty) if the requesting user can't View the target collection. Symptom of a missing rule branch, not a code bug.
- **Application URL setting**: bare domain `https://jobtracking.globalsense.co.za` (NO /_/ suffix).
- **Backups**: daily auto (cron 0 0 * * *), keep 7. **Currently doing manual backups** while PetaSAN stabilises; S3/Veeam via PocketBase S3 integration pending (needs endpoint/bucket/keys from infra team).

## Sales feature (`/sales/`)
Replaces the sales user printing delivery notes / collection invoices by hand.

- **suppliers**: name, email (`;`-separated multiples), phone, address. Mirrors `clients`.
- **sales_orders**: order_number, type (delivery/collection), client (rel — deliveries), supplier (rel — collections), assigned_to (rel users), **scheduled_date** (note: originally created misspelled as `sheduled_date`, since renamed), reference, description, status (pending/assigned/completed), attached_pdf (SAGE upload), generated_pdf (our merged output), signature, signature_name, signed_at, email_sent, related_job (optional rel).
- **order_number**: pb_hooks/sales_order_number.pb.js — `DN_XXXX` for deliveries, `CN_XXXX` for collections, two independent sequences, same `onRecordCreate` + `e.next()` pattern.
- **Design decision — sales orders are NOT jobs.** They never touch job status/timer logic. A tech can sign for a delivery mid-job without disturbing a running timer. `related_job` optionally records the linkage.
- **Status is derived, not user-set**: completed stays completed (tech owns that transition); otherwise assigned tech → `assigned`, no tech → `pending`.
- **PDF**: `/pdf/generate-sales-pdf` — Puppeteer renders a jobcard-styled cover (title "Delivery – DN_0001" / "Collection – CN_0001", party details, reference, description, "Received in good order" + signature block), then **pdf-lib appends the uploaded SAGE PDF as pages 2+**. The existing `/generate-pdf` jobcard endpoint is untouched. The app orchestrates the merge (downloads attached_pdf, posts base64, uploads result) so the PDF service needs no PocketBase credentials.
- **Portal**: second entrypoint in the same repo — `lib/main_sales.dart`, built with `flutter build web --release --base-href /sales/ -t lib/main_sales.dart`. Login gated on `is_sales || is_head_office || superuser`, with a fallback to the `_superusers` auth endpoint. Uses **separate SharedPreferences keys** (`sales_pb_*`) because `/app/` and `/sales/` share a web origin and would otherwise clobber each other's sessions.
- Portal files: `lib/main_sales.dart`, `lib/providers/sales_auth_provider.dart`, `lib/providers/sales_provider.dart`, `lib/services/sales_order_service.dart`, `lib/services/supplier_service.dart`, `lib/models/{supplier,sales_order,week_job}.dart`, `lib/screens/sales/{sales_login_screen,sales_home_screen,sales_order_form_screen}.dart`.

## Flutter app
- baseUrl in lib/config/api_config.dart: `https://jobtracking.globalsense.co.za`.
- **CRITICAL release-build fix**: AndroidManifest.xml requires `<uses-permission android:name="android.permission.INTERNET"/>` and `ACCESS_NETWORK_STATE` — debug builds get them implicitly, release does NOT.
- Theme: `AppTheme.lightTheme`; primaryBlue = #233143.
- Dashboard tabs: selectedTabIndex is LOCAL state in _DashboardScreenState with setState + IndexedStack (NOT in JobProvider — provider notifyListeners + loadAll auto-redirect caused the web-app tab freeze bug).
- Job completion flow (complete_job_dialog.dart): PDF generated once → uploaded to PocketBase job_card_pdf via multipart PATCH → same bytes emailed if checked. Recurring jobs spawn next occurrence on completion.
- Other subsystems present in the repo: offline queue (`offline_queue_service`), PDF pipeline/queue (`pdf_pipeline_service`, `pdf_queue_service`), connectivity detection (web/stub split), foreground-task timer notifications, PWA install prompt.
- **In-app update checker — BUILT** (contrary to older notes): `lib/services/version_service.dart` + `lib/widgets/update_available_dialog.dart`, invoked from `splash_screen.dart` `_promptUpdateIfAvailable()` after landing on the first real screen. Android-only (no-op on web/iOS), reads `version.json`, compares dotted versions ignoring `+build`, supports `force_update` (non-dismissible dialog, blocks back button), opens the APK URL via `url_launcher` in the external browser.
  - ⚠️ **FIXED 24 Aug 2026**: `versionUrl` was `${baseUrl}/version.json`, which hits nginx's catch-all 404 — version.json lives under `/download/`. Because `checkForUpdate()` swallows all errors and returns null, the prompt failed **silently and indistinguishably from "up to date"** and had never fired for anyone. Now points at `/download/version.json`.
  - **Consequence**: every tech on 1.2.0 has the broken URL baked into their APK and will never be prompted. The next APK must be distributed manually (send them the `/download/` link); auto-prompting works from then on.
  - To test the prompt, temporarily raise `latest_version` in version.json above the installed version.
  - **Release process**: bump `version:` in pubspec.yaml, build APK, publish APK + updated version.json to `/download/`, so techs get prompted on next launch. Current version: **1.2.0+2**.
- Web app: `flutter build web --release --base-href /app/` → /var/www/jobcard. iOS users use it as PWA (service worker caching means updates lag on iOS).
- **file_picker pinned to ^11.x** — v10.3.9+ removed `FilePicker.platform` (use `FilePicker.pickFiles(...)` directly), and **v12 changes the return type again** to `List<PlatformFile>` instead of `FilePickerResult?`. Don't jump majors casually.

## Email
- Table-based HTML needed for Outlook desktop (Word renderer strips div CSS) — deferred.
- Subject: "Job Completed - {JobType} {JobNumber}". Header is plain #233143 banner.
- Multi-recipient: emails split on `;`.

## Metabase
- Login admin: matthew. Site URL setting: `https://jobtracking.globalsense.co.za/analytics`.
- Users can't be deleted, only deactivated; emails can't be reused (use +aliases for testing). **SMTP invites RESOLVED** (previously unconfirmed).
- **Column type fix required**: jobs.on_site_ended_at cast to ISO8601→Datetime in Table Metadata (SQLite stores text) or date Field Filters won't work.
- Date filters: Field Filter mapped to Jobs→On Site Ended At with alias `j.on_site_ended_at`; wrapped `[[AND {{date_filter}}]]`.
- 7 queries (all +2h SAST offset, printf HH:MM:SS durations, `on_site_ended_at > on_site_started_at` guard): _Jobs Completed Over Time, _Time Spent on Site, _Jobs Per Technician, _Jobs Per Client, _Jobs Per Group, _Jobs Per Branch, _Jobs Per Group & Branch (UNION ALL subtotal+detail with sort_order).
- Client grouping: `LIKE 'Akeso%'` → 'Akeso Clinics'; `LIKE 'Altas Plant Hire -%'` → 'Altas Plant Hire'.

## Incidents & lessons
- **Aug 2026 ext4 corruption**: PetaSAN node overload → VM migration corrupted sda2. PocketBase crash-looped; fixed via dracut emergency shell `fsck -y /dev/sda2` (twice). data.db survived. Metabase H2 db corrupted → dashboards rebuilt. LESSON: backups must leave the VM; ask hypervisor team about virtio disk cache mode (want none/writethrough).
- npm pacman conflict: `sudo npm install -g` conflicts with the pacman npm package. Fix: `sudo pacman -S --overwrite '/usr/lib/node_modules/npm/*' npm`. Prefer pacman-installed node/npm — GUI apps (e.g. Claude Desktop MCP) only see the system PATH `/usr/local/bin:/usr/bin:/bin`, so nvm-managed node is invisible to them.
- PocketBase "invalid login credentials" via curl = trying superuser creds on the users collection endpoint.
- **pb_hooks syntax errors fail silently at the app level** — check `journalctl -u pocketbase` for `failed to execute <file>: SyntaxError` right after restart. A mismatched brace before `catch` produces "Unexpected token c".
- Shell `Argument list too long` when passing base64 PDFs to `jq --arg` — use `--rawfile` from a temp file instead. Only a test-harness issue; the app posts JSON from memory.

## Server scripts (in ~ on server; regenerate from chat if lost)
- **regenerate_jobcard.sh <GS_XXXX>** — pulls job from PB, generates PDF, uploads to job_card_pdf.
- **resend_email.sh <GS_XXXX> [override_email]** — downloads STORED PDF, emails it, sets email_sent=true.

## Health check quick reference
```
sudo systemctl status pocketbase pdf-service email-service metabase nginx
curl http://127.0.0.1:8090/api/health   # PB
curl http://127.0.0.1:3001/health       # PDF
curl http://127.0.0.1:3002/health       # Email
curl -k -I https://127.0.0.1/download/version.json  # nginx HTTPS (NOT port 80!)
journalctl -fu <service>
sqlite3 ~/pocketbase_data/data.db "PRAGMA integrity_check;"
```
After npm module errors on Node services: `cd ~/<service> && npm install && sudo systemctl restart <service>`.

## Deployment

**Web builds** (both output to `build/web`, so the sales build overwrites the app build and vice versa — copy to the server immediately after building, never assume `build/web` holds what you expect):

```bash
flutter build web --release --base-href /app/                           # main app -> /var/www/jobcard
flutter build web --release --base-href /sales/ -t lib/main_sales.dart   # sales    -> /var/www/jobcard-sales
```

**Getting the build to the server:**
- **At the office**: `ssh globaladmin@10.0.9.40`, then scp/rsync the build across.
- **From home**: SSH to the server does NOT work over the VPN. Workaround: zip `build/web`, upload to Google Drive, download + extract on the server, copy into place.

nginx has no explicit `user` directive — it runs as the Arch default (`http`).

**nginx blocks** (in `/etc/nginx/sites-enabled/jobcard_tracker.conf`):
```nginx
location /app/   { alias /var/www/jobcard/;       try_files $uri $uri/ /app/index.html; }
location /sales/ { alias /var/www/jobcard-sales/; try_files $uri $uri/ /sales/index.html; }
```
Verify with `sudo nginx -t && sudo systemctl reload nginx` then `curl -k -I https://127.0.0.1/sales/`.

## Outstanding TODOs
1. **Sales step 4** — app side: surface sales orders on the Active Jobs tab for the assigned tech, detail sheet, signature capture, call `/pdf/generate-sales-pdf`, upload to `generated_pdf`, optional email.
2. Investigate reported issue with the resend-email-on-web feature.
3. Push the next APK manually — see the update-checker note above.
4. Enable PocketBase S3 backups once PetaSAN is stable (need endpoint/bucket/keys).
5. ~~Resend-email button in app for completed jobs~~ — **done on web** (shipped in 1.2.0); see TODO 2 re: reported issue.
6. **Timestamp guard in updateJobStatus** (only set on_site_started_at if null) — still outstanding; a tech re-selecting `on_site` on a finished job corrupts durations (GS Richards Bay incident).
7. Fix corrupted GS Richards Bay job record timestamps manually if not done.
8. Outlook desktop email rendering (table-based HTML) — deferred.
9. MFA/OTP for app login — deferred (PB MFA is email-OTP, needs PB SMTP config).
10. `test/widget_test.dart` references a non-existent `MyApp` — the one hard error in `flutter analyze`. Harmless for builds, breaks `flutter test`.

## Resolved (previously open)
- ✅ Signature storage wired to jobs.signature.
- ✅ Metabase SMTP invites.
- ✅ In-app update checker built (pending the URL verification above).
