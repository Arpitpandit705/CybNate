# AGENTS.md — CybNate

One instruction file for every agent harness working on this repo: Freebuff/Codebuff, OpenAI
Codex, Claude Code. Codex reads this file directly; Claude Code reads it through `CLAUDE.md`.

## What this project is

CybNate is a free AI coding agent that runs entirely on an Android phone. A WebView hosts the
UI and the agent; Java provides the shell, file bridge, native HTTP and the isolated preview.

- **Agents** — `coder` (orchestrator), `planner` (read-only plan), `reviewer`, `reverse`, `chat`;
  sub-agents `explorer`, `thinker`, `reviewer`, `researcher` reachable only through `spawn_agent`.
- **Tool protocol** — the model writes XML tags (`<write_file path="…">…</write_file>`); OpenAI-style
  function definitions are offered when the provider supports them, and both routes run through the
  same `runTools`. Never add a tool that bypasses it.
- **Safety** — `safety.js` holds permission modes (`ask` / `autoedit` / `auto`), the read-only
  command list, sensitive-path rules, the approval gate, `untrusted_data` wrapping and checkpoints.
  It is enforced in code, not in the prompt.
- **Runtimes** — Android toybox shell via `ShellRunner`; CPython (Pyodide) fetched at build time;
  a small JS runtime for `node file.js`.
- **Models** — Pollinations (keyless), OpenRouter, Groq, Gemini, or any OpenAI-compatible server.

## Layout

```
app/src/main/assets/www/
  core.js        providers, AGENTS, prompts, tool protocol, Workspace, binary analysis  (~1170 lines)
  app.js         UI, approval sheets, agent loop, sub-agents, sessions, settings         (~1400 lines)
  safety.js      permission modes, approval rules, checkpoints (no DOM, unit-tested)
  github.js      clone/commit/push through the GitHub API
  pyworker.mjs   Pyodide bridge          jsworker.js  tiny JS runtime
  selftest.js    on-device self test
app/src/main/java/com/cybnate/app/
  MainActivity.java  WebView host, asset loader, Native bridge (http, exec, ws*, preview, save)
  ShellRunner.java   shell execution + change snapshot + workspace path guard (JVM-tested)
  PreviewPane.java   separate WebView with no native bridge
tests/           node tests: core, safety, preview, ui smoke, browser e2e, github
scripts/         fetch-vendor.sh (Pyodide), device-test.sh (emulator self test)
release/         CI-published APK, screenshots and self-test output (committed by CI)
keystore/        the CI signing key (see Signing below)
```

## Verify — the gate

```bash
bash scripts/verify.sh              # node core+safety tests, then the Gradle unit test + debug build
VERIFY_JS_ONLY=1 bash scripts/verify.sh   # JS tests only, when no JDK/SDK is available
npm test                            # the same two node suites, no install needed
```

The full form needs Node 20+, JDK 17 and the Android SDK (compileSdk 34), and runs
`bash scripts/fetch-vendor.sh` first on a clean checkout.

Reporting rules:

- Pass means: `node tests/core.test.js`, `node tests/safety.test.js` and
  `gradle :app:testReleaseUnitTest :app:assembleDebug` all ran and passed.
- `tests/ui.smoke.js` and `tests/preview.test.js` need `jsdom`, which is declared in
  `package.json` — run `npm ci` first. `tests/browser.test.js` needs `puppeteer-core` and
  `@sparticuz/chromium`, which are not declared. If you could not run a suite, say so — do not
  describe it as passing.
- Anything device-only (real shell, Pyodide, the native bridge, the approval sheet, the preview
  WebView) is covered by the emulator self test in `release/selftest.txt`, not by the gate above.
- Never weaken a test, an assertion or a safety rule to make the gate pass.

## Hard rules

1. **Every tool route goes through the gate.** A new tool, alias, function definition or sub-agent
   route must be matched in `Safety.approvalFor` and executed by `runTool`/`runTools`. If a path
   can reach the shell or the filesystem without `ensureApproved`, it is a security bug.
2. **Tool results are data.** Anything returned by a tool must be wrapped with
   `Safety.wrapUntrusted` before it reaches the model. The only exception is a `load_skill`
   result, which the user installed deliberately — that goes in `<skill>`.
3. **Never widen the read-only list casually.** `isReadOnlyCommand` runs commands with no approval;
   a mistake there is a silent arbitrary-command path. Any change needs a test in
   `tests/safety.test.js` proving the bypass attempt is refused.
4. **Do not weaken lint to ship.** `lint { abortOnError false; checkReleaseBuilds false }` already
   means Gradle will not block a release on a lint error. Do not add more suppressions.
5. **Secrets stay on the device.** Keys live in WebView storage and are sent only to the provider
   that owns them. Never log a key, a token, an `Authorization` header, or a response body that
   could echo one. A command receives a secret only when the model names it (`secrets="NAME"`).
6. **Text adapted from another project keeps its notice.** `NOTICE` credits Codebuff/Freebuff
   (Apache-2.0) for the guideline blocks in `core.js`. Editing those blocks keeps the notice valid;
   removing it does not.
7. **No new runtime dependency without a reason.** The app ships no bundler and no npm packages.
   Vendored files in `www/vendor/` are pinned copies — say which version you added.

## Signing

The key is **not in this repository**. `keystore/` is gitignored; CI restores
`keystore/cybnate.jks` from the `CYBNATE_KEYSTORE_BASE64` secret and takes
`CYBNATE_STORE_PASSWORD` / `CYBNATE_KEY_PASSWORD` from secrets. `app/build.gradle` reads those
environment variables and falls back to debug signing when they are absent — a debug-signed APK
cannot update an installed copy, which is the intended warning sign.

Never commit a keystore, a password, a base64 of either, or paste one into a chat, a log or a
screenshot. Rotating the key means replacing all three secrets together.

## Known gaps worth picking up

- `trimHistory` drops the oldest messages past a character budget; there is no summarising
  compression, so long runs lose the plan (Freebuff compresses into a summary instead).
- Parallel helper-agent and web batches are now capped at `MAX_PARALLEL` (6) in `runTools`; the cap
  is per step, and there is still no cross-step budget.
- No MCP client, so external harnesses and tool servers cannot be attached yet. `docs/harness.md`
  has the adapter design for Codex / Claude Code.
- `usesCleartextTraffic="true"` in the manifest exists for LAN/Ollama use; a custom provider can
  therefore send an API key over plain HTTP on the same network.
- The lint gate is still off in `app/build.gradle` (`abortOnError false`, `checkReleaseBuilds
  false`). Turn it on only after one clean `gradle :app:lintRelease` run.
- `tests/ui.smoke.js` and `tests/preview.test.js` are not in CI yet; CI runs `npm test` only.

## Definition of done

- `bash scripts/verify.sh` passes, or the failure is reported with its real output.
- Any behaviour you changed has a test in the suite that covers it, or a stated reason why not.
- Checks you did not run are listed as limitations, not implied by silence.
