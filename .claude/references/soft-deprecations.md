# Soft deprecations

SDK 27 declares most of its replacements `deprecated: 100000` (also 10000 or 1000), and headers use
`API_TO_BE_DEPRECATED`. The compiler reports none of them, so the push gate's zero-warnings rule can't
see them either.

- **Running it.** `scripts/soft-deprecation-check.sh` takes about 10 minutes.
  - It needs `TMPDIR` set, and has no shared fallback: it deletes under that path and trusts the cache it
    finds there, so the path has to be the user's own.
  - It builds what the push gate builds, plus the package's tests for macOS, into
    `${TMPDIR}askkit-softdep/` with indexing on.
  - It writes the report to `${TMPDIR}askkit-softdep/soft-deprecations.txt`, and the build logs to
    `logs/` beside it.
  - The per-platform symbol-graph cache it keeps is about 4 GB. It caches only a module the SDK doesn't
    have, such as AppKit for iOS, as skipped, and prints how many it skipped. A graph that fails to
    extract for any other reason isn't cached: it is retried on the next run, and this one still writes
    its report, which misses that module's deprecations, and exits 1.
  - An index it can't read, one with no units, or none for a file under the repo fails the run.
  - `--keep`, then `--reuse`, re-reads that index without rebuilding, so it sees only the tree as it was
    built.
  - `--strict` exits 1 on any soft row.
- **Reading a row.** A row reads `## symbol [sites] usr` and lists `deprecated <platform> <version>`.
  - A version above 27 is soft. A real version is hard, and the build already warns about those.
  - A row deprecated on one platform matters only where that code compiles, so check its `#if`. For
    example, `contextMenu(menuItems:)` is deprecated on watchOS alone, and AskUI never builds there.
  - Rows at an attribute's column are macro expansions (`@Generable`, `#expect`), which you can't
    change.
- **Coverage.** It reads every leg the push gate builds:
  - the five platforms;
  - the iOS, visionOS and watchOS device builds;
  - the demo's three apps and its UI tests;
  - the package tests.

  Its symbol graphs include watchOS and the test frameworks (Testing, XCTest, XCUIAutomation).
- **URL traps.**
  - The old `.path` and `.host` percent-decode, so use `path(percentEncoded: false)`.
  - The old `.path` also drops a trailing slash that `path(percentEncoded:)` keeps.
  - `appendingPathComponent` stats the disk to decide on a trailing slash, while `appending(path:)`
    infers it from the string, so pass `directoryHint: .isDirectory` for folders.
  - `AskPersistedLocationTests` pins every path the store, the archive and the feedback attachments
    write.
