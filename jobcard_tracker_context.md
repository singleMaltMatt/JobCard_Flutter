# JobCard Tracker — Project Context & Reference

_Last updated: 28 Aug 2026 (sales feature complete and live; job emails moved server-side)_

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
| Email service (Node/nodemailer) | 3002 | /email/ | ~/email-service/server.js, SMTP mail.globalsense.co.za:2525, user relaygs@globalsense.co.za, from info@globalsense.co.za, secure:false, rejectUnauthorized:false; splits `to` on `;` for multi-recipient. **Password is plaintext in server.js — worth rotating + moving to an env var.** |
| Metabase | 3003 | /analytics/ | ~/metabase/metabase.jar, H2 db ~/metabase/metabase.db(.mv.db), MB_DB_FILE env var |
| Static | — | /static/, /download/, /app/, /sales/ | logo, APK distribution + version.json, Flutter web builds |

nginx config: /etc/nginx/sites-enabled/jobcard_tracker.conf (include line added to nginx.conf http block; mime.types had to be manually downloaded — Arch nginx package quirk).

### Service endpoints
**PDF service (3001)**
| Endpoint | Purpose |
|---|---|
| `/generate-pdf` | Job card. Production-critical — don't modify casually. |
| `/generate-sales-pdf` | Delivery/collection note; appends the SAGE PDF via pdf-lib |
| `/merge-pdfs` | Merges an array of base64 PDFs in order. Skips non-PDF entries rather than failing the batch. |

**Email service (3002)**
| Endpoint | Purpose |
|---|---|
| `/send-email` | Original client-side job email. **No longer called by the app** — kept for scripts/fallback. |
| `/send-job-email` | Called by the job_email hook. Takes `pdfUrl` and fetches the PDF itself (needs Node 18+ for global `fetch`). |
| `/send-sales-email` | Standalone delivery notes. Separate template — the job-card wording would be wrong. |

