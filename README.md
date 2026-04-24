# Agentic Workflow

A structured, multi-agent software development workflow built on top of [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Three specialised AI agents — **Scrum Master**, **Developer**, and **Tester** — collaborate through a shared scrum board, an event-driven trigger queue, and a set of slash-command skills to take a project from idea to verified, committed code.

---

## How It Works

### Key Mechanisms

| Mechanism | Location | Purpose |
|---|---|---|
| Scrum board | `project/board/` | Epics, stories, tasks with structured frontmatter |
| Trigger queue | `project/queue/scrum_triggers.jsonl` | Async handoff to Scrum Master |
| Event log | `project/logs/events.json` | Append-only audit trail of all inter-agent events |
| Rapport system | `project/rapports/` | Problem and analysis reports written by Developer/Tester |
| File locking | `<file>.lock` adjacent to board files | Concurrency control for parallel agents |

---

## Workflow Lifecycle

1. **`/init`** — Scaffold the project: git init, directories, `workflow.json`, `PROJECT_SUMMARY.md` stub.
2. **`/jenga`** — Gather project description and goals from the user; define initial epics in `PROJECT_SUMMARY.md`.
3. **`/todo`** (or Scrum Master directly) — Translate requirements into board items (epics → stories → tasks).
4. **`/do`** — Pick a task from `project/todo.md`, invoke the Developer agent with full scrum board context and a sender object.
5. **Developer** — Reads task, creates a worktree, implements, commits, and calls the Tester.
6. **Tester** — Validates sender object, runs tests, writes status to the board, triggers rollup if all tasks pass.
7. **`SessionEnd` hook** — `on_session_end.sh` detects new rapports and writes triggers to the queue.
8. **Scrum Master** (next session) — Processes the queue: rapport review, status review, story/epic rollup.

---

## Agents

### Scrum Master (`agents/scrum_master.md`)

- **Owns** `project/PROJECT_SUMMARY.md` — sole writer.
- Processes `project/queue/scrum_triggers.jsonl` at every session start.
- Creates and amends epics, stories, and tasks using the scrum board schema.
- Handles story and epic rollup when all child items pass.
- Applies advisory file locks before writing any board file.

### Developer (`agents/developer.md`)

- Creates an isolated git worktree per task (`<E##_S##_T##-slug>`).
- Logs all incoming sender objects to `project/logs/events.json` before doing any work.
- Commits at meaningful milestones (not every line, not only at the end).
- Calls the Tester with a full sender object including commit SHAs.
- Never runs tests — that is the Tester's exclusive responsibility.
- After three failed conflict resolutions, writes a rapport, sets status to `Blocked`, and halts.
- Never commits `.env` files or credentials.

### Tester (`agents/tester.md`)

- **Sole agent** permitted to update task and story statuses on the board.
- Validates all required sender fields before proceeding (rejects with `"error"` if any are missing).
- Manages the full testing lifecycle: unit, integration, e2e, SAST, vulnerability, performance, coverage.
- Test tool configuration lives in `project/configs/test-config.json` (user-approved).
- SAST/vulnerability scans are opt-in and require explicit user approval, logged to `events.json`.
- Writes `Rejected` status only after notifying the user and receiving confirmation.
- After every status update, checks for story/epic rollup and writes a trigger to the queue if warranted.
- Maintains analytics baselines in `project/data/baselines.json` across sessions.

---

## Skills (Slash Commands)

Skills are stored in `skills/<name>/SKILL.md`. Invoke them with `/<name>` in a Claude Code session.

| Command | Description |
|---|---|
| `/init` | Scaffold project directories, `workflow.json`, `PROJECT_SUMMARY.md`, initial commit. |
| `/jenga` | Define project goals and initial epics in `PROJECT_SUMMARY.md`. |
| `/jbp` | Scaffold the project using the [JengaBasePlate](https://github.com/samwelmunga/JengaBasePlate.git) boilerplate. |
| `/brainstorm` | Focused planning session with the Scrum Master to define and refine features before committing to the board. |
| `/btw` | Capture a mid-flow mission, classify into epic/story structure, implement now or defer. |
| `/todo` | Add missions to `project/todo.md` linked to epics and stories. Loops until done, then optionally runs `/do`. |
| `/redo` | Rework a previous implementation by commit SHA or Epic/Story number. Includes scope assessment, plan, and doc updates. |
| `/do` | Execute tasks from the scrum board. Resolves each entry to full board context and drives the Developer agent. |
| `/status` | Overview of epics, stories, and tasks with statuses, open rapports, and queue depth. |
| `/commit` | Commit completed work using the EST naming convention (`epic(...)`, `story(...)`). |
| `/lgtm` | Approve current work, commit, and continue. Chains `/commit` + `/continue`. |
| `/continue` | Pick up the next incomplete item across `PROJECT_SUMMARY.md`, epics, and stories. |
| `/proceed` | Resume execution from where it left off. |
| `/error` | Guided troubleshooting — gathers context about an error and investigates a fix. |
| `/help` | List all available skills with descriptions. |

---

## MCP Tools

### `mcp/help`

Discovers available skills by scanning `.agents/skills/`. `help(path?)` returns skill folder names.

```bash
cd mcp/help && npm install
node index.js
```

### `mcp/execute-ticket`

Planned: creates a sub-agent, initialises a git worktree, and names the session after the task ID. See `mcp/execute-ticket/index.js`.

---

## Hooks

Hooks are configured in `settings.json` and fire automatically during a Claude Code session.

| Hook | Trigger | Action |
|---|---|---|
| `WorktreeCreate` | Developer creates a worktree | Runs `git worktree add` and echoes the worktree path. |
| `WorktreeRemove` | Developer removes a worktree | Runs `git worktree remove --force` on the given path. |
| `SessionEnd` | Any session ends | Runs `hooks/on_session_end.sh` asynchronously. |

### `hooks/on_session_end.sh`

Runs at the end of every Developer or Tester session: logs a session-end event to `events.json`, compares `rapports/problems/` against `.rapport_manifest.json` (skipping `*.IGNORE.md` files) and writes a `rapport_review` trigger if new rapports are found, then always appends a `status_review` trigger for the next Scrum Master session.

---

## distribute

### How It Works

1. **Add search paths** to `.jenga_paths` (one absolute directory per line, git-ignored) — each scanned 1–2 levels deep for directories containing `jenga.config.json`.

2. **Mark consumer projects** — place `jenga.config.json` at each consumer root:
   ```json
   {
     "workflow": "jenga",
     "workflow_version": "1.0.0",
     "target_dir": ".agents",
     "project_name": "my-project",
     "created_at": "2024-01-01",
     "updated_at": "2024-01-01"
   }
   ```
   Copy `templates/JENGA_CONFIG_TEMPLATE.json` as a starting point.

3. **Optionally exclude paths** — add `.jenga_ignore` at the consuming project root (one prefix pattern per line, never overwritten by distribute).

4. **Run the distribute:**
   ```bash
   .agents/hooks/distribute-changes.sh --dry-run  # preview
   .agents/hooks/distribute-changes.sh             # apply
   ```
   Or use the `/distribute` skill inside a Claude Code session.

### Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Preview all actions without writing anything |
| `--force` | Skip the workflow version compatibility check |
| `--paths <file>` | Override the default `.jenga_paths` file |

### Version Compatibility

If a consumer's `workflow_version` is ahead of the repo's `jenga.config.json`, distribute warns and skips that project. Use `--force` to override. On success, `updated_at` in the consumer's config is updated automatically.

### distribute Files

| File | Location | Purpose |
|---|---|---|
| `jenga.config.json` | Agents repo root | Canonical workflow version source |
| `.jenga_paths` | Agents repo root | Machine-local list of search paths (git-ignored) |
| `.jenga_paths.example` | Agents repo root | Documented format reference |
| `templates/JENGA_CONFIG_TEMPLATE.json` | `templates/` | Template for consumer project config |
| `.jenga_ignore` | **Consumer project root** | Per-project exclusions — owned by consumer, never overwritten |

---

## Directory Structure

```
.                          ← Project root (your software project)
├── agents/
│   ├── scrum_master.md
│   ├── developer.md
│   └── tester.md
├── hooks/
│   └── on_session_end.sh
├── mcp/
│   ├── help/
│   └── execute-ticket/
├── skills/
│   ├── init/
│   ├── jenga/
│   ├── jbp/
│   ├── brainstorm/
│   ├── btw/
│   ├── todo/
│   ├── do/
│   ├── status/
│   ├── commit/
│   ├── lgtm/
│   ├── continue/
│   ├── proceed/
│   ├── redo/
│   ├── error/
│   └── help/
├── templates/
│   ├── SCRUM_BOARD_SCHEMA.md
│   └── PROBLEM_RAPPORT_TEMPLATE.md
├── settings.json
└── RELEASE_NOTE.md

project/                   ← Created by /init inside your software project
├── board/
│   ├── epics/             ← E##_<slug>.md
│   ├── stories/           ← E##_S##_<slug>.md
│   └── tasks/             ← E##_S##_T##_<slug>.md
├── configs/
│   ├── workflow.json      ← Shared constants (statuses, paths, agents)
│   └── test-config.json   ← Test tool stack (owned by Tester, approved by user)
├── data/
│   └── baselines.json     ← Analytics baselines (owned by Tester)
├── queue/
│   ├── scrum_triggers.jsonl          ← Trigger queue for Scrum Master
│   └── project_summary_updates.jsonl ← Proposed PROJECT_SUMMARY.md edits
├── rapports/
│   ├── problems/          ← Problem rapports (Developer + Tester)
│   └── analysis/          ← Analysis rapports (Tester)
├── logs/
│   └── events.json        ← Append-only inter-agent event log
└── PROJECT_SUMMARY.md     ← Project source of truth (owned by Scrum Master)
```

---

## Getting Started

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and configured.

### Setup

1. **Copy this workflow** — place `agents/`, `hooks/`, `mcp/`, `skills/`, `templates/`, and `settings.json` into your project (typically under `.claude/` or `.agents/`).
2. **Run `/init`** — scaffolds `project/`, creates `workflow.json`, `PROJECT_SUMMARY.md`, and makes an initial git commit.
3. **Run `/jenga`** — answer the prompts to define project goals and initial epics.
4. **Run `/todo`** — describe the first features or tasks to add to `project/todo.md`.
5. **Run `/do`** — picks the first task and drives the full implementation → test → commit loop.
6. **Run `/status`** at any time to see where the project stands.

---

## Agent Communication Contract

Every inter-agent call must include a **sender object**:

```json
{
  "sender": {
    "agent": "<scrum_master | developer | tester | orchestrator>",
    "session_id": "<session id>",
    "task_id": "<E##_S##_T##>",
    "story_id": "<E##_S##>",
    "epic_id": "<E##>",
    "date": "<ISO 8601 UTC>",
    "paths": ["<commit SHA>", "..."],
    "worktree": "<absolute path to worktree>"
  }
}
```

All agents log every incoming sender object to `project/logs/events.json` as their **first action** on every invocation.
