#!/usr/bin/env python3
"""Fail unless a test run shows tests actually ran.

An .xctest bundle with no test cases in it passes; that is how TandemKitTests once sat broken
behind an empty Sources build phase. Reads either an xcodebuild / swift test log, where the
aggregate "Executed N tests" line is the largest one, or with --xunit the report that
`swift test --parallel --xunit-output` writes, since a parallel run prints no such line.

Usage: check-test-count.py LOG --label NAME [--no-skips]
       check-test-count.py --xunit REPORT --label NAME
"""
import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

SUMMARY = re.compile(
    r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures? \((\d+) unexpected\)"
)

parser = argparse.ArgumentParser()
parser.add_argument("log", nargs="?")
parser.add_argument("--xunit", metavar="REPORT")
parser.add_argument("--label", required=True)
parser.add_argument("--no-skips", action="store_true", help="fail if any test was skipped")
args = parser.parse_args()
if bool(args.log) == bool(args.xunit):
    parser.error("give exactly one of LOG or --xunit REPORT")
if args.xunit and args.no_skips:
    parser.error("--no-skips needs a log: SwiftPM's xunit report records a skipped test as passed")

if args.xunit:
    suites = ET.parse(args.xunit).getroot().iter("testsuite")
    totals = [(int(s.get("tests", 0)), int(s.get("failures", 0)) + int(s.get("errors", 0))) for s in suites]
    executed, failures = (sum(t[0] for t in totals), sum(t[1] for t in totals))
    line = f"{args.label}: {executed} tests executed, {failures} failures (parallel; skips not reported)."
else:
    with open(args.log, errors="replace") as f:
        runs = [tuple(int(g or 0) for g in m) for m in SUMMARY.findall(f.read())]
    if not runs:
        sys.exit("Could not find an 'Executed N tests' line in the test output. "
                 "Either the tests did not run or the reporting format changed.")
    executed, skipped, failures, unexpected = max(runs)
    if args.no_skips and skipped:
        sys.exit(f"{args.label}: {skipped} of {executed} tests were skipped.")
    line = f"{args.label}: {executed} tests executed, {skipped} skipped, {failures} failures ({unexpected} unexpected)."

if executed == 0:
    sys.exit(f"{args.label}: the test bundle ran 0 tests.")
print(line)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
        f.write(line + "\n")
