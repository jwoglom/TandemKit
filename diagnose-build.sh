#!/bin/bash

set -euo pipefail

echo "=== TandemKit Build Diagnostic ==="
echo ""

echo "1. Checking Carthage installation..."
if command -v carthage &> /dev/null; then
    echo "   ✓ Carthage found: $(carthage version)"
else
    echo "   ✗ Carthage not found. Please install from: https://github.com/Carthage/Carthage"
    exit 1
fi

echo ""
echo "2. Checking for Carthage directory..."
if [ -d "Carthage" ]; then
    echo "   ✓ Carthage directory exists"
    echo "   Contents:"
    ls -la Carthage/ || true
else
    echo "   ✗ Carthage directory not found"
fi

echo ""
echo "3. Checking for required xcframeworks..."
if [ -d "Carthage/Build/LoopKit.xcframework" ]; then
    echo "   ✓ LoopKit.xcframework found"
else
    echo "   ✗ LoopKit.xcframework not found at Carthage/Build/LoopKit.xcframework"
fi

if [ -d "Carthage/Build/LoopKitUI.xcframework" ]; then
    echo "   ✓ LoopKitUI.xcframework found"
else
    echo "   ✗ LoopKitUI.xcframework not found at Carthage/Build/LoopKitUI.xcframework"
fi

echo ""
echo "4. Searching for xcframeworks in Carthage directory..."
if [ -d "Carthage" ]; then
    find Carthage -name "*.xcframework" -type d 2>/dev/null | while read -r framework; do
        echo "   Found: $framework"
    done
fi

echo ""
echo "5. Checking Carthage/Build structure..."
if [ -d "Carthage/Build" ]; then
    echo "   Contents of Carthage/Build:"
    ls -la Carthage/Build/ | head -20
else
    echo "   ✗ Carthage/Build directory not found"
fi

echo ""
echo "=== Diagnosis Complete ==="
echo ""
echo "If xcframeworks are missing, run:"
echo "  ./carthage.sh update --platform iOS,macOS --use-xcframeworks"
echo ""
echo "Note: The --use-xcframeworks flag should place frameworks in Carthage/Build/"
echo "      If they appear elsewhere, you may need to move them manually."
