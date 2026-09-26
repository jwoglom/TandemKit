#!/usr/bin/env python3
"""Fail unless an xcodebuild test log shows tests actually ran.

An .xctest bundle with no test cases in it passes; that is how TandemKitTests once sat broken
behind an empty Sources build phase. The aggregate "Executed N tests" line is the largest one.

Usage: check-test-count.py LOG --label NAME [--no-skips]
"""
import argparse
import os
import re
import sys

SUMMARY = re.compile(
    r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures? \((\d+) unexpected\)"
)

parser = argparse.ArgumentParser()
parser.add_argument("log")
parser.add_argument("--label", required=True)
parser.add_argument("--no-skips", action="store_true", help="fail if any test was skipped")
args = parser.parse_args()

with open(args.log, errors="replace") as f:
    runs = [tuple(int(g or 0) for g in m) for m in SUMMARY.findall(f.read())]
if not runs:
    sys.exit("Could not find an 'Executed N tests' line in the xcodebuild output. "
             "Either the tests did not run or xcodebuild changed its reporting format.")
executed, skipped, failures, unexpected = max(runs)
if executed == 0:
    sys.exit(f"{args.label}: the test bundle ran 0 tests.")
if args.no_skips and skipped:
    sys.exit(f"{args.label}: {skipped} of {executed} tests were skipped.")

line = f"{args.label}: {executed} tests executed, {skipped} skipped, {failures} failures ({unexpected} unexpected)."
print(line)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
        f.write(line + "\n")
