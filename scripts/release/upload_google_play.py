#!/usr/bin/env python3
"""Uploads a signed AAB to a Google Play track (default: internal testing).

Used by .github/workflows/release.yml's `google-play-internal` job. Never
run this against `production` from CI -- see docs/release/GOOGLE_PLAY.md
"Production promotion is manual": this script's --track default and the
release workflow that calls it are both hard-limited to internal/beta
tracks; promoting a release to production/closed-testing-beyond-what's-
configured is a deliberate, separate action a human takes in the Play
Console UI, not something this script is meant to do.

Auth: a service account JSON key with the "Release manager" (or
equivalent) permission on the app in Play Console, provided via the
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON environment variable (the raw JSON
content, not a file path) -- see docs/release/GOOGLE_PLAY.md for how to
create one. Never logged, never written to disk in plaintext for longer
than this process needs it.

Uses Google's own official `google-api-python-client` /
`google-auth` libraries against the public, documented Android Publisher
API v3 -- not a third-party wrapper.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

ALLOWED_TRACKS = {"internal", "alpha", "beta"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-name", required=True, help="e.g. com.david610.singboxclient")
    parser.add_argument("--aab", required=True, help="path to the signed .aab file")
    parser.add_argument(
        "--track",
        default="internal",
        choices=sorted(ALLOWED_TRACKS),
        help="Play Console track to release to (default: internal). "
        "production and closed-testing tracks beyond this allowlist are "
        "deliberately not supported here -- see docs/release/GOOGLE_PLAY.md.",
    )
    parser.add_argument(
        "--release-notes",
        default=None,
        help="optional path to a plain-text release notes file (en-US)",
    )
    args = parser.parse_args()

    if args.track not in ALLOWED_TRACKS:
        # Defense in depth on top of argparse's `choices` -- this script
        # must never be the thing that pushes to production.
        print(f"error: track {args.track!r} is not allowed by this script", file=sys.stderr)
        return 1

    service_account_json = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    if not service_account_json:
        print("error: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not set", file=sys.stderr)
        return 1

    try:
        service_account_info = json.loads(service_account_json)
    except json.JSONDecodeError as e:
        print(f"error: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not valid JSON: {e}", file=sys.stderr)
        return 1

    # Imported here, not at module scope, so `--help` works even before
    # these are installed (the workflow installs them immediately before
    # calling this script; see release.yml).
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError

    credentials = service_account.Credentials.from_service_account_info(
        service_account_info,
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    service = build("androidpublisher", "v3", credentials=credentials)

    edits = service.edits()
    try:
        edit = edits.insert(packageName=args.package_name, body={}).execute()
        edit_id = edit["id"]
        print(f"opened edit {edit_id}")

        with open(args.aab, "rb") as f:
            bundle = (
                edits.bundles()
                .upload(
                    packageName=args.package_name,
                    editId=edit_id,
                    media_body=args.aab,
                    media_mime_type="application/octet-stream",
                )
                .execute()
            )
        version_code = bundle["versionCode"]
        print(f"uploaded bundle: versionCode {version_code}")

        release = {"versionCodes": [version_code], "status": "completed"}
        if args.release_notes and os.path.exists(args.release_notes):
            with open(args.release_notes, encoding="utf-8") as f:
                notes = f.read().strip()
            if notes:
                release["releaseNotes"] = [{"language": "en-US", "text": notes}]

        edits.tracks().update(
            packageName=args.package_name,
            editId=edit_id,
            track=args.track,
            body={"track": args.track, "releases": [release]},
        ).execute()
        print(f"assigned versionCode {version_code} to track {args.track!r}")

        edits.commits().commit(packageName=args.package_name, editId=edit_id).execute()
        print(f"committed edit {edit_id} -- versionCode {version_code} is now live on "
              f"track {args.track!r} (internal/beta only -- production promotion is a "
              f"separate, manual Play Console action; see docs/release/GOOGLE_PLAY.md)")
    except HttpError as e:
        print(f"error: Play Developer API request failed: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
