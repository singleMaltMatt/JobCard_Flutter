# Feature: Alternative Email Address on Job Completion

## Overview

When a technician checks **Send Email** on the Complete Job screen, an additional
option should appear allowing them to send the job card to a second recipient on
that specific job — useful when the usual contact is not on site that day.

## Approach

The email service already accepts semi-colon-separated recipients in the `to`
field, so the cleanest solution is to concatenate the alternative address onto
the primary client email in a **single API call** rather than making two separate
requests. This keeps the implementation simple, requires no backend changes, and
means both recipients receive the same email thread and attachment atomically.

---

## Files to Change

| File | What changes |
|---|---|
| `lib/widgets/complete_job_dialog.dart` | State variables, `dispose`, UI, email payload |

No other files need to change.

---

## 1 — State Variables

Add two new fields to `_CompleteJobDialogState` alongside the existing ones:

```dart
// existing
bool _sendEmail = false;

// add these two
bool _sendToAlt  = false;                              // alt-address checkbox
final _altEmailController = TextEditingController();   // alt-address text field
```

---

## 2 — dispose()

Add the new controller to `dispose()`:

```dart
@override
void dispose() {
  _descriptionController.dispose();
  _signatureNameController.dispose();
  _altEmailController.dispose();   // ← add this
  super.dispose();
}
```

---

## 3 — UI (build method)

Locate the existing `CheckboxListTile` for **Send Email** inside the
`SingleChildScrollView` column (around line 611 in the current file):

```dart
CheckboxListTile(
  title: const Text('Send Email'),
  subtitle: Text('Send job card to ${widget.job.clientName}'),
  value: _sendEmail,
  onChanged: (v) => setState(() => _sendEmail = v ?? false),
  controlAffinity: ListTileControlAffinity.trailing,
  activeColor: AppTheme.primaryBlue,
),
const SizedBox(height: 24),
```

Replace that block with:

```dart
CheckboxListTile(
  title: const Text('Send Email'),
  subtitle: Text('Send job card to ${widget.job.clientName}'),
  value: _sendEmail,
  onChanged: (v) => setState(() {
    _sendEmail = v ?? false;
    if (!_sendEmail) {
      _sendToAlt = false;
      _altEmailController.clear();
    }
  }),
  controlAffinity: ListTileControlAffinity.trailing,
  activeColor: AppTheme.primaryBlue,
),

// ── Alternative address (only visible when Send Email is checked) ──
if (_sendEmail) ...[
  CheckboxListTile(
    title: const Text('Send to alternative address?'),
    subtitle: const Text('Useful when the usual contact is off site'),
    value: _sendToAlt,
    onChanged: (v) => setState(() {
      _sendToAlt = v ?? false;
      if (!_sendToAlt) _altEmailController.clear();
    }),
    controlAffinity: ListTileControlAffinity.trailing,
    activeColor: AppTheme.primaryBlue,
  ),
  if (_sendToAlt) ...[
    const SizedBox(height: 4),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _altEmailController,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: 'Alternative email address',
          hintText: 'someone@example.com',
          prefixIcon: const Icon(Icons.alternate_email),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        // Inline validation — shown on form submit, not on every keystroke
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Enter an email address';
          if (!v.contains('@') || !v.contains('.')) {
            return 'Enter a valid email address';
          }
          return null;
        },
      ),
    ),
    const SizedBox(height: 8),
  ],
],
const SizedBox(height: 24),
```

> **Note:** The outer `if (_sendEmail)` block collapses completely when the
> checkbox is unchecked, and the alt-email field collapses when its own checkbox
> is unchecked. No animation package is needed — Flutter's conditional rendering
> handles the show/hide cleanly.

---

## 4 — Validation in _completeJob()

Add a guard before the arrival-time check so a partially filled alt-email field
doesn't slip through:

```dart
Future<void> _completeJob() async {
  if (_descriptionController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar( ... );
    return;
  }

  // ── NEW: validate alt email if the field is visible ──────────────────
  if (_sendToAlt && _altEmailController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please enter the alternative email address'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }
  if (_sendToAlt) {
    final alt = _altEmailController.text.trim();
    if (!alt.contains('@') || !alt.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alternative email address is not valid'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
  }
  // ─────────────────────────────────────────────────────────────────────

  _departedTime ??= DateTime.now();
  // ... rest of the method unchanged
}
```

---

## 5 — Email payload (_generatePdfStoreAndEmail)

Locate Step 3 inside `_generatePdfStoreAndEmail`. The only line that needs to
change is the `'to'` field:

**Before:**
```dart
'to': widget.job.clientEmail,
```

**After:**
```dart
'to': (_sendToAlt && _altEmailController.text.trim().isNotEmpty)
    ? '${widget.job.clientEmail}; ${_altEmailController.text.trim()}'
    : widget.job.clientEmail,
```

The email service splits on `;` and dispatches to each address. Both recipients
receive the same subject, body, and PDF attachment in a single call.

---

## 6 — Confirmation Summary (_showConfirmationSummary)

Update the `_optionRow` call for **Email** so the summary card reflects the
alternative address when provided:

**Before:**
```dart
_optionRow(
  Icons.email_outlined,
  'Email',
  _sendEmail
      ? 'Will be sent to ${widget.job.clientName}'
      : 'Not sending',
  _sendEmail,
),
```

**After:**
```dart
_optionRow(
  Icons.email_outlined,
  'Email',
  _sendEmail
      ? (_sendToAlt && _altEmailController.text.trim().isNotEmpty
          ? 'Will be sent to ${widget.job.clientName} + ${_altEmailController.text.trim()}'
          : 'Will be sent to ${widget.job.clientName}')
      : 'Not sending',
  _sendEmail,
),
```

---

## Behaviour Summary

| User action | Result |
|---|---|
| Unchecks **Send Email** | Both alt-address checkbox and text field collapse; `_sendToAlt` resets to false |
| Checks **Send to alternative address?** | Text field appears below |
| Unchecks alt-address checkbox | Text field collapses and controller is cleared |
| Taps **Complete Job** with blank alt field | Snackbar: "Please enter the alternative email address" |
| Taps **Complete Job** with invalid alt email | Snackbar: "Alternative email address is not valid" |
| Confirmation summary | Shows `+ alt@email.com` next to client name when alt is provided |
| Email sent | Single API call with `to: "client@x.com; alt@y.com"` |
