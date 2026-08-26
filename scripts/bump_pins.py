#!/usr/bin/env python3
"""Bump the pinned revisions in config/west.yml.

Each pin's trailing comment (`# <branch> @ <date>`) names the branch it tracks.
For every project, fetch that branch's head from the project's remote and
rewrite the pin (and its date) in place, preserving the file's formatting.
The actual checkout sync stays with `west update` (the `just bump` recipe runs
it); this script only rewrites the manifest.

Usage: bump_pins.py [--dry-run]
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEST_YML = ROOT / "config" / "west.yml"
TOPDIR = ROOT / "zmk-workspace" / "zmk"

REVISION_RE = re.compile(
    r"^(\s*revision:\s*)([0-9a-f]{40})"
    r"(\s*#\s*)(\S+)(\s*@\s*)(\d{4}-\d{2}-\d{2})\s*$"
)


def git(clone, *args):
    return subprocess.run(
        ["git", "-C", str(clone), *args],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def main():
    dry_run = "--dry-run" in sys.argv[1:]

    lines = WEST_YML.read_text().splitlines(keepends=True)
    section = None
    url_bases = {}
    name = None
    remote = None
    changes = []
    out = []

    for line in lines:
        stripped = line.strip()
        if stripped in ("remotes:", "projects:"):
            section = stripped[:-1]
        elif m := re.match(r"\s*- name:\s*(\S+)", line):
            name = m.group(1)
        elif m := re.match(r"\s*(?:url-base|remote):\s*(\S+)", line):
            if section == "remotes":
                url_bases[name] = m.group(1)
            else:
                remote = m.group(1)
        elif (m := REVISION_RE.match(line)) and section == "projects":
            prefix, old_sha, c1, branch, c2, old_date = m.groups()
            clone = TOPDIR / name
            if not clone.is_dir():
                sys.exit(f"❌ no local clone for {name} at {clone} — run 'just update' first")
            url = f"{url_bases[remote]}/{name}"
            git(clone, "fetch", "--quiet", url, branch)
            new_sha = git(clone, "rev-parse", "FETCH_HEAD")
            new_date = git(clone, "log", "-1", "--format=%cs", "FETCH_HEAD")
            if new_sha != old_sha:
                changes.append(f"  {name}: {old_sha[:10]} ({old_date}) → {new_sha[:10]} ({new_date}) [{branch}]")
                line = f"{prefix}{new_sha}{c1}{branch}{c2}{new_date}\n"
            else:
                print(f"  {name}: already at {branch} head ({old_sha[:10]}, {old_date})")
        out.append(line)

    if not changes:
        print("✅ All pins already at their branch heads")
        return

    print(f"{'Would bump' if dry_run else 'Bumping'} {len(changes)} pin(s):")
    print("\n".join(changes))
    if not dry_run:
        WEST_YML.write_text("".join(out))


if __name__ == "__main__":
    main()
