#!/bin/sh
# Build release archives for ibm-monitoring-integration v6 configpack.
#
# Usage: ./build-release.sh [version]
#   e.g. ./build-release.sh v2.1
#
# If version is not specified, it is read from src/configpacks/v6/VERSION.
#
# Produces in ./dist/:
#   ibm-monitoring-integration.zip
#   ibm-monitoring-integration.tar.gz
#
# Archive filenames are intentionally unversioned so that release asset
# download URLs stay consistent across releases.
#
# Compatible with macOS (BSD tar/zip) and Linux (GNU tar/zip).

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_DIR="$SCRIPT_DIR/src/configpacks/v6"

VERSION="$1"
if [ -z "$VERSION" ]; then
    VERSION_FILE="$SCRIPT_DIR/VERSION"
    if [ ! -f "$VERSION_FILE" ]; then
        echo "ERROR: no version argument and $VERSION_FILE not found."
        exit 1
    fi
    VERSION=$(cat "$VERSION_FILE")
fi
echo "Building version $VERSION ..."
DIST_DIR="$SCRIPT_DIR/dist"
ARCHIVE_NAME="instana-v6-configpack"
STAGE_DIR="$DIST_DIR/stage"

# Verify source files exist
for f in agent2server_itm.sh agent2server_itm.bat env.properties Readme; do
    if [ ! -f "$SRC_DIR/$f" ]; then
        echo "ERROR: expected file not found: $SRC_DIR/$f"
        exit 1
    fi
done

# Clean and create staging area
rm -rf "$DIST_DIR"
mkdir -p "$STAGE_DIR"

# Copy files into staging directory
cp "$SRC_DIR/agent2server_itm.sh"  "$STAGE_DIR/"
cp "$SRC_DIR/agent2server_itm.bat" "$STAGE_DIR/"
cp "$SRC_DIR/env.properties"       "$STAGE_DIR/"
cp "$SRC_DIR/Readme"               "$STAGE_DIR/"
printf "\nVersion: %s\n" "$VERSION" >> "$STAGE_DIR/Readme"

# Ensure correct permissions on the shell script
chmod 755 "$STAGE_DIR/agent2server_itm.sh"

echo "Staged files:"
ls -l "$STAGE_DIR"
echo ""

# --- ZIP ---
# -X strips macOS extended attributes (__MACOSX/ folder) on BSD zip
# Files are placed at archive root (no subdirectory) to match prior releases.
ZIP_FILE="$DIST_DIR/${ARCHIVE_NAME}.zip"
cd "$STAGE_DIR"
zip -X -r "$ZIP_FILE" .
echo "Created: $ZIP_FILE"

# --- TAR ---
# Use ustar format on both macOS and Linux to prevent extended attribute headers
# (e.g. com.apple.provenance) that cause warnings on Linux tar.
# COPYFILE_DISABLE=1 also suppresses macOS ._resource fork files.
# Files are placed at archive root (no subdirectory) to match prior releases.
TAR_FILE="$DIST_DIR/${ARCHIVE_NAME}.tar"
cd "$STAGE_DIR"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$TAR_FILE" .
echo "Created: $TAR_FILE"

# Clean up staging directory
rm -rf "$STAGE_DIR"

echo ""
echo "Done. Archives in $DIST_DIR:"
ls -lh "$DIST_DIR"
