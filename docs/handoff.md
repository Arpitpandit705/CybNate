# CybNate — review, corrections, and open work

If you are an agent (Freebuff, Codex, Claude Code) reading this to work on the repository: read
`AGENTS.md` for the rules, then this file for the state of the work.

- **Verify with:** `bash scripts/verify.sh` (or `VERIFY_JS_ONLY=1 bash scripts/verify.sh` without
  a JDK/Android SDK), `npm test`, `gradle :app:testReleaseUnitTest :app:assembleDebug`
- **Do not:** commit signing material, push from an agent session, weaken `safety.js` rules or
  tests, add npm runtime dependencies to the app, or touch `release/` by hand

---

## 1. What this project is

CybNate is a free AI coding agent that runs on an Android phone: a WebView hosts the agent and
UI, Java provides the shell, file bridge, native HTTP and an isolated preview.

- Agents: `coder`, `planner`, `reviewer`, `reverse`, `chat`; sub-agents `explorer`, `thinker`,
  `reviewer`, `researcher` through `spawn_agent`
- Tools: XML tags in the reply, with OpenAI-style function definitions offered alongside; both
  routes run through `runTools`
- Safety: permission modes, read-only command list, sensitive-path rules, approval gate,
  `untrusted_data` wrapping, checkpoints — enforced in `safety.js`, not in the prompt
- Runtimes: Android toybox shell, CPython 3.14 via Pyodide, a small JS runtime
- Models: Pollinations (keyless), OpenRouter, Groq, Gemini, any OpenAI-compatible endpoint

The agent loop is modelled on Freebuff's documented loop (investigate → plan → edit → run →
review → summarise). It is not a copy of Freebuff code; see `NOTICE`.

## 2. What was wrong, and what changed

| # | Problem | Severity | Correction |
|---|---|---|---|
| 1 | `keystore/cybnate.jks` **and its password** were committed (`app/build.gradle`, workflow) | Critical — anyone with the repo could sign an update for existing installs | Key removed from the tree and gitignored (`keystore/`); `app/build.gradle` reads `CYBNATE_KEYSTORE_PATH`, `CYBNATE_STORE_PASSWORD`, `CYBNATE_KEY_ALIAS`, `CYBNATE_KEY_PASSWORD`; CI restores the key from the `CYBNATE_KEYSTORE_BASE64` secret and falls back to debug signing (which cannot update an installed app) when it is absent |
| 2 | No licence file although `NOTICE` credits Apache-2.0 text from Codebuff/Freebuff | Legal | `LICENSE` (Apache-2.0) added |
| 3 | No `package.json`, so `ui.smoke.js` / `preview.test.js` could not run without guessing `NODE_PATH`, and CI ran only two of six suites | Reproducibility | `package.json` + `package-lock.json` added with `npm test`, `test:ui`, `test:preview`, `test:browser`, `verify` scripts and `jsdom` as the single dev dependency |
| 4 | `spawn_agent` / `web_search` / `read_url` batches ran unbounded in parallel — twenty spawn tags meant twenty streams on one API key | Reliability | `MAX_PARALLEL = 6` cap in `runTools` (`core.js`), matching Freebuff's documented six per spawn call |
| 5 | Every harness writing this repo started from zero: it reads a workspace `AGENTS.md` for the *user's* projects, but the repo had none of its own | Agent harness | `AGENTS.md`, `CLAUDE.md` (imports `@AGENTS.md`), `.claude/settings.json`, `scripts/verify.sh`, `docs/harness.md` added |
| 6 | CI committed the key alongside every APK | Critical (same as #1) | Workflow no longer `git add -f`s `keystore/`; the key only exists for the duration of the job |

## 3. Still open — with the reason and the shape of the fix

1. **Lint gate is switched off.** `app/build.gradle` has `lint { abortOnError false;
   checkReleaseBuilds false }`. Correct fix: run `gradle :app:lintRelease`, fix what it reports,
   then set both to `true`. Left as-is because turning it on blind would break the release build.
2. **No context compression.** `trimHistory(msgs, budget)` keeps the newest messages until the
   character budget is full and then stops; older context is dropped, not summarised. Freebuff
   compresses history into a summary that keeps the goal, decisions, state and files. Fix: replace
   the cut with a summary call when history is dropped, and keep the todos and the current plan
   pinned outside the trimmed window.
3. **No MCP client.** `docs/harness.md` describes the adapter route (`HARNESSES` with
   `buildBody` / `stream` / `parseCalls` per dialect) and the remote route (`codex exec`,
   `codex mcp-server`, `claude -p`) for attaching Codex and Claude Code. The tool layer and gate
   stay shared, so a new harness cannot bypass approval.
4. **No Mission-mode equivalent.** There is no judge model that decides whether the run reached
   the goal; the loop stops on the step budget or when the model stops emitting tool tags.
5. **`usesCleartextTraffic="true"`.** Needed for LAN/Ollama, but a custom provider URL of `http://`
   would send an API key in the clear. Fix: allow cleartext only for private address ranges via a
   network security config.
6. **Release artefacts in git.** `release/CybNate.apk`, screenshots, `device-console.txt` and
   `model-raw.txt` are committed by CI. Fine for a portable download link; revisit before a store
   release (upload-artifact + GitHub Releases is the cleaner shape).
7. **`versionCode` comes from `GITHUB_RUN_NUMBER`.** Every local build is version 1 and cannot
   update a sideloaded install.
8. **API keys live in WebView storage.** Acceptable for a no-account app, but
   EncryptedSharedPreferences + Android Keystore is the stronger option. Masking only covers
   printed output, not what an approved command can send.
9. **Device-only behaviour is proven only by the emulator self test.** Shell, Pyodide, the native
   bridge, the approval sheet and the preview WebView are covered by `release/selftest.txt`
   (currently pass=27, fail=0), not by `scripts/verify.sh`. Keep that distinction in reports.

## 4. How the harness files fit together

| File | Read by | Purpose |
|---|---|---|
| `AGENTS.md` | Freebuff, Codex | Layout, the gate, hard rules, known gaps |
| `CLAUDE.md` | Claude Code | `@AGENTS.md` import plus Claude-specific notes |
| `.claude/settings.json` | Claude Code | Allows the gate; denies `git push`, `git add -f` on `release/`, key reads |
| `scripts/verify.sh` | all | JS tests, then Gradle unit test + debug build, with honest exit codes |
| `docs/harness.md` | humans and agents | The Codex / Claude Code adapter design |

## 5. Report format this repo expects

> What changed · which command ran and what it printed · what was not checked and why

A green compile is evidence about compilation. It is not evidence that the blocker-like behaviours
work, that the approval gate covers a new route, or that the emulator self test passed.
