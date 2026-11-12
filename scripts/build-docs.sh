#!/usr/bin/env bash
# Build API documentation with doc-gen4 matching the repository's Lean release.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
toolchain=$(< lean-toolchain)
mkdir -p docbuild
cp lean-toolchain docbuild/lean-toolchain
cat > docbuild/lakefile.toml <<EOF
name = "docbuild"
reservoir = false
version = "0.1.0"
packagesDir = "../.lake/packages"

[[require]]
name = "godel-loeb"
path = "../"

[[require]]
scope = "leanprover"
name = "doc-gen4"
rev = "${toolchain#*:}"
EOF

(
  cd docbuild
  MATHLIB_NO_CACHE_ON_UPDATE=1 lake update godel-loeb
  lake build GodelLoeb:docs
)
mkdir -p public-docs/docs
cp -r docbuild/.lake/build/doc/. public-docs/docs/
