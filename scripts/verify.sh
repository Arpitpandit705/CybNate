#!/usr/bin/env bash
# Single verification command for every agent harness (Freebuff, Codex, Claude Code).
# Usage: bash scripts/verify.sh              -> JS tests + Gradle unit test + debug build
#        VERIFY_JS_ONLY=1 bash scripts/verify.sh   -> JS tests only (no JDK/SDK needed)
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v node >/dev/null 2>&1; then
  echo "verify: FAIL - node is not installed (Needs Node 20+)." >&2
  exit 2
fi

echo "verify: node $(node --version)"
echo "verify: node tests/core.test.js"
node tests/core.test.js
echo "verify: node tests/safety.test.js"
node tests/safety.test.js

if [[ "${VERIFY_JS_ONLY:-0}" == "1" ]]; then
  echo "verify: OK - JS tests passed (ui/preview/browser tests need jsdom/puppeteer; not declared in this repo)."
  exit 0
fi

if [[ -z "${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-}" ]] || ! command -v gradle >/dev/null 2>&1; then
  echo "verify: JS tests passed, but the Android gate did not run:" >&2
  echo "verify: needs JDK 17, the Android SDK (compileSdk 34) and 'gradle' on PATH." >&2
  echo "verify: run VERIFY_JS_ONLY=1 to accept the JS-only result, or install the toolchain." >&2
  exit 3
fi

# The Pyodide runtime is fetched at build time and is not committed.
if [[ ! -f app/src/main/assets/www/vendor/pyodide/pyodide.asm.wasm ]]; then
  echo "verify: fetching the pinned Python runtime"
  bash scripts/fetch-vendor.sh
fi

echo "verify: gradle :app:testReleaseUnitTest :app:assembleDebug"
gradle --no-daemon :app:testReleaseUnitTest :app:assembleDebug

echo "verify: OK - JS tests, Gradle unit test and debug build passed (device behaviour is NOT covered)."
