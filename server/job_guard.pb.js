/// <reference path="../pb_data/types.d.ts" />

console.log("job_guard hook loaded");

// Protects on_site_started_at from being overwritten once it has a value.
//
// WHY: re-selecting "on site" on a job that already has an arrival time
// silently resets the duration. It has happened in the field (GS Richards
// Bay) and the corrupted value then flows into the job card PDF and the
// Metabase duration charts, where nobody notices it's wrong.
//
// The app guards this too, but this hook also covers the admin UI, the
// recovery scripts, and any older APK still in the wild.
//
// Deliberately does NOT block status changes — an admin sometimes needs to
// correct a status by hand (e.g. putting GS_0238 back to completed).

onRecordUpdate((e) => {
    try {
        const original = e.record.original();

        // Log every status transition with its before/after. PocketBase's
        // own request log lives in auxiliary.db and does not survive a
        // rebuild, and nginx doesn't log bodies — so when GS_0238 came back
        // as `pending` after completion there was no way to tell what wrote
        // it. This line makes the next occurrence self-evident.
        if (original) {
            const before = original.getString("status");
            const after = e.record.getString("status");
            if (before !== after) {
                console.log("job_guard: status " + before + " -> " + after +
                    " on " + e.record.getString("job_number") +
                    (before === "completed" ? "  *** BACKWARDS FROM COMPLETED ***" : ""));
            }
        }

        const incoming = e.record.get("on_site_started_at");

        // Only interested in updates that would set/replace the value.
        if (incoming) {
            const existing = original ? original.get("on_site_started_at") : null;

            if (existing && String(existing) !== String(incoming)) {
                console.log("job_guard: kept original on_site_started_at on " +
                    e.record.getString("job_number") +
                    " (tried to change " + existing + " -> " + incoming + ")");
                e.record.set("on_site_started_at", existing);
            }
        }
    } catch (err) {
        // Never let this block a legitimate update.
        console.log("job_guard: error " + err);
    }

    return e.next();
}, "jobs");
