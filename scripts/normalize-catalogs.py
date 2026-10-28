#!/usr/bin/env python3
"""Normalize String Catalogs back to the repo's committed shape.

What it is for: an `xcodebuild -exportLocalizations` pass rewrites every
`.xcstrings` it touches in Xcode's own serialization and its own key order, and
a single pass has turned a six-key change into a 150,000-line diff nobody could
review. That is not cosmetic — it is how a translation regression hides in the
noise.

Xcode's exporter is not the only writer that does this. A one-key
`StringCatalogEdit` through the Xcode MCP rewrites the whole file, and any MCP
build rewrites every catalog in the tree. Neither announces itself.

The committed shape is therefore Xcode's *exact* serialization —
`json.dumps(indent=2, separators=(',', ' : '))`, verified byte-identical
against a catalog Xcode itself wrote — with `strings` sorted by key. Matching
the writer means an extraction pass changes only what actually changed;
sorting is the one thing added on top, and it is what keeps the diff readable
when it does.

Run after any pass that may have rewritten a catalog, before committing:

    python3 scripts/normalize-catalogs.py

`--check` reports without writing and exits 1 when anything is out of shape.
That is what the push gate runs, so the committed tree stays canonical
whether or not anyone remembered to run the writer form.

It is purely a reserialization — keys, values, comments, `shouldTranslate`
markers and `extractionState` are all preserved byte-for-byte in content. It
reports which files it rewrote.
"""
import json
import os
import sys
import tempfile
from collections import OrderedDict

# Imported, not restated: the completeness ratchet owns catalog discovery, and
# two hand-maintained lists is how one of them ends up missing a catalog.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module  # noqa: E402

discover_catalogs = import_module("check-catalog-completeness").discover_catalogs


def normalized(catalog):
    """Sort `strings` by key; leave every other top-level field in place."""
    out = OrderedDict()
    for field, value in catalog.items():
        if field == "strings":
            out[field] = OrderedDict(sorted(value.items()))
        else:
            out[field] = value
    return out


def serialized(catalog):
    """Xcode's own serialization, which is the whole point of this file."""
    return json.dumps(normalized(catalog), ensure_ascii=False, indent=2,
                      separators=(",", " : ")) + "\n"


def write_atomically(path, text):
    """Replace `path` with `text` whole or not at all.

    Written in place, a catalog is empty from the moment the file opens until
    the last byte lands, and an interrupted run leaves it truncated: a broken
    catalog, or one that parses with strings missing. So the new text goes to a
    file beside it, which takes its mode, and a rename puts it in place. That
    file's name is hidden, so if a kill leaves it behind, SwiftPM and the push
    gate pass over it.
    """
    directory, name = os.path.split(path)
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=directory or ".", prefix=f".{name}.",
        suffix=".tmp", delete=False)
    try:
        with handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(handle.name, os.stat(path).st_mode & 0o7777)
        os.replace(handle.name, path)
    except BaseException:
        os.unlink(handle.name)
        raise


def main():
    check_only = "--check" in sys.argv[1:]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    out_of_shape = []
    for path in discover_catalogs():
        with open(path, encoding="utf-8") as handle:
            before = handle.read()
        after = serialized(json.loads(before, object_pairs_hook=OrderedDict))
        if after == before:
            continue
        out_of_shape.append(path)
        if not check_only:
            write_atomically(path, after)

    if not out_of_shape:
        print("✓ catalogs already normalized")
        return 0

    if check_only:
        print(f"✗ {len(out_of_shape)} catalog(s) are not in the committed shape:")
        for path in out_of_shape:
            print(f"    {path}")
        print("  run: python3 scripts/normalize-catalogs.py")
        return 1

    print(f"✓ normalized {len(out_of_shape)} catalog(s):")
    for path in out_of_shape:
        print(f"    {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
