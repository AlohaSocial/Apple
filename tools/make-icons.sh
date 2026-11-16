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
# `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` expects (the list lives in
# Supporting/Aloha.xcconfig as ALOHA_ALTERNATE_APP_ICONS). Each set carries
# all three Home Screen appearances, so an alternate does not stay a light
# tile on a dark Home Screen, or lose the system tint when it is tinted.
# The colours match `AlohaIconVariant` in AlohaDesign.

# preview <in.svg> <image set name>
#
# What the Settings picker shows. An alternate icon is an *icon* in the
# catalog, which `UIImage(named:)` does not reliably hand back, so each one
# also goes out as an ordinary image at the size the picker draws it.
previews=$catalog/AppIconPreviews
preview() {
    preview_dir=$previews/$2.imageset
    mkdir -p "$preview_dir"
    render "$1" 180 "$preview_dir/$2.png"
    cat >"$preview_dir/Contents.json" <<EOF
{
  "images" : [
    { "filename" : "$2.png", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
}

# alternate <Name> <ground> <flower> <@> <dark ground> <dark flower> <dark @>
alternate() {
    name=$1
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
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon-1024-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon-1024-tinted.png",
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
    recolour "$2" "$3" "$4" "$work/$name.svg"
    render "$work/$name.svg" 1024 "$set_dir/icon-1024.png"
    recolour "$5" "$6" "$7" "$work/$name-dark.svg"
    render "$work/$name-dark.svg" 1024 "$set_dir/icon-1024-dark.png"
    # Tinted is luminance only, so every alternate shares the primary's.
    cp "$primary/icon-1024-tinted.png" "$set_dir/icon-1024-tinted.png"
    preview "$work/$name.svg" "AppIconPreview-$name"
}

preview "$work/aloha.svg" AppIconPreview-Aloha

# visionOS: the mark taken apart into the three layers a Vision Pro icon is
# made of, so the Home View can float them apart as it is looked at — the
# sand ground at the back, the flower in the middle, the @ in front. It is a
# stack of its own (AppIcon-Vision, chosen for the xros SDKs in the project);
# an iOS icon set does nothing on visionOS, which showed a placeholder.
vision_icon() {
    stack=$catalog/AppIcon-Vision.solidimagestack
    mkdir -p "$stack"
    cat >"$stack/Contents.json" <<'EOF'
{
  "info" : { "author" : "xcode", "version" : 1 },
  "layers" : [
    { "filename" : "Front.solidimagestacklayer" },
    { "filename" : "Middle.solidimagestacklayer" },
    { "filename" : "Back.solidimagestacklayer" }
  ]
}
EOF
    # The back layer is opaque; the two in front are cut out of nothing.
    vision_layer Back "$sand" none none RGB_8
    vision_layer Middle none "$coral" none RGBA_8
    vision_layer Front none none "$white" RGBA_8
}

# vision_layer <Layer> <ground> <flower> <@> <colour mode>
vision_layer() {
    layer=$stack/$1.solidimagestacklayer
    mkdir -p "$layer/Content.imageset"
    cat >"$layer/Contents.json" <<'EOF'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
    cat >"$layer/Content.imageset/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "layer.png", "idiom" : "vision", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
    recolour "$2" "$3" "$4" "$work/vision-$1.svg"
    render "$work/vision-$1.svg" 1024 "$layer/Content.imageset/layer.png" "$5"
}

# The colourways' dark appearance: a near-black ground, so every flower
# colour sits on it the same way.
night='#17191C'

# The colourways: the flower recoloured on the sand ground.
for colourway in Ocean:#1C78C7 Forest:#218054 Grape:#784ABF Rose:#D13D73 Slate:#546173; do
    name=${colourway%%:*}
    flower=${colourway#*:}
    alternate "$name" "$sand" "$flower" "$white" "$night" "$flower" "$white"
done

# Midnight: the primary's own dark appearance, chosen for every appearance.
alternate Midnight '#082A33' "$coral" "$white" '#082A33' "$coral" "$white"

# Coral: the colours turned inside out — a coral tile with a sand flower,
# and the @ cut back to the tile.
alternate Coral "$coral" "$sand" "$coral" '#9E3A2A' "$sand" '#9E3A2A'

# Mono: graphite and paper, nothing else — the one-colour mark on a tile.
alternate Mono '#F4F4F2' '#1F1F21' '#F4F4F2' '#1F1F21' '#F4F4F2' '#1F1F21'

vision_icon

echo "icons written"
