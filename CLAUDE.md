@AGENTS.md

# Claude Code specifics

`AGENTS.md` (imported above) is the single source of truth for this project. Change rules there,
not here, so Codex and Freebuff see the same thing.

- Verification: `bash scripts/verify.sh`, or `VERIFY_JS_ONLY=1 bash scripts/verify.sh` when no
  JDK/SDK is installed. Paste the real result; `tests/ui.smoke.js`, `tests/preview.test.js` and
  `tests/browser.test.js` need dependencies this repo does not declare — report them as not run.
- The safety layer is the product: read `safety.js` and `tests/safety.test.js` before touching any
  tool path, and add a bypass test with every gate change.
- Do not commit to `release/` or `keystore/`, and do not run `git push` — CI owns those.
- Do not weaken `lint`, remove the `NOTICE`, or add npm dependencies.
