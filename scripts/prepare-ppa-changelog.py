#!/usr/bin/env python3
"""Bring the *first* debian/changelog entry to the PPA release version.

This script is deliberately conservative:

* It never rewrites or deletes changelog history.
* If the first entry already has the requested Debian version, only its
  distribution is normalised (e.g. UNRELEASED -> resolute).
* Otherwise a brand-new entry is *prepended*, reusing the maintainer identity
  found in the previous first entry (or DEBFULLNAME/DEBEMAIL).

Usage:
    prepare-ppa-changelog.py UPSTREAM_VERSION DISTRIBUTION
                             [--debian-revision REV]
                             [--changelog PATH]

Example:
    prepare-ppa-changelog.py 0.3.0 resolute
    -> win12-desktop (0.3.0-1~ubuntu26.04.1) resolute; urgency=medium
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from email.utils import formatdate

HEADER_RE = re.compile(
    r"^(?P<pkg>\S+) \((?P<ver>[^)]+)\) (?P<dist>[^ ;]+); urgency=(?P<urg>\w+)\s*$"
)
TRAILER_PREFIX = " -- "


def die(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def split_trailer(line: str) -> tuple[str, str] | None:
    """Split a ' -- Maintainer <email>  RFC2822 date' trailer."""
    if not line.startswith(TRAILER_PREFIX):
        return None
    maint, sep, date = line[len(TRAILER_PREFIX):].rpartition("  ")
    if not sep or not maint:
        return None
    return maint, date


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream")
    parser.add_argument("distribution")
    parser.add_argument("--debian-revision", default="1~ubuntu26.04.1")
    parser.add_argument("--changelog", default="debian/changelog")
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.upstream):
        die(f"upstream version must look like 0.3.0, got {args.upstream!r}")

    full_version = f"{args.upstream}-{args.debian_revision}"
    path = args.changelog

    if not os.path.isfile(path):
        die(f"changelog not found: {path}")

    with open(path, encoding="utf-8") as handle:
        lines = handle.readlines()

    if not lines:
        die(f"changelog is empty: {path}")

    match = HEADER_RE.match(lines[0].rstrip("\n"))
    if not match:
        die("first changelog line does not match the expected header format")

    package = match.group("pkg")
    urgency = match.group("urg")

    # Case 1: top entry already targets this version. Only fix distribution.
    if match.group("ver") == full_version:
        if match.group("dist") != args.distribution:
            lines[0] = (
                f"{package} ({full_version}) {args.distribution};"
                f" urgency={urgency}\n"
            )
            with open(path, "w", encoding="utf-8") as handle:
                handle.writelines(lines)
            print(f"Updated distribution to {args.distribution!r}.")
        else:
            print("Top changelog entry already current; nothing changed.")
        return

    # Case 2: a new release. Reuse the previous entry's maintainer identity.
    maintainer = None
    for line in lines:
        parsed = split_trailer(line.rstrip("\n"))
        if parsed is not None:
            maintainer = parsed[0]
            break

    if maintainer is None:
        full_name = os.environ.get("DEBFULLNAME", "").strip()
        email = os.environ.get("DEBEMAIL", "").strip()
        if full_name and email:
            maintainer = f"{full_name} <{email}>"
        elif email:
            maintainer = email
        else:
            die(
                "cannot derive maintainer from an existing trailer and "
                "DEBFULLNAME/DEBEMAIL are not set"
            )

    new_entry = (
        f"{package} ({full_version}) {args.distribution};"
        f" urgency={urgency}\n"
        f"\n"
        f"  * New upstream release {args.upstream}.\n"
        f"\n"
        f"{TRAILER_PREFIX}{maintainer}  {formatdate(localtime=True)}\n"
        f"\n"
    )

    with open(path, "w", encoding="utf-8") as handle:
        handle.write(new_entry)
        handle.writelines(lines)

    print(f"Prepended changelog entry {full_version} for {args.distribution}.")


if __name__ == "__main__":
    main()
