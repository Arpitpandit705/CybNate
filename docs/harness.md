# Harness setup

CybNate is itself a harness. This file covers two things: how other coding-agent harnesses work
on this repository, and how to make Codex and Claude Code first-class harnesses *inside* the app.

## Part 1 — Working on this repo with any harness

| Harness | Reads | So the repo has |
| --- | --- | --- |
| Freebuff / Codebuff | `AGENTS.md` (falls back to `CLAUDE.md`) | `AGENTS.md` |
| OpenAI Codex CLI | `AGENTS.md`, layered from the repo root down | `AGENTS.md` |
| Claude Code | `CLAUDE.md`, which imports `@AGENTS.md` | `CLAUDE.md` |

One rule file, one gate:

```bash
bash scripts/verify.sh                    # JS tests + Gradle unit test + debug build
VERIFY_JS_ONLY=1 bash scripts/verify.sh   # JS tests only
```

`.claude/settings.json` allows those commands and denies `git push`, `git add -f` on `release/`
and `keystore/`, and reads of the signing key. Project settings apply once Claude Code trusts the
directory.

The gap this closes: CybNate already reads a workspace `AGENTS.md`/`CLAUDE.md` for the *user's*
projects (`extraPrompt()` in `app.js`), but the repository had no instructions of its own — so
every harness writing CybNate started from zero.

## Part 2 — Codex and Claude Code as harnesses inside the app

You cannot run either binary on Android: both are Node/Python CLI programs with a real shell.
What you can do is treat a harness as **a model plus a protocol**, and keep CybNate's tool layer
(the part that is actually security-sensitive) shared. That is the same split Freebuff documents:
model, agent, tool, runtime are four separate layers.

### The adapter

Today one function, `chatStream`, speaks the OpenAI chat-completions dialect to every provider.
The change is to make the dialect a value, not a hardcoded shape:

```js
// core.js
const HARNESSES = {
  native:    { dialect: 'xml',       label: 'CybNate' },
  openai:    { dialect: 'openai',    chatUrl: '…/chat/completions', tools: 'functions' },
  anthropic: { dialect: 'anthropic', chatUrl: 'https://api.anthropic.com/v1/messages',
               headers: (k) => ({ 'x-api-key': k, 'anthropic-version': '2023-06-01' }) },
  codex:     { dialect: 'openai',    label: 'Codex',  remote: true },   // via MCP or a bridge
  claude:    { dialect: 'anthropic', label: 'Claude', remote: false },
};
```

Each harness supplies four things and nothing else:

1. `buildBody(msgs, tools)` — the wire shape. Anthropic puts the system prompt in a top-level
   `system` field, uses `tools[].input_schema`, and returns `content[]` blocks; OpenAI/Codex uses
   `messages[]` with `tools[].function.parameters`.
2. `stream(text)` → deltas — reuse the SSE parser, it is already generic.
3. `parseCalls(text)` — the existing `parseToolCalls` for the XML dialect; `tool_calls` for
   OpenAI; `tool_use` blocks for Anthropic.
4. `finishReason` handling — `tool_use` and `tool_calls` both mean "run tools and continue".

Everything after parsing stays exactly as it is: `runTools` → `Safety.approveEdits` /
`ensureApproved` → `ShellRunner` → `wrapUntrusted` → checkpoint. **A new harness must not get its
own tool executor**, or the approval gate stops being the single choke point. Add a test in
`tests/safety.test.js` that a harness-routed shell call still prompts.

Then the picker becomes `agent × harness × model`, and `buildSystemPrompt` gets one small
per-harness preamble instead of one global prompt.

### Remote harnesses

Codex and Claude Code can be driven non-interactively on a real machine:

- Codex — `codex exec "<task>"` for a headless run; `codex mcp-server` exposes Codex itself as an
  MCP server.
- Claude Code — `claude -p "<task>"` (add `--output-format json`), with `.claude/agents/*.md` for
  named subagents.

On the phone the practical route is a thin bridge on the user's PC (`codex exec` / `claude -p`
behind a local HTTP endpoint), reached from the app as one more tool. That needs an MCP client in
`core.js` plus a pairing/token flow — `usesCleartextTraffic` already allows the LAN call, which is
also why a paired bridge must be opt-in and token-authenticated.

### Order to build it in

1. Extract `buildBody`/`parseCalls` from `chatStream`; no behaviour change, tests stay green.
2. Add the Anthropic dialect and one real Claude model behind it — proves the abstraction.
3. Add a `harness` field to sessions so a chat keeps its dialect across restarts.
4. Only then add a remote/MCP bridge, with the approval gate still in front of every tool.

Until step 2 lands, "Codex/Claude as a harness" in CybNate means *their models through an
OpenAI-compatible endpoint*, which the Custom provider and Anthropic-compatible gateways already
allow today — the loop and tools are CybNate's own.
