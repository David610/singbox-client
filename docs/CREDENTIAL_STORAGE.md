# Credential storage and portable backups

Status: implemented in code; Android/iOS behavior still requires the physical
device checks listed in `DEVICE_ACCEPTANCE.md`.

## Storage boundary

Before this change, `subscribe.json` contained complete imported sing-box
outbounds and remote subscription URLs. Consequently VLESS UUIDs, Hysteria2
and obfuscation passwords, subscription tokens embedded in URLs, and REALITY
key material were ordinary plaintext application-support files.

`ProfileCredentialStore` now walks the complete persisted profile document and
the settings document (which can contain WebDAV, local proxy, and other
passwords).
Authentication fields and the complete `url_or_path` value are written through
`flutter_secure_storage`. That plugin uses Android Keystore-backed storage on
Android and Keychain on iOS. `subscribe.json` retains non-secret routing and UI
metadata but replaces each secret with an opaque `secure-credential:v1:`
reference. The live document is rehydrated in memory immediately before the
existing parser/config-builder path uses it. Secrets necessarily exist in
process memory and in the transient configuration handed to sing-box while a
tunnel runs; platform credential stores cannot remove that architectural
requirement.

### Migration guarantees

On first load of a legacy profile, every secret is written and read back from
the secure store. Only after every verification succeeds is a temporary
reference-only JSON file flushed and atomically renamed over the old file. A
failure leaves the original bytes untouched and usable by the prior app build.
Running migration again is a no-op. Missing or checksum-invalid secure entries
fail closed rather than starting a tunnel with incomplete credentials. A
successful later save reconciles and deletes entries no longer referenced by
any profile, covering deletion, replacement, and credential rotation.

Uninstall, device migration, Keychain access-group changes, a device security
reset, or OS-level secure-store loss can make references unrecoverable. The app
does not try to reconstruct secrets or silently discard profiles in that case;
the user must re-import the subscription/profile.

## Portable backups

Portable ZIP backups are intentionally **credential-free**, not encrypted.
They contain only `diversion_group.json` and `subscribe_use.json`.
`subscribe.json`, `setting.json`, and platform secure-store entries are excluded.
This avoids inventing a cryptographic format and avoids exporting device-bound
Keystore/Keychain values. After restore, users must re-import subscriptions and
credentials. There is no "include credentials" mode.

The previous backup file list named nonexistent `servers.json` and `use.json`
files. Besides making backup unreliable, changing those names to the real
credential-bearing file would have produced a plaintext credential archive.
The corrected list uses the real non-secret filenames and deliberately omits
the profile file.
