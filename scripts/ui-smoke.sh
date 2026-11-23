#!/bin/sh
# Run the demo's UI smoke suite on an iPhone 18 Pro simulator.
#
# CI builds this bundle and never runs it. The push gate, given PREPUSH_LIB,
# runs it only for a push that changes Sources/AskUI/, Demo/ or the scripts
# that run it (this one and ci.sh): it takes about 12 minutes and is the
# flakiest step there is. This script runs it by hand. It
# is `scripts/ci.sh ui-smoke`, which finds the simulator the way `test-ios`
# does, builds the suite for it and runs it, and keeps the logs, the result
# bundle and DerivedData under $ASKKIT_CI_WORK with the other steps'.
#
# Pass a test identifier to run one:
#   scripts/ui-smoke.sh AskScreenSmokeTests/testTheScreenPassesApplesAccessibilityAudit
set -eu

exec "$(dirname "$0")/ci.sh" ui-smoke "$@"
