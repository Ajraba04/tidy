# Opening an unsigned release

Signing and notarizing a release is optional (see the main README's
Privacy & Signing section for why). If a release isn't signed, macOS
Gatekeeper will refuse to open it with a message like:

> "Tidy" can't be opened because Apple cannot check it for malicious software.

This doesn't mean anything is wrong with the app — it means nobody paid
Apple to notarize this particular build. The app is fully functional
either way. Two ways to open it:

## Option 1: Right-click, then Open

1. Unzip the release download.
2. In Finder, right-click (or Control-click) `Tidy.app` and choose **Open**.
3. In the dialog that appears, click **Open** again.

macOS remembers this choice — you only need to do it once per download.

## Option 2: Remove the quarantine flag

Every file downloaded from the internet gets a `com.apple.quarantine`
extended attribute, which is what triggers the Gatekeeper warning. You can
remove it directly:

```bash
xattr -dr com.apple.quarantine /path/to/Tidy.app
```

Then launch the app normally by double-clicking it.

## Verifying what you downloaded

Tidy makes zero network calls — you can check this yourself. With the app
running, open **Activity Monitor ▸ Network** (or use `nettop` / Little
Snitch / any traffic monitor of your choice) and confirm it shows no
connections while you use any part of the app. The source is also fully
open — read `TidyCore/` before you build or run it, if you'd rather verify
that way.
