# FrankGeary

FrankGeary is a focused fork of the Geary email client. It keeps the familiar
Geary conversation-based mail experience while carrying project-specific fixes
and experiments in this repository.

## FrankGeary vs upstream Geary

Upstream Geary remains the canonical GNOME mail client project. FrankGeary is a
downstream fork intended for targeted improvements, packaging experiments, and
validation work before changes are considered for rebasing or upstreaming.

Because this codebase still follows older Geary internals, some runtime strings,
desktop integration, data paths, and application identity surfaces may still say
`Geary`. This is intentional for now: changing runtime identity can affect user
profiles, settings, desktop files, schemas, translations, and migration safety.

## Features

- IMAP email client for GNOME-style desktops.
- Conversation-oriented message reading.
- HTML and plain-text composer.
- Full-text and keyword search.
- Desktop notifications.
- Wider composer autocomplete that includes contacts seen in CC/BCC contexts
  while filtering common no-reply addresses.
- Message image context menu support: right-click supported inline/data images
  and choose **Copy Image** to place the image on the clipboard.
- Manual folder sidebar visibility toggle with `Ctrl+Shift+M`.

## Screenshots

### Wider recipient autocomplete

FrankGeary keeps Geary's native composer completion UI, but widens the contact
visibility threshold so more legitimate contacts appear in recipient fields.

![FrankGeary recipient autocomplete popup](docs/images/autocomplete-popup.png)

### Folder sidebar toggle

The folder/account sidebar can be hidden manually with `Ctrl+Shift+M`, giving
more room to the message list and reading pane on narrow windows.

<table>
<tr>
<td width="50%" align="center">

**Sidebar shown**

<img src="docs/images/sidebar-shown.png" alt="FrankGeary with the folder sidebar shown" width="100%">

</td>
<td width="50%" align="center">

**Sidebar hidden**

<img src="docs/images/sidebar-hidden.png" alt="FrankGeary with the folder sidebar hidden" width="100%">

</td>
</tr>
</table>

### Copy Image from message images

The old autocomplete module also exposed a **Copy Image** action. FrankGeary now
implements that behavior natively in the message viewer: right-click a supported
inline or data-backed image in a message and choose **Copy Image** to copy the
decoded image to the desktop clipboard.

> Screenshots come from the earlier standalone module prototypes. The behavior is
> now implemented natively in this fork rather than injected through GTK modules.

## Upstream rebase policy

FrankGeary should minimize divergence where practical. Native feature work should
be isolated so the project can periodically rebase onto newer upstream Geary or
extract changes for upstream submission. Packaging, documentation, and CI changes
should avoid touching native build or source files unless a dedicated feature
lane explicitly owns that work.

## AUR packages

Packaging scaffolding lives under `packaging/aur/`:

- `frank-geary`: source package built from a GitHub Release/source archive.
- `frank-geary-bin`: binary package intended only for stable GitHub Release
  assets, not GitHub Actions workflow artifacts.

The `frank-geary` source recipe is published from stable GitHub Release source
archives. The `frank-geary-bin` recipe uses stable Release `.tar.zst` install-tree
assets, not workflow artifacts, and bundles the legacy ABI libraries built from a
pinned Arch Linux Archive snapshot for WebKitGTK 2.4 / `webkitgtk-3.0`, GMime
2.6, and Enchant 1.x.
