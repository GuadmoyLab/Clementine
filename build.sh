#!/bin/sh
# Builds the release binary: target/release/clementine
set -e
cd "$(dirname "$0")"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing build requirement: $1 ($2)" >&2; exit 1; }; }
need cargo "Rust toolchain, https://rustup.rs"
need qmake6 "Qt 6 development files, e.g. qt6-base qt6-declarative"

# Converters are runtime tools: warn, don't fail
for t in magick ffmpeg pdftoppm bsdtar; do
    command -v "$t" >/dev/null 2>&1 || echo "note: '$t' not found, the matching conversions will report an error" >&2
done

cargo build --release
echo "Built: $PWD/target/release/clementine"
