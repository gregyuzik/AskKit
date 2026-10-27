#!/usr/bin/env python3
"""README.md's samples against the files they are copied from.

Why it exists: README.md's Adopt section shows the code of two files in
Tests/AskCrossPostureTests, which the package's tests compile and run:
ReadmeDomain.swift, a domain over the app's own rows, and
ReadmeAssistantDomain.swift, a domain without rows. A copy that drifts from its
file shows an adopter code that nothing builds, and nothing else compares the
two.

The rule: every ```swift block between the `## Adopt` heading and the next `## `
heading is a run of one sample file's lines, word for word. Each file is longer
than any one block: the `#if` lines and the tests sit outside them, and a file's
blocks are separate runs of it, so each block is looked for as a whole, as
consecutive lines, in each file, and maps to the first that holds it. Scoped to
the Adopt section because the Install block above it is lines of a
Package.swift, which neither file holds.

A block that isn't found fails with a diff against the nearest lines of the
file it is closest to. The check also fails when the section has no Swift block
at all, so a renamed heading can't turn it into a check of nothing, and when a
sample file has no block, so a sample the README stopped showing can't sit
unchecked.

usage: python3 -I scripts/check-readme-sample.py
"""

import difflib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
SAMPLES = [
    ROOT / "Tests" / "AskCrossPostureTests" / "ReadmeDomain.swift",
    ROOT / "Tests" / "AskCrossPostureTests" / "ReadmeAssistantDomain.swift",
]
SECTION = "## Adopt"


def fail(message):
    print(f"check-readme-sample: {message}", file=sys.stderr)
    sys.exit(1)


def adopt_blocks(lines):
    """The Adopt section's Swift blocks, as (README line number, lines)."""
    blocks = []
    in_section = False
    current = None
    for number, line in enumerate(lines, 1):
        if current is not None:
            if line.rstrip() == "```":
                blocks.append(current)
                current = None
            else:
                current[1].append(line)
        elif line.startswith("## "):
            in_section = line.rstrip() == SECTION
        elif in_section and line.rstrip() == "```swift":
            current = (number + 1, [])
    if current is not None:
        fail(f"README.md:{current[0] - 1}: a ```swift block never closes")
    return blocks


def find_run(lines, run):
    """Where `run` sits in `lines` as consecutive lines, or None."""
    for start in range(len(lines) - len(run) + 1):
        if lines[start:start + len(run)] == run:
            return start
    return None


def nearest(sample, block):
    """The stretch of `sample` that `block` is closest to, and where it starts.

    Bounded by the substantial runs the two share, so the diff shows the block's
    own region and not the rest of the file.
    """
    matcher = difflib.SequenceMatcher(None, sample, block, autojunk=False)
    shared = [m for m in matcher.get_matching_blocks() if m.size >= 3]
    if not shared:
        longest = matcher.find_longest_match(0, len(sample), 0, len(block))
        if longest.size == 0:
            return [], 0
        shared = [longest]
    first, last = shared[0], shared[-1]
    start = max(0, first.a - first.b)
    end = min(len(sample), last.a + len(block) - last.b)
    return sample[start:end], start


def closest(samples, block):
    """The sample `block` is most like, its stretch nearest the block, and where
    that stretch starts: the diff a failing block is shown against."""
    best = None
    for path, lines in samples.items():
        stretch, start = nearest(lines, block)
        score = difflib.SequenceMatcher(None, stretch, block, autojunk=False).ratio()
        if best is None or score > best[0]:
            best = (score, path, stretch, start)
    return best[1:]


def main():
    try:
        readme = README.read_text(encoding="utf-8").split("\n")
        samples = {path: path.read_text(encoding="utf-8").split("\n") for path in SAMPLES}
    except OSError as error:
        fail(str(error))

    blocks = adopt_blocks(readme)
    if not blocks:
        fail(f"README.md has no ```swift block under '{SECTION}'; the check would compare nothing")

    failed = False
    shown = {path: 0 for path in SAMPLES}
    for number, block in blocks:
        source = next(
            (path for path, lines in samples.items() if block and find_run(lines, block) is not None),
            None,
        )
        if source is not None:
            shown[source] += 1
            continue
        failed = True
        path, stretch, start = closest(samples, block)
        name = path.relative_to(ROOT)
        print(
            f"check-readme-sample: README.md:{number}: this block isn't a run of any sample "
            f"file's lines, word for word. Diff from the nearest lines of {name}, the file "
            "it is closest to, to the README's:",
            file=sys.stderr,
        )
        diff = difflib.unified_diff(
            stretch,
            block,
            fromfile=f"{name}:{start + 1}",
            tofile=f"README.md:{number}",
            lineterm="",
        )
        print("\n".join(diff), file=sys.stderr)
    if failed:
        fail(
            "change README.md's block or the file so they match; the file is the one "
            "the package's tests compile"
        )
    unshown = [path for path, count in shown.items() if count == 0]
    if unshown:
        fail(
            "no ```swift block under "
            f"'{SECTION}' comes from {', '.join(str(path.relative_to(ROOT)) for path in unshown)}; "
            "show its code there, or take it out of SAMPLES in this script"
        )
    counts = ", ".join(f"{count} from {path.name}" for path, count in shown.items())
    print(f"check-readme-sample: {len(blocks)} README blocks match: {counts}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
