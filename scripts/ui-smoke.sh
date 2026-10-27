#!/bin/sh
# Run the demo's UI smoke suite on an iPhone 18 Pro simulator.
#
# CI and the push gate BUILD this bundle and don't run it: a simulator UI test
# would be the flakiest part of a gate every change passes. This script is how
# it runs. It is `scripts/ci.sh ui-smoke`, which finds the simulator the way
# `test-ios` does and keeps the log, the result bundle and DerivedData under
# $ASKKIT_CI_WORK with the other steps'.
#
# Pass a test identifier to run one:
#   scripts/ui-smoke.sh AskScreenSmokeTests/testTheScreenPassesApplesAccessibilityAudit
set -eu

exec "$(dirname "$0")/ci.sh" ui-smoke "$@"
