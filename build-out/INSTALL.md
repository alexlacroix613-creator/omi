# Omi.app — install / swap instructions

Built from fork branch `feat/native-provider-auth-v0.12.0` (HEAD `b90566180`),
rebased onto upstream tag `v0.12.0+12000-macos`.
Version: **0.12.0-siempre1**  ·  Bundle ID: `com.omi.computer-macos` (matches the
store build, so it swaps in cleanly and keeps existing permissions/deep-links).

This build is **ad-hoc signed** (no Apple Developer identity was available on this
machine). It is meant for local use on THIS Mac, not for distribution.

---

## What this is

`build-out/Omi.app` is a full, self-contained bundle assembled the same way
upstream's `desktop/macos/run.sh` assembles it: Swift release binary + Sparkle /
Sentry / onnxruntime frameworks + the Node agent bridge (`Resources/agent/dist`,
including our new `adapters/codex.js`, `codex-auth.js`, `patched-codex-entry.mjs`)
+ the bundled universal Node runtime + Firebase/Mixpanel client config in
`Resources/.env` (copied from the installed store build — same product).

---

## Install (swap it in for the store build)

Run these in Terminal, one block at a time.

```bash
# 1. Quit the running Omi
osascript -e 'quit app "omi"' 2>/dev/null || true
pkill -f "Omi Computer" 2>/dev/null || true
sleep 2

# 2. Back up the current store build (timestamped, so it's reversible)
ditto /Applications/omi.app "$HOME/omi-app-backup-$(date +%Y%m%d-%H%M%S).app"

# 3. Remove the old app and copy the new one in
rm -rf /Applications/omi.app
ditto /Users/alexl/projects/omi/build-out/Omi.app /Applications/omi.app

# 4. Clear the quarantine flag and launch
xattr -dr com.apple.quarantine /Applications/omi.app
open /Applications/omi.app
```

> First launch: because the build is ad-hoc signed, macOS may prompt to confirm
> opening it, and it will re-request Screen Recording / Microphone / Accessibility
> permissions (an ad-hoc signature has a different code identity than the store
> build). Grant them again in System Settings → Privacy & Security if asked.

---

## Rollback (restore the store build)

```bash
# Quit the swapped-in build
osascript -e 'quit app "omi"' 2>/dev/null || true
pkill -f "Omi Computer" 2>/dev/null || true
sleep 2

# Restore from the backup you made in step 2 (use your actual timestamp)
rm -rf /Applications/omi.app
ditto "$HOME/omi-app-backup-YYYYMMDD-HHMMSS.app" /Applications/omi.app
open /Applications/omi.app
```

If you did not keep a backup, the current store build (v0.12.0) can be
re-downloaded / re-installed from Omi's normal distribution channel.
