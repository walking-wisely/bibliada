#!/bin/bash
# Compiles the pure-logic half of Shared/ into a throwaway CLI and runs
# scripts/smoke/pool-smoke.swift against it.
#
# There is no XCTest target in this project, and a full ./build.sh proves only
# that things compile — not that the reference parser understands "1Cor13:4-7".
# This is the cheap check for that: it takes a couple of seconds and needs no
# signing, no simulator, and no App Group.
#
# Only files with no AppKit/SwiftUI/App Group dependency can go in SOURCES;
# anything touching UserDefaults suites or NSWindow belongs in a real build.
#
# Usage: scripts/smoke/run.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

SOURCES=(
  Shared/BibleCanon.swift
  Shared/VersePool.swift
  Shared/VersePoolResolver.swift
  Shared/ReferenceParser.swift
  Shared/TranslationCatalog.swift
  Shared/Verse.swift
  Shared/Translation.swift
  Shared/PoolDocument.swift
  Shared/PoolTextFormat.swift
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Swift only allows top-level statements in a file literally named main.swift.
cp "${SOURCES[@]}" "$WORK/"
cp scripts/smoke/pool-smoke.swift "$WORK/main.swift"
# Bundle(for:) in a plain CLI resolves to the executable's directory, so the
# resources have to sit next to the binary for the canon/corpus to load.
cp Shared/Resources/canon.json Shared/Resources/curated-references.json "$WORK/"
mkdir -p "$WORK/Translations"
cp Shared/Resources/Translations/*.json "$WORK/Translations/"

swiftc -O -o "$WORK/pool-smoke" "$WORK"/*.swift
(cd "$WORK" && ./pool-smoke)
