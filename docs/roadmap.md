# CybNate — problems, gaps, and the plan

This document answers four questions: what is wrong with the project today, what is missing,
where each missing piece comes from, and how to grow it into something other people can sign in
to and use — the way Codebuff, Codex and Claude Code are built.

Read `AGENTS.md` for the rules an agent must follow, and `docs/handoff.md` for the review that
produced the corrections already in the repo.

---

## 1. Problems found, with the fix for each

### 1.1 Already fixed in this repository

| # | Problem | Why it mattered | Fix that is in the repo |
|---|---|---|---|
| 1 | The signing keystore **and its password** were committed | Anyone with the repo could build an APK signed with the same key, and Android installs it as an update over an existing CybNate. The app's update path was effectively public | `keystore/` is gitignored and deleted; `app/build.gradle` reads `CYBNATE_KEYSTORE_PATH` / `CYBNATE_STORE_PASSWORD` from the environment; CI restores the key from `CYBNATE_KEYSTORE_BASE64`; a build without secrets is debug-signed and cannot update an install |
| 2 | No `LICENSE`, although `NOTICE` credits Apache-2.0 text from Codebuff/Freebuff | Adapting text without shipping the licence is a compliance gap | Apache-2.0 `LICENSE` added |
| 3 | No `package.json`, so `ui.smoke.js` and `preview.test.js` could only run with a hand-made `NODE_PATH`, and CI ran two of six suites | The approval sheet and preview isolation were effectively untested in CI | `package.json` + `package-lock.json`, `npm test`, `jsdom` declared |
| 4 | `spawn_agent` / `web_search` / `read_url` ran with no parallel cap | Twenty spawn tags in one reply opened twenty streams on one API key — a rate-limit cascade that looks like "the model is broken" | `MAX_PARALLEL = 6` in `runTools` |
| 5 | The repository had no instructions for coding agents, even though the app reads a workspace `AGENTS.md` for users' projects | Every harness writing CybNate started from zero | `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `scripts/verify.sh` |

### 1.2 Still open

| # | Problem | Why it matters | Solution | Effort |
|---|---|---|---|---|
| 1 | **No context compression.** `trimHistory()` keeps the newest messages until a character budget is full, then stops. The oldest context is dropped, not summarised | A long run forgets the plan, the todos and the reason for earlier decisions — the model starts contradicting itself. Freebuff compresses history into a summary because this is the main long-task failure | Add a summarisation step when the budget is exceeded: keep the system prompt, the current todos and the last N messages, replace the rest with a running summary. Keep todos in a separate pinned field, not inside history | 1–2 days |
| 2 | **The lint gate is off.** `lint { abortOnError false; checkReleaseBuilds false }` | Gradle will never fail a release on a manifest or API error, so silent breakage ships | Run `gradle :app:lintRelease`, fix the report, then set both flags to `true` | 0.5 day + fixes |
| 3 | **`usesCleartextTraffic="true"`.** Needed for LAN/Ollama, but it also permits `http://` for any custom provider | A custom provider URL can send an API key in plaintext on a public network | Network security config that allows cleartext only for private ranges (`10/8`, `172.16/12`, `192.168/16`, `localhost`) | 2 hours |
| 4 | **No MCP client.** CybNate has tools but cannot consume external tool servers | MCP is how Codex, Claude Code, Cursor and Copilot share tools today. Without it CybNate is an island | Implement `search_mcp_tools` / `call_mcp_tool` behind the same approval gate, with an explicit server allowlist and a per-server prompt | 3–5 days |
| 5 | **One protocol dialect.** `chatStream` speaks OpenAI chat-completions only | Anthropic's native API (system prompt at top level, `tools[].input_schema`, `tool_use` blocks) cannot be used directly, so "Claude as a harness" today means "Claude through a gateway" | The `HARNESSES` adapter in `docs/harness.md`: `buildBody` / `stream` / `parseCalls` per dialect, with the tool executor and gate shared | 2–3 days |
| 6 | **No judge / mission mode.** The loop stops on the step budget or when the model stops emitting tags | Nothing checks that the goal was actually reached. Freebuff's Mission mode uses a second model to judge each turn | A `judge` run after each turn: given the goal and the transcript, answer continue / done / ask-user. Bound it to one cheap model call per turn | 2 days |
| 7 | **API keys live in WebView storage.** No Keystore, no EncryptedSharedPreferences | Any process that can read the app's data directory, or a rooted device, gets the keys. Masking only covers printed output | Store keys and secrets with Android Keystore–backed encryption; keep them out of checkpoints and out of any sync | 1 day |
| 8 | **No crash reporting or usage signal.** A failure on a user's phone is invisible | You cannot fix what you cannot see, and users just leave | Firebase Crashlytics (small, free) or Sentry; log the provider, model and step count, never prompts or keys | 0.5 day |
| 9 | **Release artefacts in git, `versionCode` from `GITHUB_RUN_NUMBER`** | Every local build is version 1 and cannot update a sideloaded install; the repo carries a 6.5 MB APK and screenshots | Keep the APK for now, move to GitHub Releases later; derive `versionCode` from a committed `version.properties` or the tag | 2 hours |
| 10 | **Device-only behaviour is proven only by the emulator self test** | The gate (`scripts/verify.sh`) proves JS logic and compilation, not the shell, Pyodide, the bridge, the approval sheet or the preview | Keep the distinction in every report; treat `release/selftest.txt` as the device evidence | ongoing discipline |

