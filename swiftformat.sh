#!/bin/bash

# Get list of staged .swift files
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\\.swift$')

if [ -n "$FILES" ]; then
    echo "Running SwiftFormat on staged Swift files..."
    for FILE in $FILES; do
        swiftformat "$FILE"
        git add "$FILE" # Re-add the file to staging after formatting
    done
    echo "Swift files formatted and re-staged."
fi
