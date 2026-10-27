<!-- What changes, and why. A change in behaviour also fixes the comments and docs it makes untrue. -->

- [ ] `swift test` passes, and a change in behaviour comes with a test that fails without it.
- [ ] `swiftlint lint` is clean, and the build has no warnings.
- [ ] New public API is called from `Tests/AskCrossPostureTests`.
- [ ] New user-facing strings are translated into every locale, and looked up with `bundle: #bundle`: `python3 scripts/check-catalog-completeness.py`.