---

## 2. What is missing compared with a mature agent product

Judged against how Codebuff/Freebuff, Codex and Claude Code are actually assembled.

| Capability | CybNate today | What is missing |
|---|---|---|
| Agent loop | Yes — investigate, plan, edit, run, review, summarise | A judge that decides when the goal is met |
| Tools | Strong: files, shell, Python, JS, web, binary analysis | MCP client; a browser surface |
| Permission model | Better than most CLIs: three modes, sensitive-path rules, fail-closed gate, checkpoints | Policy persistence per project; an audit log of approved commands |
| Project context | Reads workspace `AGENTS.md`/`CLAUDE.md` | Nested/layered instructions (Codex layers `AGENTS.md` from the root down); `.cybnateignore` |
| Context management | Truncation only | Summarising compression and a pinned plan |
| Model layer | 5 providers, OpenAI-compatible, text-tag fallback | Native Anthropic dialect; capability matrix per model (tools, context window, vision); retry/backoff on 429/5xx |
| Extensibility | Skills | MCP servers; plugins |
| Surfaces | Android only | CLI, IDE extension, desktop, web, cloud |
| Accounts | None — one device, one user | Sign-in, cross-device sync, quotas |
| Distribution | APK committed by CI | Play Store listing, signed releases, update channel, privacy policy |
| Trust | Local-only, BYO key | Play Integrity / App Check, per-user quotas, abuse handling once a hosted key exists |

---

## 3. The structural idea that makes CLI and IDE cheap: one core, many hosts

`core.js` and `safety.js` already state in their own headers that they have **no DOM access and
are unit-tested under Node**, and both use a UMD wrapper (`module.exports` or a global). That is
the single most valuable property in this codebase: the agent core is already portable.

So the rule for every future surface is: **the core decides, the host executes.**

```
core.js        providers, agents, prompts, tool protocol, parsing     <- shared, no I/O
safety.js      modes, approval rules, read-only list, checkpoints     <- shared, no I/O
   ^
hosts:  Android (Java bridge)  ·  CLI (Node child_process + fs)  ·  VS Code (workspace.fs + terminal)
        Desktop (Tauri/Electron)  ·  Web/Cloud (container sandbox)
```

Each host implements only the four I/O primitives the core calls: `exec`, `search`, `readUrl`
and `spawn`, plus an approval UI. Everything else — prompts, parsing, gate decisions, tool docs —
is one implementation. This is exactly how Codebuff separates model / agent / tool / runtime, and
it is why adding a surface should take days, not a rewrite.

