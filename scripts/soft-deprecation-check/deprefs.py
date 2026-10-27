#!/usr/bin/env python3
"""Cross the index-store references with the symbol graphs' deprecations.

Usage: deprefs.py refs.tsv sg/ > deprecated-refs.txt

A member some graph lists only as a synthesized copy is matched too (see
below).
"""
import glob
import json
import os
import sys
from collections import defaultdict

refs_path, sg_root = sys.argv[1], sys.argv[2]

wanted = set()
with open(refs_path) as f:
    for line in f:
        wanted.add(line.split("\t", 1)[0])

dep = {}  # usr -> (title, [(domain, version, message, renamed)])
# The index records a protocol-extension member under its own USR, while a
# graph also lists it once per conforming type as `<usr>::SYNTHESIZED::<type>`, and
# for an underscored protocol (`_KeyValueCodingAndObserving.observe`) only that way.
# A copy also inherits its type's own deprecation (NSCoding's init(coder:) carries
# the deprecations of every deprecated NSCoding class), so copies count only for a
# USR no graph declares itself, and only the deprecations every copy on that
# platform shares.
declared = set()
copies = defaultdict(list)  # (usr, platform folder) -> [(title, marks)]
for path in glob.glob(os.path.join(sg_root, "**", "*.symbols.json"), recursive=True):
    with open(path) as f:
        graph = json.load(f)
    for sym in graph.get("symbols", []):
        usr, _, synthesized_for = sym["identifier"]["precise"].partition("::SYNTHESIZED::")
        if usr not in wanted:
            continue
        marks = []
        for a in sym.get("availability", []) or []:
            d = a.get("deprecated")
            if d is not None or a.get("isUnconditionallyDeprecated"):
                ver = "*" if d is None else ".".join(str(d.get(k, 0)) for k in ("major", "minor") if k in d)
                marks.append((a.get("domain", "*"), ver, a.get("message", ""), a.get("renamed", "")))
        if synthesized_for:
            platform = os.path.relpath(path, sg_root).split(os.sep)[0]
            copies[(usr, platform)].append((sym.get("names", {}).get("title", ""), frozenset(marks)))
            continue
        declared.add(usr)
        if marks:
            title = sym.get("names", {}).get("title", "")
            prev = dep.get(usr)
            if prev:
                merged = sorted(set(prev[1]) | set(marks))
                dep[usr] = (prev[0] or title, merged)
            else:
                dep[usr] = (title, sorted(set(marks)))

for (usr, _platform), found in copies.items():
    shared = frozenset.intersection(*(marks for _, marks in found))
    if usr in declared or not shared:
        continue
    prev = dep.get(usr)
    dep[usr] = (prev[0] if prev else found[0][0], sorted(set(prev[1] if prev else []) | shared))

by_usr = defaultdict(list)
with open(refs_path) as f:
    for line in f:
        usr, name, path, ln, col, roles = line.rstrip("\n").split("\t")
        if usr in dep:
            by_usr[usr].append((path, int(ln), int(col)))

root = os.path.commonpath([p for v in by_usr.values() for p, _, _ in v]) if by_usr else ""
for usr, sites in sorted(by_usr.items(), key=lambda kv: -len(kv[1])):
    title, marks = dep[usr]
    print(f"## {title}  [{len(sites)}]  {usr}")
    for m in marks:
        print(f"   deprecated {m[0]} {m[1]}  msg={m[2]!r} renamed={m[3]!r}")
    for p, ln, col in sorted(set(sites)):
        print(f"   {os.path.relpath(p, root)}:{ln}:{col}")
