# Security

ThisNote is local-first. It does not create an account and does not upload notes by default.

## What the PIN lock is

The 4-digit PIN locks the interface. It is **not** disk encryption: note files remain plain JSON in the data directory. Use full-disk encryption (BitLocker / Android device encryption) if you need encryption at rest.

## Secrets

The optional AI API key and WebDAV password are stored in the OS keystore (Windows Credential Manager / Android Keystore) by `flutter_secure_storage`. When the OS store is unavailable, the app falls back to the local settings file so it never silently loses a key; that fallback is the only case where `settings.json` contains a secret. Backups include `settings.json`, but not the OS keystore, so restored secrets must be entered again on a new device.

## Backups

Backups are ordinary zip archives. They are not encrypted. Store them somewhere you trust.

## Reporting

Open a private security advisory on GitHub if you find a vulnerability. Do not attach real note data or API keys.