---

## 4. Connecting a CLI

**Goal:** `npx cybnate` in any project folder, on any OS.

1. New package `packages/cli` with `bin: { cybnate: "./bin.js" }`, private first, publish to npm
   later. It `require()`s `core.js` and `safety.js` straight from the app assets (or a copy made at
   build time) — no duplication.
2. Implement the host:
   - `exec` -> `child_process.spawn(shell, ['-c', cmd])` with cwd = project root, a timeout, and
     the same output clipping as `ShellRunner`.
   - `search` -> a ripgrep call, falling back to a JS scan.
   - `readUrl` -> `fetch` (Node 20 has it).
   - `spawn` -> a nested run of the same agent with its own history.
3. Implement approval in the terminal: the same `Safety.approvalFor` output, rendered as a
   `y/n/a` prompt with the diff (`Safety.lineDiff` already exists). The gate must be the same
   function the app uses — that is the point.
4. Checkpoints: copy changed files to `~/.cybnate/checkpoints/<ts>/` before a run, offer
   `cybnate undo`. (`git stash create` is an alternative, but do not require git.)
5. Config: `~/.config/cybnate/config.json` for provider/model, `chmod 600`; keys optionally in the
   OS keychain. Never in the project folder.
6. Auth (once accounts exist): a device-code flow like `gh auth login` — the CLI shows a code, the
   browser approves, the CLI receives a token.

**Cheapest first version:** a local-only CLI with BYO keys. It needs no backend at all, and it
turns CybNate from "an Android app" into "an agent with a terminal".

## 5. Connecting an IDE

Three routes, in ascending cost:

1. **MCP server (recommended first).** Add `cybnate mcp` that speaks MCP over stdio and exposes
   `list_files`, `read_file`, `write_file`, `edit_file`, `run_terminal_command`. Any MCP client —
   Cursor, Copilot, Claude Code, Codex — can then use CybNate's tools with its own model and UI.
   This is the cheapest interoperability in the ecosystem and it reuses the tool layer you already
   have. It also forces the tool schemas to be clean, which benefits the app.
2. **VS Code extension.** The extension host is Node, so it can reuse `core.js` directly:
   `vscode.workspace.fs` for files, `vscode.window.createTerminal` for commands, a webview panel
   that loads the existing `index.html`/`style.css`, and `showWarningMessage` for approvals.
   Publish with a Marketplace Personal Access Token.
3. **JetBrains plugin.** A Kotlin plugin with the same JS core is possible but expensive; do it
   only if users ask.

**Desktop** is the same shape as the CLI: a Tauri or Electron shell that loads `www/` and provides
the four primitives. Tauri is smaller; Electron is simpler if you want to reuse the WebView code.

---

## 6. Letting other people sign in — and later paying for it

Today CybNate is single-device and single-user by design: keys and chats live in WebView storage.
Making it a platform is a four-phase ladder, and each phase is useful on its own.

### Phase 0 — today, no accounts (keep this as a real product)

Local workspace, BYO key, no server, no privacy exposure. This should never be removed: it is the
privacy story and the zero-cost tier.

### Phase 1 — sign-in for sync (this is the "others can log in" step)

Users sign in with Google or email, and their projects, chats and settings sync across phone,
CLI and IDE. **No API keys are ever synced** — each device keeps its own.

- **Recommended backend: Supabase** — Auth (Google/email/magic link) + Postgres with row-level
  security + storage + edge functions, one project, generous free tier, SDKs for Android, web and
  Node. You already use Supabase in this workspace, and it maps onto the pattern you used with
  Firebase/Firestore in FocusStudy.
- Alternatives: Firebase Auth + Firestore (you know it; no SQL), Clerk (excellent auth DX, but you
  still need a database), Auth0/WorkOS (enterprise-shaped, heavier).
