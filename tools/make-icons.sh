#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Writes every app icon from the Aloha Social mark — the "@ stamen hibiscus"
# from https://github.com/AlohaSocial/Logos.
#
#   sh tools/make-icons.sh
#
# Needs Inkscape (`brew install --cask inkscape`). The source SVG is checked in
# under tools/icon-source so the colourways are recoloured from one drawing; the
# PNGs it writes are committed because Xcode needs them at build time.

set -eu

cd "$(dirname "$0")/.."

source_svg=tools/icon-source/app-icon.svg
catalog=AlohaSocial/Assets.xcassets
primary=$catalog/AppIcon.appiconset
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The colours in the source drawing.
sand='#FBF4EA'
coral='#E8604C'
white='#FFFFFF'

# recolour <ground> <flower> <at> <out.svg>
#
# Through placeholders, so one substitution never rewrites another's result
# (the tinted icon turns the flower white, which is the @'s colour).
recolour() {
    sed -e "s/fill=\"$sand\"/fill=\"@GROUND@\"/" \
        -e "s/fill=\"$coral\"/fill=\"@FLOWER@\"/" \
        -e "s/fill=\"$white\"/fill=\"@AT@\"/" \
        -e "s/@GROUND@/$1/" -e "s/@FLOWER@/$2/" -e "s/@AT@/$3/" \
        "$source_svg" >"$4"
}

# render <in.svg> <pixels> <out.png> [RGB_8|RGBA_8]
#
# iOS icons are opaque squares (the system rounds them), so they go out
# without an alpha channel; App Store Connect rejects one that has it.
render() {
    inkscape "$1" --export-type=png --export-filename="$3" \
        --export-width="$2" --export-height="$2" \
        --export-png-color-mode="${4:-RGB_8}" >/dev/null 2>&1
}

# The primary icon, in the three appearances iOS asks for.
recolour "$sand" "$coral" "$white" "$work/aloha.svg"
render "$work/aloha.svg" 1024 "$primary/icon-1024.png"

# Dark: the same mark on a deep-sea ground — not a different drawing.
recolour '#082A33' "$coral" "$white" "$work/dark.svg"
render "$work/dark.svg" 1024 "$primary/icon-1024-dark.png"

# Tinted: the system supplies the colour from luminance, so the flower is white
# on black and the @ is cut back to the ground, as in the one-colour mark.
recolour '#000000' '#FFFFFF' '#000000' "$work/tinted.svg"
render "$work/tinted.svg" 1024 "$primary/icon-1024-tinted.png"

# macOS does not round icons itself: the artwork is a rounded square inset in a
# transparent canvas, as Apple's macOS icon grid lays it out (824 of 1024).
sed -e 's/<rect width="1024" height="1024"/<rect width="1024" height="1024" rx="185"/' \
    -e 's/<rect /<g transform="translate(100 100) scale(0.8046875)"><rect /' \
    -e 's/<\/svg>$/<\/g><\/svg>/' \
    "$work/aloha.svg" >"$work/mac.svg"
for size in 16 32 128 256 512; do
    render "$work/mac.svg" "$size" "$primary/mac-$size.png" RGBA_8
    render "$work/mac.svg" $((size * 2)) "$primary/mac-$size@2x.png" RGBA_8
done

# Alternates are their own icon sets in the same catalog, which is what
# `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` expects. Each recolours the
# flower; the colours match `AlohaIconVariant.swatch`.
for colourway in Ocean:#1C78C7 Forest:#218054 Grape:#784ABF Rose:#D13D73 Slate:#546173; do
    name=${colourway%%:*}
    flower=${colourway#*:}
    set_dir=$catalog/AlohaIcon-$name.appiconset
    mkdir -p "$set_dir"
    cat >"$set_dir/Contents.json" <<'EOF'
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
    recolour "$sand" "$flower" "$white" "$work/$name.svg"
    render "$work/$name.svg" 1024 "$set_dir/icon-1024.png"
done

echo "icons written"
