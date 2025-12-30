#!/bin/bash
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Build Script
#
# Creates a flashable Magisk module ZIP
#
##########################################################################################

set -e

# Configuration
MODULE_NAME="custos"
VERSION=$(grep "^version=" module.prop | cut -d'=' -f2)
OUTPUT_DIR="./release"
OUTPUT_FILE="${OUTPUT_DIR}/${MODULE_NAME}-${VERSION}.zip"

echo "========================================"
echo "Building Custos Module ${VERSION}"
echo "========================================"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Remove old build
rm -f "$OUTPUT_FILE"

# Files and directories to include
INCLUDE_FILES=(
    "META-INF"
    "common"
    "config"
    "docs"
    "module.prop"
    "customize.sh"
    "service.sh"
    "post-fs-data.sh"
    "sepolicy.rule"
    "uninstall.sh"
    "README.md"
)

echo "Creating ZIP archive..."

# Create the ZIP
zip -r9 "$OUTPUT_FILE" "${INCLUDE_FILES[@]}" \
    -x "*.git*" \
    -x "*__pycache__*" \
    -x "*.pyc" \
    -x "*.DS_Store" \
    -x "build.sh" \
    -x "release/*"

echo ""
echo "========================================"
echo "Build complete!"
echo "Output: $OUTPUT_FILE"
echo "Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo "========================================"

# Verify ZIP contents
echo ""
echo "ZIP contents:"
unzip -l "$OUTPUT_FILE"

# Generate SHA256 checksum
sha256sum "$OUTPUT_FILE" > "${OUTPUT_FILE}.sha256"
echo ""
echo "SHA256: $(cat "${OUTPUT_FILE}.sha256")"

