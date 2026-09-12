#!/bin/sh
# Package the plugin as a .deb. Assumes the .so is already built (via
# compile-plugin.sh or equivalent). Emits the path to the .deb on stdout; all
# other output (cargo, dpkg-deb, log) goes to stderr.
#
# Args: <plugin-path>     e.g. audio/spotify
# Env:  TARGET (from cross-env.sh), GST_GIT_BRANCH
# Cwd:  the working tree containing gst-plugins-rs/<plugin>/
set -eu

PLUGIN="$1"
GST_SRC_DIR=gst-plugins-rs/$PLUGIN
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

"$SCRIPT_DIR/inject-deb-metadata.sh" "$GST_SRC_DIR" >&2

DEB_VERSION=$("$SCRIPT_DIR/compose-version.sh" --deb "$GST_SRC_DIR")
echo "Building .deb version: $DEB_VERSION" >&2

# Must specify --target despite --no-build, else cargo-deb looks in the
# workspace for the asset (see comment in compile-plugin.sh).
(cd "$GST_SRC_DIR" && cargo deb --target="$TARGET" --no-build --deb-version "$DEB_VERSION" -v) >&2

DEB_FILE=$(find "gst-plugins-rs/target/$TARGET/debian"/*.deb)

# cargo-deb ends DEBIAN/control with a blank line, because it adds a newline
# after the description, which the description already has. A tool that reads
# the control file with "dpkg-deb -I <deb> control" and then adds fields of its
# own, such as "sbuild --extra-package", makes a second paragraph that has no
# "Package:" field, and apt stops with "Encountered a section with no Package:
# header". Remove the blank line.
UNPACK_DIR=$(mktemp -d)
chmod 755 "$UNPACK_DIR"  # mktemp gives 0700, and that mode goes into the .deb.
dpkg-deb --raw-extract "$DEB_FILE" "$UNPACK_DIR" >&2
printf '%s\n' "$(cat "$UNPACK_DIR/DEBIAN/control")" > "$UNPACK_DIR/DEBIAN/control.new"
mv "$UNPACK_DIR/DEBIAN/control.new" "$UNPACK_DIR/DEBIAN/control"
dpkg-deb --root-owner-group --build "$UNPACK_DIR" "$DEB_FILE" >&2
rm -rf "$UNPACK_DIR"

dpkg-deb --field "$DEB_FILE" Package Architecture Version Installed-Size >&2

printf '%s\n' "$DEB_FILE"