## PocketBase
- **Superuser**: admin@globalsense.co.za. App users are in `users` collection (cannot access admin panel). Superusers are a **separate auth collection** (`_superusers`) with their own endpoint — superuser creds fail against the `users` login endpoint.
- **Collections**: users, clients, jobs, **suppliers**, **sales_orders**.
- **jobs fields**: client (rel), user (rel), status (pending/accepted/on_route/on_site/completed — lowercase!), description, signature (file), **email_requested** (bool — the tech ticked "Send Email"), **email_sent** (bool — written ONLY by the job_email hook after the mailer confirms), calendar_date (plain YYYY-MM-DD string), on_site_started_at, on_site_ended_at, job_type (site_visit/maintenance/call_out/**cctv_access_control**), job_number, is_recurring, recurrence_interval, job_card_pdf.
- ⚠️ **File fields are MULTI**, so PocketBase stores a JSON array (`["gs_0238_x.pdf"]`). `getString("job_card_pdf")` returns **empty** in a hook — unwrap the array first. This silently broke the email hook for a day.
- **job_number**: auto GS_XXXX via pb_hooks/job_number.pb.js using `onRecordCreate` + `e.next()`. Service MUST have `--hooksDir=/home/globaladmin/pocketbase_data/pb_hooks`.

### pb_hooks
| File | Purpose |
|---|---|
| `job_number.pb.js` | GS_XXXX on create |
| `sales_order_number.pb.js` | DN_XXXX / CN_XXXX on create, two sequences |
| `job_email.pb.js` | **Sends the job card email server-side** |

All three log a line on load — `journalctl -u pocketbase` after a restart should show three "hook loaded" lines. A missing one means that hook isn't registered.

**job_email.pb.js** — `onRecordAfterUpdateSuccess` on `jobs`. Fires when status=completed, `email_requested`, `!email_sent`, and a PDF is attached; POSTs to `/send-job-email` with a local file URL; sets `email_sent=true` only on HTTP 200 (which re-triggers the hook, stopped by the `email_sent` guard). Every hook logs a line — `journalctl -u pocketbase | grep job_email` is the diagnostic. Copy in the repo at `server/job_email.pb.js`.

**Known wrinkle**: the guard is a read-then-write with no atomicity, so two near-simultaneous updates can both pass it. Seen once (two "sent" log lines, one actual email). Hardening would be to set `email_sent=true` *before* sending and reset on failure.

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
- **Design decision — sales orders are NOT jobs.** They never touch job status/timer logic. A tech can sign for a delivery mid-job without disturbing a running timer: the sheet writes only to `sales_orders`, and `TechSalesProvider` is separate from `JobProvider`.
- **Two signatures, deliberately.** A delivery attached to a job is still signed separately by the client, on its own document. The job-card signature is never stamped onto a page the signer didn't see.
- **Attached vs standalone** (`related_job`):
  - *Standalone* — signed in the app, optional email to the client immediately via `/send-sales-email`.
  - *Attached* — no email at signing. At job completion the signed note's `generated_pdf` is appended to the job card via `/merge-pdfs`, and the merged file goes to `job_card_pdf`, which triggers the normal job email. Client receives ONE PDF: job card, delivery note, SAGE pages.
  - Kelly sets `related_job` in the portal: a delivery with a client + date offers a dropdown of that client's non-completed jobs within ±3 days.
  - At completion the app warns (does not block) if an attached order is still unsigned — an unsigned note never gets merged.
- **Status is derived, not user-set**: completed stays completed (tech owns that transition); otherwise assigned tech → `assigned`, no tech → `pending`.
- **PDF**: `/pdf/generate-sales-pdf` — Puppeteer renders a jobcard-styled cover (title "Delivery – DN_0001" / "Collection – CN_0001", party details, reference, description, "Received in good order" + signature block), then **pdf-lib appends the uploaded SAGE PDF as pages 2+**. The existing `/generate-pdf` jobcard endpoint is untouched. The app orchestrates the merge (downloads attached_pdf, posts base64, uploads result) so the PDF service needs no PocketBase credentials.
- **Portal**: second entrypoint in the same repo — `lib/main_sales.dart`, built with `flutter build web --release --base-href /sales/ -t lib/main_sales.dart`. Login gated on `is_sales || is_head_office || superuser`, with a fallback to the `_superusers` auth endpoint. Uses **separate SharedPreferences keys** (`sales_pb_*`) because `/app/` and `/sales/` share a web origin and would otherwise clobber each other's sessions.
- Portal files: `lib/main_sales.dart`, `lib/providers/sales_auth_provider.dart`, `lib/providers/sales_provider.dart`, `lib/services/sales_order_service.dart`, `lib/services/supplier_service.dart`, `lib/models/{supplier,sales_order,week_job}.dart`, `lib/screens/sales/{sales_login_screen,sales_home_screen,sales_order_form_screen}.dart`.

## Flutter app
- baseUrl in lib/config/api_config.dart: `https://jobtracking.globalsense.co.za`.
- **CRITICAL release-build fix**: AndroidManifest.xml requires `<uses-permission android:name="android.permission.INTERNET"/>` and `ACCESS_NETWORK_STATE` — debug builds get them implicitly, release does NOT.
- Theme: `AppTheme.lightTheme`; primaryBlue = #233143.
- Dashboard tabs: selectedTabIndex is LOCAL state in _DashboardScreenState with setState + IndexedStack (NOT in JobProvider — provider notifyListeners + loadAll auto-redirect caused the web-app tab freeze bug).
- Job completion flow (complete_job_dialog.dart): the dialog **stays open and awaits the whole pipeline** (generate → merge any signed delivery notes → upload → signature), showing progress labels, then pops. Recurring jobs spawn next occurrence on completion.
  - ⚠️ **This is the fix for the 24 Aug email incident.** The pipeline used to run fire-and-forget *after* `Navigator.pop()`; the tech saw "completed!", pocketed the phone, and the suspended tab killed the in-flight request mid-chain. Three jobs stopped at three different points on one day. The retry queue never fired because nothing ever *returned* a failure — the code simply stopped executing. **Never put a critical chain after a pop.**
  - The email itself is no longer sent by the client at all — see the job_email hook.
- **Resend** (`resendJobEmail`): reuses the stored PDF untouched — it's the document the client signed — and just flips `email_requested`/`email_sent` to trigger the hook. It regenerates **only** when `job_card_pdf` is missing. That's the deliberate correction path: delete the PDF on the record, tell the tech to resend, and it rebuilds from stored data + stored signature.
- **PDF dates**: `appointmentDetails` is the *completion* date, date-only. It used to come from `calendar_date`, so a job scheduled for the 27th but completed on the 1st showed the 27th on a document signed on the 1st. `completedDate` (with time) is still used for the signature block.
- Other subsystems present in the repo: offline queue (`offline_queue_service`), PDF pipeline/queue (`pdf_pipeline_service`, `pdf_queue_service`), connectivity detection (web/stub split), foreground-task timer notifications, PWA install prompt.
- **In-app update checker — BUILT** (contrary to older notes): `lib/services/version_service.dart` + `lib/widgets/update_available_dialog.dart`, invoked from `splash_screen.dart` `_promptUpdateIfAvailable()` after landing on the first real screen. Android-only (no-op on web/iOS), reads `version.json`, compares dotted versions ignoring `+build`, supports `force_update` (non-dismissible dialog, blocks back button), opens the APK URL via `url_launcher` in the external browser.
  - ⚠️ **FIXED 24 Aug 2026**: `versionUrl` was `${baseUrl}/version.json`, which hits nginx's catch-all 404 — version.json lives under `/download/`. Because `checkForUpdate()` swallows all errors and returns null, the prompt failed **silently and indistinguishably from "up to date"** and had never fired for anyone. Now points at `/download/version.json`.
  - **Consequence**: every tech on 1.2.0 has the broken URL baked into their APK and will never be prompted. The next APK must be distributed manually (send them the `/download/` link); auto-prompting works from then on.
  - To test the prompt, temporarily raise `latest_version` in version.json above the installed version.
  - **Release process**: bump `version:` in pubspec.yaml, build APK, publish APK + updated version.json to `/download/`, so techs get prompted on next launch. Current version: **1.3.0+3** (sales feature + server-side email).
- Web app: `flutter build web --release --base-href /app/` → /var/www/jobcard. iOS users use it as PWA (service worker caching means updates lag on iOS).
- **file_picker pinned to ^10.3.10** — 11.x fails the Android build (its gradle config doesn't apply `kotlin-android`, so `FilePickerPlugin` never compiles: "cannot find symbol" in GeneratedPluginRegistrant). 10.x uses `FilePicker.platform.pickFiles(...)`; 11.x switched to a static `FilePicker.pickFiles(...)`; 12.x changes the return type to `List<PlatformFile>`. The constraint has been reverted by accident twice — there's a comment in pubspec.yaml now.
- **Release builds are signed with the DEBUG key** (`signingConfig = signingConfigs.getByName("debug")`), which is per-machine. Builds from CachyOS and the work laptop have different signatures, so techs must uninstall/reinstall on every release. A proper release keystore would end that — outstanding.

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
- **24 Aug 2026 — job card emails silently not sending.** Four completions, one email. nginx access logs were the arbiter that split "never called" from "called and failed": one POST to `/email/send-email` all day, so the break was client-side. Root cause: the PDF/email chain ran fire-and-forget after the completion dialog popped (see Flutter section). LESSONS: (1) `email_sent` was written from the checkbox, not the mailer's response, so the flag lied and hid the problem for an unknown period — **derive status flags from results, never from intent**; (2) a retry queue that only catches *returned* failures cannot catch terminated execution; (3) a service that logs nothing (17 days uptime, one startup line) makes the journal useless as evidence.
- **28 Aug 2026 — the email hook fired for nobody.** `getString("job_card_pdf")` returns empty on a MULTI file field, so the hook exited at that guard on every update, silently. Diagnosed by adding a load-time log plus a line dumping every guard value. LESSON: **a hook that logs only on success is indistinguishable from a hook that never loaded.**
- **Status reverting to `pending`** on a completed job (GS_0238) removed it from the tech's Completed list ("my job card disappeared") and blocked its email at the hook's first guard. Same root cause as the outstanding timestamp-guard TODO.
- **Aug 2026 ext4 corruption**: PetaSAN node overload → VM migration corrupted sda2. PocketBase crash-looped; fixed via dracut emergency shell `fsck -y /dev/sda2` (twice). data.db survived. Metabase H2 db corrupted → dashboards rebuilt. LESSON: backups must leave the VM; ask hypervisor team about virtio disk cache mode (want none/writethrough).
- npm pacman conflict: `sudo npm install -g` conflicts with the pacman npm package. Fix: `sudo pacman -S --overwrite '/usr/lib/node_modules/npm/*' npm`. Prefer pacman-installed node/npm — GUI apps (e.g. Claude Desktop MCP) only see the system PATH `/usr/local/bin:/usr/bin:/bin`, so nvm-managed node is invisible to them.
- PocketBase "invalid login credentials" via curl = trying superuser creds on the users collection endpoint.
- **PocketBase list endpoints return 200 with an empty `items` array when a List rule excludes the caller**, not 403. A 200 therefore proves nothing on its own — always check the body. `auth: N/A` requests returning 200 in the logs are rules working, not a leak. (This was briefly misdiagnosed as an unauthenticated-read hole on 28 Aug.)
- **NAT hairpinning is not supported**, so `curl https://jobtracking.globalsense.co.za/...` **from the server** returns `000` (no connection). Test from a client machine, or hit `http://127.0.0.1:8090` directly to bypass nginx.
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
- `ssh globaladmin@10.0.9.40` works from the office **and from home over the VPN** (the server IP was allowed on the MikroTik, 30 Aug 2026). scp/rsync the build across.
- Historical note: SSH used to fail over the VPN, and the workaround was zipping `build/web`, uploading to Google Drive and extracting on the server. No longer needed.

nginx has no explicit `user` directive — it runs as the Arch default (`http`).

**nginx blocks** (in `/etc/nginx/sites-enabled/jobcard_tracker.conf`):
```nginx
location /app/   { alias /var/www/jobcard/;       try_files $uri $uri/ /app/index.html; }
location /sales/ { alias /var/www/jobcard-sales/; try_files $uri $uri/ /sales/index.html; }
```
Verify with `sudo nginx -t && sudo systemctl reload nginx` then `curl -k -I https://127.0.0.1/sales/`.

## Outstanding TODOs
1. **`updateJobStatus` timestamp guard** — only set `on_site_started_at` if null, and don't let a completed job silently move backwards. Has now caused both corrupted durations (GS Richards Bay) and a blocked email (GS_0238).
2. Fix corrupted GS Richards Bay job record timestamps manually if not done.
3. **Release keystore** — see the debug-signing note above.
4. Harden the job_email double-fire guard (set `email_sent` before sending).
5. Check `send_jobcard.sh` doesn't now double-trigger the hook — re-uploading a PDF to a job with `email_requested=1, email_sent=0` will fire it.
6. Enable PocketBase S3 backups once PetaSAN is stable (need endpoint/bucket/keys). Manual backups until then.
7. Broken nginx `alias` for `/static/` — points at `/home/globaladmin/static/`, which nginx (user `http`) can't traverse; every request is `13: Permission denied`. Harmless (only bots hit it) but dead.
8. Outlook desktop email rendering (table-based HTML) — deferred.
9. MFA/OTP for app login — deferred (PB MFA is email-OTP, needs PB SMTP config).

## Resolved (previously open)
- ✅ Signature storage wired to jobs.signature.
- ✅ Metabase SMTP invites.
- ✅ In-app update checker built; `versionUrl` path fixed.
- ✅ Sales portal — all steps, deployed and live at `/sales/`.
- ✅ Sales orders on the tech's Active Jobs tab, signing, PDF merge.
- ✅ Delivery notes merged into the job card at completion (verified: 3-page output — job card, delivery note, SAGE).
- ✅ Job card emails moved server-side (job_email hook).
- ✅ `email_sent` now reflects reality.
- ✅ CCTV / Access Control job type.
- ✅ Appointment date on the PDF uses the completion date.
- ✅ `flutter analyze` clean; `test/widget_test.dart` replaced with real model tests.
- ✅ `auxiliary.db` corruption cleared 30 Aug 2026 (moved aside, PocketBase recreated it; integrity_check ok). Old file kept as `auxiliary.db.corrupt-2026-08-30` — safe to delete once you're happy.
- ✅ SSH from home over the VPN (MikroTik rule added 30 Aug 2026).