- Data model: `users(id)`, `projects(id, owner_id, name)`, `project_files(project_id, path, blob)`,
  `chats(id, project_id, messages jsonb)`, `devices(id, user_id, name, last_seen)`.
  Row-level security on every table keyed by `auth.uid()` — never trust a client-supplied owner id,
  the same rule your Firestore rules already enforce.

Security requirements for this phase:

- Tokens in EncryptedSharedPreferences / Keystore on Android, OS keychain in the CLI.
- RLS on every table, default deny, plus a policy test suite.
- Sign-out clears local tokens but keeps the local workspace.
- Nothing sensitive in the synced rows: no keys, no secrets, no shell history.

### Phase 2 — hosted inference (the "big company" part)

Right now every user must obtain their own key, which is the biggest drop-off in onboarding.

- Put a small gateway in front of the providers (Supabase Edge Function or a Cloudflare Worker).
  The gateway holds the provider keys, verifies the user's token, applies a per-user daily quota,
  and streams the response back.
- Keys never reach the phone; the APK contains no secret.
- Quotas live in a table/KV keyed by user and day; log usage counts only, never prompts.
- On Android, gate the gateway with **Play Integrity** (and Firebase App Check if you stay on
  Firebase) so a modified APK cannot farm your free tier.

### Phase 3 — money (deliberately deferred, but design for it now)

- Free tier: BYO key (costs you nothing) or a small daily quota through the gateway.
- Paid tier: larger quota, better models, sync history, team projects.
- Mobile billing: Google Play Billing (RevenueCat simplifies the cross-platform side).
- Web/CLI billing: Stripe Checkout + a webhook that writes the plan onto the user row.
- Keep the gateway's quota check as the single enforcement point, so plan logic never lives in
  the client.

**Where the money actually comes from:** inference margin (quota priced above provider cost),
sync/storage tiers, and team seats. Not ads — an ad inside a coding agent costs more trust than it
earns.

---

## 7. Roadmap, in the order that keeps risk low

| Phase | Work | Done when |
|---|---|---|
| A (now) | Context compression, lint gate, cleartext config, crash reporting, `versionCode` | `verify.sh` green including lint; a 50-step run still remembers its plan; crashes visible in a dashboard |
| B | MCP server (`cybnate mcp`) | Cursor or Claude Code can call CybNate's tools on a real project |
| C | CLI (`npx cybnate`), reusing `core.js` + `safety.js` | Same approval gate in a terminal; one real task completed end to end |
| D | Supabase auth + project/chat sync; keys stay local | Two devices, same account, same project; RLS test suite green |
| E | Hosted gateway + quotas + Play Integrity | A new user can use the app without any API key |
| F | Play Store release, privacy policy, billing | Installs from Play; paid tier enforced server-side |

Phase A is pure repair and should happen first. B and C add surfaces without touching the core.
D and E turn it into a platform. F is the business step you are deliberately postponing.

---

## 8. Honest costs and risks

- **Play Console:** $25 once. **Supabase:** free tier, then about $25/month. **Domain:** about
  $10/year. **Crash reporting:** free tiers are enough at the start.
- **The gateway is the only real cost centre** — every hosted call spends your money. Without a
  hard per-user quota and device attestation, a hostile user can burn it.
- **Shell on a user's machine is the sharpest edge.** Desktop/CLI must keep the same gate and
  should default to a workspace-only filesystem view.
- **Sync is a privacy decision.** Two people's code on one server means a privacy policy, a
  deletion path and encryption at rest. Do not sync secrets, ever.
- **Registry trust:** once you publish an npm CLI or a VS Code extension, your account becomes a
  supply-chain target. Use 2FA and scoped tokens.

## 9. The next five tasks, in order

1. Context compression in `core.js` (with a test that a long history keeps its goal).
2. Turn the lint gate on after one clean `:app:lintRelease`.
3. Private-range-only cleartext via network security config.
4. `cybnate mcp` — the smallest possible MCP server over stdio.
5. `packages/cli` with the Node host and terminal approvals.
