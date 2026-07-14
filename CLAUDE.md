# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

FrankGeary is a lightly-patched fork of the GNOME Geary email client (Vala, GTK 3, Meson). It tracks upstream Geary (`https://gitlab.gnome.org/GNOME/geary.git`, branch `main`) closely; fork-specific changes are deliberately small and kept separable. `origin/master` is periodically rebased onto `upstream/main` — see `docs/upstream-updates.md` for the exact update flow (always `git push --force-with-lease`, never plain `--force`).

## Build and test commands

```sh
meson setup build -Dprofile=development   # configure (profile is required outside a git checkout)
meson compile -C build                    # build
./build/src/geary                         # run without installing
meson test -C build --print-errorlogs     # run tests
```

Run a single test suite by name (suites are defined in `test/meson.build`: `engine-tests`, `client-tests`, `js-tests`):

```sh
meson test -C build --print-errorlogs geary:engine-tests
```

Engine tests run headless; client and JS tests execute GTK/WebKit code and need a display. CI (`.github/workflows/ci.yml`, Arch Linux container) runs the headless-safe subset under xvfb:

```sh
xvfb-run -a dbus-run-session -- meson test -C build --print-errorlogs \
    vala-unit:tests geary:desktop-file-validate \
    geary:org.gnome.Geary.metainfo.xml-validate \
    geary:mail-merge-test geary:engine-tests
```

Within a suite, individual test cases can be selected with the test binary's path argument, e.g. `./build/test/test-engine <suite-path>` (GLib test conventions).

Integration tests (`build/test/test-integration PROTOCOL PROVIDER [HOSTNAME] LOGIN PASSWORD`) hit real IMAP/SMTP servers and are not run by CI — see `test/README.md`.

Build profiles (`-Dprofile=development|beta|release`) change the app ID (`org.gnome.Geary.Devel`, etc.), branding, and data locations. Packaging must use `release`.

## Architecture

Two main layers, built as separate libraries from `src/`:

- **`src/engine/`** — `libgeary-engine`, the non-GUI email library. Namespaced `Geary.*`. Key subsystems: `imap/` (protocol client), `imap-engine/` (account/folder synchronization logic on top of imap), `imap-db/` (SQLite-backed local mail store; schema migrations live in `sql/`), `smtp/`, `rfc822/` (message parsing via GMime), `db/` (SQLite wrapper), `nonblocking/` (async primitives), `api/` (public engine API surface: `Geary.Account`, `Geary.Folder`, `Geary.Email`, etc.).
- **`src/client/`** — the GTK application, namespaced by directory (`Application.*`, `Composer.*`, `ConversationViewer.*`, etc.). `application/` holds the main window and controller; `composer/`, `conversation-list/`, `conversation-viewer/`, `folder-list/`, `sidebar/` are the main UI components; `plugin/` is the libpeas plugin system; `web-process/` is the WebKitGTK web-extension process used to render message bodies. UI definitions are GtkBuilder files in `ui/`.

Supporting pieces: `bindings/` (custom VAPIs/metadata for libraries without upstream Vala bindings), `subprojects/` (`vala-unit` test framework, `libhandy` fallback), `test/` mirrors the src layout (`test/engine/`, `test/client/`, `test/js/`, plus `test/mock/`).

## Fork-specific changes (keep these intact when rebasing on upstream)

The FrankGeary delta over upstream is intentionally minimal and grouped by feature (see the patch policy in `docs/upstream-updates.md`):

1. **Contact autocomplete** — `src/client/composer/contact-entry-completion.vala` (tests in `test/client/composer/contact-entry-completion-test.vala`), plus `load_entry_completions()` in `composer-widget.vala`. Lowered `SEEN` threshold, no-reply filtering, searches **all** accounts' contact stores (sender first, deduped), and shows suggestions in a **GtkPopover** — GtkEntryCompletion's stock popup never maps on wlroots Wayland compositors (Hyprland), so do not reintroduce `complete()`/popup_completion.
2. **Copy Image context-menu action** — `src/client/conversation-viewer/conversation-message.vala`, `ui/conversation-message-menus.ui`
3. **Folder sidebar toggle (Ctrl+Shift+M)** — `src/client/application/application-main-window.vala`, `application-configuration.vala`, `desktop/org.gnome.Geary.gschema.xml`
4. **Docs / packaging / CI** — `.github/workflows/`, `packaging/aur/`, `docs/`
5. **Build fixes pending upstream** — messaging-menu plugin `Config.APP_ID` (PR #1; the bug also exists on upstream `main`). Drop each of these when the equivalent fix lands upstream. The `build-debian` CI job exists because Arch has no `libmessaging-menu`, so only a Debian build compiles that plugin.

The app id remains `org.gnome.Geary`; the only user-visible branding is the desktop launcher `Name=FRANK Geary` (`desktop/*.desktop.in.in` — deliberately untranslated so the name is uniform across locales).

## Packaging and releases

The repo is `github.com/akitaonrails/frank_geary` (standalone; the original fork was deleted to detach from the nielsdg/Geary network — old releases/secrets did not survive).

Release flow: push tag `v<pkgver>` with `_` → `-` (e.g. `pkgver=46.0_frank.2` → tag `v46.0-frank.2`) → `.github/workflows/binary-release.yml` builds a release-profile install tree in an Arch container and uploads `frank-geary-<pkgver>-x86_64.tar.zst` + `.sha256` to the GitHub Release (created if missing). Then update `packaging/aur/frank-geary-bin/PKGBUILD` (pkgver + sha256) and `frank-geary/PKGBUILD` (pkgver), regenerate both `.SRCINFO`s (`makepkg --printsrcinfo` — the validate job diffs them and fails on mismatch), push, and dispatch `aur.yml` with `publish=true` to push both packages to AUR (needs the `AUR_SSH_KEY` repo secret).
