/// <reference path="../pb_data/types.d.ts" />

// Sends the job card email server-side once the PDF is attached.
//
// WHY: the email used to be the last step of a client-side chain that ran
// after the completion dialog closed. If the phone slept or the tab was
// suspended, the request died mid-flight with no error and no retry — the
// app's queue only catches calls that *return* a failure. Triggering from
// here means the send happens on the box regardless of what the device does.
//
// Fires only when: status is completed, the tech ticked "Send Email"
// (email_requested), the PDF is attached, and we haven't already sent.
// Setting email_sent re-triggers this hook, and the guard stops it there.

onRecordAfterUpdateSuccess((e) => {
    try {
        const rec = e.record;

        if (rec.getString("status") !== "completed") return e.next();
        if (!rec.getBool("email_requested")) return e.next();
        if (rec.getBool("email_sent")) return e.next();

        const pdfName = rec.getString("job_card_pdf");
        if (!pdfName) return e.next();

        // Recipient lives on the related client record.
        const clientId = rec.getString("client");
        if (!clientId) {
            console.log("job_email: no client on " + rec.getString("job_number"));
            return e.next();
        }

        let clientRec;
        try {
            clientRec = e.app.findRecordById("clients", clientId);
        } catch (err) {
            console.log("job_email: client " + clientId + " not found");
            return e.next();
        }

        const to = clientRec.getString("email");
        if (!to) {
            console.log("job_email: client has no email, skipping " + rec.getString("job_number"));
            return e.next();
        }

        // Local URL — the email service runs on the same box, so this
        // avoids a round trip through nginx.
        const pdfUrl = "http://127.0.0.1:8090/api/files/jobs/" + rec.id + "/" + pdfName;

        const res = $http.send({
            url: "http://127.0.0.1:3002/send-job-email",
            method: "POST",
            headers: { "content-type": "application/json" },
            timeout: 120,
            body: JSON.stringify({
                to: to,
                subject: "Job Completed - " + rec.getString("job_number"),
                clientName: clientRec.getString("name"),
                clientAddress: clientRec.getString("address"),
                jobDate: rec.getString("calendar_date"),
                description: rec.getString("description"),
                jobNumber: rec.getString("job_number"),
                pdfUrl: pdfUrl,
            }),
        });

        if (res.statusCode === 200) {
            rec.set("email_sent", true);
            e.app.save(rec);
            console.log("job_email: sent " + rec.getString("job_number") + " -> " + to);
        } else {
            console.log("job_email: FAILED " + rec.getString("job_number") +
                " status=" + res.statusCode + " body=" + res.raw);
        }
    } catch (err) {
        // Never let a mail problem block the record update.
        console.log("job_email: error " + err);
    }

    return e.next();
}, "jobs");
