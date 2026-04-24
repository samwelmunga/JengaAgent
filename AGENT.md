# Workflow Rules

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

## Skill Execution — `prefered_agent`

When a `SKILL.md` file contains a `prefered_agent` property in its YAML frontmatter:

```yaml
metadata:
  prefered_agent: <agent_name>
```

this indicates which sub-agent should be used to **execute** the skill. When invoking the skill, delegate execution to that agent by loading its definition from `agents/<agent_name>.md` and passing it the skill's instructions along with all relevant context.

Valid values match the agent definitions in the `agents/` directory: `scrum_master`, `developer`, `tester`.

Skills without this property are executed directly without delegating to a sub-agent.

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
