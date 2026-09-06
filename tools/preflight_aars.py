#!/usr/bin/env python3
"""PREFLIGHT — is every staged AAR younger than the Kotlin it was built from?

THE DEFECT. `addons/<mod>/bin/{debug,release}/*.aar` is gitignored build output.
docs/FIELD.md used to ask, in prose, for a copy after every Kotlin change, and
nothing enforced it. A forgotten copy ships an OLD plugin under a NEW script and
the failure is silent — the APK builds, installs, runs, and answers the previous
question. Hours went into "the Kotlin change did nothing".

THIS SCRIPT IS THE MANDATORY STEP BEFORE AN EXPORT. It compares, per module, the
newest mtime under `android_plugin/<mod>/src/` with the oldest staged AAR, and
exits nonzero naming the module and both timestamps when the source is newer or
an AAR is missing entirely. It builds nothing and copies nothing: fixing it is
one command, `./gradlew exportAllAars`, and this script's whole job is to be the
thing that says so BEFORE forty minutes of export.

Cross-platform on purpose (the sibling tools are PowerShell; CI is not).

    python tools/preflight_aars.py            # check every module
    python tools/preflight_aars.py ixbody     # check one

Exit 0 = every staged AAR is at least as new as its source.
"""

from __future__ import annotations

import datetime as _dt
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGINS = os.path.join(ROOT, "android_plugin")
ADDONS = os.path.join(ROOT, "addons")

# Closed on purpose: a module missing from this list is a plugin nobody decided
# how to stage. It is the same list `settings.gradle.kts` includes and
# `tests/plugin_version_smoke.gd` walks.
MODULES = ["ixbody", "ixcap", "ixlens", "ixloc", "ixmesh", "ixmnn", "ixvoice"]

FLAVOURS = ["debug", "release"]

VERSION_RE = re.compile(r'PLUGIN_VERSION\s*=\s*"([^"]+)"')

# THE ONE DIRECTORY THAT IS NOT SOURCE. ixbody's build fetches ~52 MB of
# MediaPipe weights into src/main/assets/ at build time, so its mtime is always
# fresh and always meaningless as a signal that the Kotlin moved.
SKIP_DIRS = {"assets"}


def _stamp(ts: float) -> str:
    return _dt.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def newest_source(mod: str) -> tuple[float, str]:
    """(mtime, path) of the most recently touched real source file."""
    root = os.path.join(PLUGINS, mod, "src")
    best, best_path = 0.0, ""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            p = os.path.join(dirpath, name)
            try:
                ts = os.path.getmtime(p)
            except OSError:
                continue
            if ts > best:
                best, best_path = ts, p
    # The build file counts as source: a dependency bump changes the AAR
    # without touching a single .kt.
    for extra in ("build.gradle.kts",):
        p = os.path.join(PLUGINS, mod, extra)
        if os.path.exists(p) and os.path.getmtime(p) > best:
            best, best_path = os.path.getmtime(p), p
    return best, best_path


def staged(mod: str) -> list[tuple[str, float, str]]:
    """[(flavour, mtime, path)] for each staged AAR; mtime -1 when missing."""
    out = []
    for flavour in FLAVOURS:
        d = os.path.join(ADDONS, mod, "bin", flavour)
        found = ""
        if os.path.isdir(d):
            for name in sorted(os.listdir(d)):
                if name.endswith(".aar"):
                    found = os.path.join(d, name)
                    break
        out.append((flavour, os.path.getmtime(found) if found else -1.0, found))
    return out


def declared_version(mod: str) -> str:
    root = os.path.join(PLUGINS, mod, "src", "main", "kotlin")
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith(".kt"):
                continue
            with open(os.path.join(dirpath, name), encoding="utf-8") as fh:
                m = VERSION_RE.search(fh.read())
                if m:
                    return m.group(1)
    return ""


def check(mod: str) -> list[str]:
    """The complaints about one module. Empty means it is fit to export."""
    bad: list[str] = []
    src_ts, src_path = newest_source(mod)
    if src_ts == 0.0:
        return ["%s: no source under android_plugin/%s/src/" % (mod, mod)]

    for flavour, aar_ts, aar_path in staged(mod):
        if aar_ts < 0:
            bad.append("%s/%s: NO AAR STAGED — addons/%s/bin/%s/ is empty"
                       % (mod, flavour, mod, flavour))
            continue
        if aar_ts < src_ts:
            bad.append(
                "%s/%s: STALE — source %s (%s) is newer than %s (%s)"
                % (mod, flavour, os.path.relpath(src_path, ROOT), _stamp(src_ts),
                   os.path.relpath(aar_path, ROOT), _stamp(aar_ts)))

    # The stamp is the other half of the handshake `scripts/seam.gd` runs on the
    # phone. A stamp that disagrees with the source means the staged AAR answers
    # a version no script asks for, which is a refusal at attach.
    want = declared_version(mod)
    stamp_path = os.path.join(ADDONS, mod, "bin", "VERSION")
    if not want:
        bad.append("%s: no PLUGIN_VERSION constant in its Kotlin" % mod)
    elif not os.path.exists(stamp_path):
        bad.append("%s: no addons/%s/bin/VERSION — never staged by exportAars"
                   % (mod, mod))
    else:
        with open(stamp_path, encoding="utf-8") as fh:
            got = fh.read().strip()
        if got != want:
            bad.append("%s: staged stamp %s but the source says %s"
                       % (mod, got or "(empty)", want))
    return bad


def main(argv: list[str]) -> int:
    mods = argv[1:] or MODULES
    unknown = [m for m in mods if m not in MODULES]
    if unknown:
        print("unknown module(s): %s" % ", ".join(unknown), file=sys.stderr)
        return 2

    complaints: list[str] = []
    for mod in mods:
        bad = check(mod)
        complaints += bad
        print("%-8s %s" % (mod, "ok" if not bad else "STALE"))

    if not complaints:
        print("\npreflight: every staged aar is newer than its source.")
        return 0

    print("", file=sys.stderr)
    for line in complaints:
        print("preflight: " + line, file=sys.stderr)
    print("\npreflight: run `./gradlew exportAllAars` from android_plugin/ "
          "before exporting.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
