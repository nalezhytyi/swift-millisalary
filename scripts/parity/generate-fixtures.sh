#!/usr/bin/env bash
# Regenerates the MillisalaryCore parity fixture from the Electron app's
# TypeScript (the reference implementation). Needs node and a checkout of
# electron-millisalary with its node_modules installed; set
# ELECTRON_MILLISALARY when it isn't next to this repo. Only reads from it:
# the bundle is built and run in a temporary folder.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REF="$(cd "${ELECTRON_MILLISALARY:-$ROOT/../electron-millisalary}" && pwd)"
OUTPUT="$ROOT/Packages/MillisalaryCore/Tests/MillisalaryCoreTests/Fixtures/parity.json"
ESBUILD="$(ls -d "$REF"/node_modules/.pnpm/esbuild@*/node_modules/esbuild/bin/esbuild | sort -V | tail -1)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# dayjs resolves from the reference's node_modules, for both files
NODE_PATH="$REF/node_modules" "$ESBUILD" "$ROOT/scripts/parity/fixtures.ts" \
  --bundle --platform=node --format=cjs --log-level=warning \
  --alias:@shared="$REF/src/shared" \
  --alias:@renderer="$REF/src/renderer/src" \
  --outfile="$WORK/fixtures.cjs"

mkdir -p "$(dirname "$OUTPUT")"
node "$WORK/fixtures.cjs" "$OUTPUT" \
  "electron-millisalary@$(git -C "$REF" rev-parse --short HEAD)"
