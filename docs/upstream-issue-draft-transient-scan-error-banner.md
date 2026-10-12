# Draft for upstream issue at https://gitlab.gnome.org/GNOME/geary/-/issues/new

Suggested title:

> Transient ConversationMonitor scan errors are reported as "Geary encountered a problem checking mail" with an undismissable info bar

---

**Bug Summary**

When the conversation monitor loads thread ancestors from another folder (e.g.
`[Gmail]/Trash`) and that listing fails with a transient engine error, the
error is surfaced as a `ServiceProblemReport` — the orange *"Account problem:
Geary encountered a problem checking mail for &lt;account&gt;"* info bar — even
though the IMAP connection is healthy and mail keeps syncing normally.

The typical trigger on Gmail is a race with server-side message removal
(Gmail auto-expunge, or another client emptying Trash): the requested
messages disappear between the UID discovery and the FETCH, Gmail's responses
for those UIDs then contain only UID+FLAGS — no `BODY[HEADER.FIELDS …]`
section and no `INTERNALDATE`/`RFC822.SIZE` — so every message in the range is
dropped with:

```
[wrn] Geary: [account] [imap] […, Imap.Folder(>[Gmail]>Trash), …] GearyImapFolderSession: No header specifier "body.peek[header.fields (in-reply-to message-id references)]" found in response:
[wrn] Geary: [account] [imap] […] GearyImapFolderSession: GearyImapDBEmailIdentifier(-1,504461) missing=PROPERTIES fetched=[242] uid=504461 flags=\Seen
```

(repeated for each UID in the range), and the subsequent listing failure
bubbles up to the info bar.

Two aspects make this worse than a cosmetic bug:

1. **The report misdiagnoses the problem.** `MainWindow.on_scan_error()` wraps
   *every* `ConversationMonitor.scan_error` into a
   `Geary.ServiceProblemReport` for the incoming service, so a local/engine
   consistency hiccup (`EngineError.INCOMPLETE_MESSAGE` family) is presented
   to the user as a connection problem. The same catch-all pattern exists in
   `ImapEngine.AccountSynchronizer.FolderSync.process()` and
   `ImapEngine.GenericAccount.on_operation_error()`.
2. **The info bar cannot be dismissed.** `Components.ProblemReportInfoBar`
   sets `show_close_button = (retry == null)`, and the IMAP variant always has
   a Retry button — so there is no close button at all. Since the underlying
   race recurs, Retry (which restarts the otherwise-healthy service) brings
   the banner right back, and users end up restarting Geary to get rid of it.

Notably, the engine already has the right classification pattern elsewhere:
`GenericAccount.enumerate_remote_folders_async()` deliberately ignores
everything except `IOError` and `ImapError` ("ignore everything but I/O and
IMAP errors"). Applying the same classification to the three report paths
above (only reporting `GLib.IOError` other than `CANCELLED`, `ImapError`, and
`GLib.TlsError`; logging everything else) would keep real connection/auth
problems visible while eliminating the false alarms. Independently, showing
the close button on `ProblemReportInfoBar` even when Retry is present would
let users dismiss the bar.

I am happy to submit an MR along those lines if the approach sounds
acceptable.


**Your installation**

 * Geary version:                    46.0 (self-built from current `main`; the affected code paths are unmodified upstream code)
 * Installation method:              Self-compiled (Meson release profile), Arch Linux package
 * Desktop environment:              Hyprland (wlroots Wayland)
 * Operating system and version:     Arch Linux (rolling, September 2026), GLib 2.88.3, GTK 3.24.52, WebKitGTK 2.52.6, GMime 3.2.15, libhandy 1.8.3
 * Email provider:                   Gmail (via GNOME Online Accounts, imap.gmail.com:993)


**Steps to reproduce**

 1. Configure a busy Gmail account that is also used from other clients
    (webmail, phone), so messages regularly get moved/deleted server-side.
 2. Use Geary normally with the Inbox selected; delete conversations or let
    another client move/expunge messages that belong to threads visible in
    the Inbox (messages in `[Gmail]/Trash` referenced by open conversations).
 3. Wait for the conversation monitor to load thread ancestors from
    `[Gmail]/Trash` (`external_load_by_sparse_id`) while those messages are
    being expunged server-side.

The race is timing-dependent, but on a multi-device Gmail account it triggers
several times per week.


**What happened?**

The orange *"Account problem — Geary encountered a problem checking mail for
&lt;account&gt;"* info bar appears and cannot be dismissed (no close button, only
Details and Retry). Mail continues to arrive normally behind it. The journal
shows no connection, TLS, or auth failure at that moment — only the
`No header specifier … found in response` / `missing=PROPERTIES` warnings
above, for a contiguous UID range in `[Gmail]/Trash`.


**What did you expect to happen?**

Transient engine/consistency errors during background scans should be logged
(or retried) without raising an account-level "problem checking mail" report;
the info bar should be reserved for actual connection, TLS, or authentication
failures — and should be dismissable in any case.


**Relevant logs and/or screenshots**

Journal excerpt (times local, account identifiers redacted). The full
sequence repeats the pair of lines below for ~20 consecutive UIDs
(504459–504478) within the same second, immediately after which the info bar
appeared:

```
13:21:46 geary[…]: *[wrn] Geary: [goa_account_…] [imap] [GearyImapClientSession(selected:[Gmail]/Trash selected RW, GearyImapClientConnection(000A/imap.gmail.com:993/up)), Imap.Folder(>[Gmail]>Trash), ro: false, …] GearyImapFolderSession: No header specifier "body.peek[header.fields (in-reply-to message-id references)]" found in response:
13:21:46 geary[…]: *[wrn] Geary: [goa_account_…] [imap] […] GearyImapFolderSession: GearyImapDBEmailIdentifier(-1,504461) missing=PROPERTIES fetched=[242] uid=504461 flags=\Seen
```

Note the absence of any ` - has …` lines after "found in response:" — the
response's body-data map was empty, i.e. the server returned no body sections
at all for these messages, consistent with them having been expunged
server-side mid-fetch. No `[err]`-level lines, TLS errors, or reconnections
were logged in the surrounding minutes; the routine IMAP keepalive continued
normally afterwards.

Related earlier reports that look like the same class of problem, where an
`INCOMPLETE_MESSAGE`-family error surfaces as an account problem: #523, #420,
#863, #1273, #848. !74 reduced problem-report noise in other paths but did
not cover these three.
