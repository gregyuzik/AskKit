# Private Cloud Compute in development

Three things keep a development run off Private Cloud Compute: the context gate, the entitlement and
the development park. ARCHITECTURE.md §3 says how each works ("Entitlements", "The development park",
"Private Cloud Compute's context gate"), and README.md's "Development builds and Private Cloud Compute"
how a host opts a run in. This page is how to measure the tier anyway.

## Measuring it

- Use a signed build of an app that holds the entitlement and declares it, launched with the opt-in
  (`ASK_LIVE_PCC=1`); a device is the sure way. Or use a TestFlight build, which is never parked.
- A failure in a simulator build says nothing about the tier: an entitled simulator build driven through
  its UI by automation has failed its first request with the context gate's error, about 300 ms in, and
  handed down correctly.
- A simulator build's entitlements are in the section Xcode embeds, `otool -s __TEXT __entitlements
  <binary>`; `codesign -d --entitlements` prints an empty `[Dict]` there.
- The demo always shows "On device": it declares no entitlement, and it is parked anyway, so its
  settings card says Private Cloud Compute isn't enabled in this build. That is by design.
- A diagnostics row in the host's settings runs `AskEval` on the tier that serves (ARCHITECTURE.md,
  "Evaluation and diagnostics").
- The on-device model does answer from `swift test`, so on-device probes can run there.
