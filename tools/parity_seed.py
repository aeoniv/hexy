#!/usr/bin/env python3
"""Seed tests/parity/parity.json from the frozen baseline.

    python tools/parity_seed.py [path/to/baseline.json]

Default baseline: D:/GitHub/ix64-core/sdlc/hexy/baseline.json (outside the
product repo; read only). One entry per frozen GREEN test, in baseline order.

Idempotent: an entry already in parity.json keeps its status/here/reason, so
re-running never undoes porting work. New green tests come in as `todo`, using
SEED below when the file has no entry yet. Entries whose frozen file is no
longer green in the baseline are dropped from the ledger.
"""
import json
import os
import sys

BASELINE = "D:/GitHub/ix64-core/sdlc/hexy/baseline.json"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "parity", "parity.json")

PORTED = [
    "q6_core", "test_q6_equivariance", "q6_lattice_smoke", "oracle_tendency_smoke",
    "oracle_sense_smoke", "oracle_rig_smoke", "test_huohoutu_dual_mandala",
]
DEFERRED = {
    "q6_cast_version": "loads scripts/core/store.gd -> brain/character.gd",
    "test_cast_bus": "loads scripts/core/store.gd -> brain/character.gd",
    "test_core_iching": "loads scripts/core/store.gd -> brain/character.gd",
    "test_character_changing_line": "loads scripts/brain/character.gd",
    "test_habits_q6": "loads scripts/brain/character.gd",
    "test_mb_line_is_pure": "loads scripts/brain/fly_skill_memory.gd",
    "test_wedge_trigram_table": "loads scripts/brain/fly_calcium_radar_2d.gd, fly_brain.gd, fly_connectome.gd",
    "test_sensor_oracle_8x8": "loads scripts/sensor_oracle.gd -> brain",
    "oracle_feed_smoke": "loads scripts/glass/doors_sheet.gd",
    "test_front_card_reading": "loads scripts/glass/front.gd",
    "test_reading_configuration": "loads scripts/glass/reading_sheet.gd",
    "test_rig_oracle_channels": "loads scripts/core/learning/sensor_rig.gd",
}


def ported_here(stem):
    name = stem if stem.startswith("test_") else "test_" + stem
    return "tests/q6/%s.gd" % name


def seed_entry(frozen, tech):
    stem = os.path.splitext(os.path.basename(frozen))[0]
    if stem in PORTED:
        return {"frozen": frozen, "tech": tech, "status": "ported", "here": ported_here(stem)}
    if stem in DEFERRED:
        return {"frozen": frozen, "tech": tech, "status": "deferred", "reason": DEFERRED[stem]}
    return {"frozen": frozen, "tech": tech, "status": "todo"}


def main():
    baseline = sys.argv[1] if len(sys.argv) > 1 else BASELINE
    with open(baseline, encoding="utf-8") as fh:
        tests = json.load(fh)["tests"]
    green = [t for t in tests if t["state"] == "green"]

    existing = {}
    if os.path.exists(OUT):
        with open(OUT, encoding="utf-8") as fh:
            for e in json.load(fh).get("entries", []):
                existing[e["frozen"]] = e

    entries = []
    for t in green:
        e = existing.get(t["file"]) or seed_entry(t["file"], t["tech"])
        e["tech"] = t["tech"]
        entries.append(e)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    doc = {
        "about": "Parity ledger: one entry per GREEN test of the frozen source "
                 "(sdlc/hexy/baseline.json). status: ported (here = the test in this repo) | "
                 "deferred | dropped (reason required) | todo. Seeded by tools/parity_seed.py; "
                 "checked by tests/test_parity.gd.",
        "frozen_green": len(green),
        "entries": entries,
    }
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    counts = {}
    for e in entries:
        counts[e["status"]] = counts.get(e["status"], 0) + 1
    print("wrote %s: %d entries %s" % (OUT, len(entries), counts))


if __name__ == "__main__":
    main()
