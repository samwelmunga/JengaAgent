# Scrum Board Schema

This document is the authoritative reference for all scrum board files. Every agent that creates, reads, or updates board items must follow this schema exactly.

---

## Directory Layout

```
project/
  board/
    epics/          Epic files: E##_<slug>.md
    stories/        Story files: E##_S##_<slug>.md
    tasks/          Task files: E##_S##_T##_<slug>.md
  configs/
    workflow.json   Shared constants (statuses, paths, rapport types)
  data/
    baselines.json  Analytics baselines (owned by tester)
  queue/
    scrum_triggers.jsonl         Trigger queue for scrum master
    developer_triggers.jsonl     Trigger queue for developer agent
    tester_triggers.jsonl        Trigger queue for tester agent
    project_summary_updates.jsonl Proposed PROJECT_SUMMARY.md edits
    .session_handoff.json        Transient inter-session handoff (written by agent, consumed by on_session_end.sh)
  rapports/
    problems/       Problem rapports from developer and tester
    analysis/       Analysis rapports from tester
  logs/
    events.json     Append-only inter-agent event log
```

> **Note:** `project/epics/` and `project/stories/` and `project/tasks/` are legacy paths from earlier skills. All new board items are written under `project/board/`. Skills and agents that reference the legacy paths should migrate to `project/board/` when next touched.

---

## ID & Filename Conventions

| Type  | ID Format     | Filename                          |
|-------|---------------|-----------------------------------|
| Epic  | `E##`         | `E##_<slug>.md`                   |
| Story | `E##_S##`     | `E##_S##_<slug>.md`               |
| Task  | `E##_S##_T##` | `E##_S##_T##_<slug>.md`           |

- Numbers are zero-padded to two digits: `E01`, `S03`, `T07`
- `<slug>` is a short lowercase kebab-case title derived from the item title
- Example: `E02_S04_T01_add-jwt-middleware.md`

---

## Status Values

All status fields must use one of the following exact strings:

| Status               | Meaning                                                    |
|----------------------|------------------------------------------------------------|
| `Pending`            | Created, not yet started                                   |
| `In Progress`        | Actively being worked on                                   |
| `Passed`             | All tests passed, no findings                              |
| `Passed with remarks`| Tests passed but non-blocking findings exist               |
| `Failed`             | Tests did not pass                                         |
| `Rejected`           | Deliberately rejected — not a test failure                 |
| `Blocked`            | Cannot proceed; human intervention required                |

Only the **tester agent** may write status values to story and task files. Only the **scrum master** may write status values to epic files and may update story status as part of rollup.

---

## File Formats

### Epic — `E##_<slug>.md`

```markdown
---
id: E##
title: <Title>
status: Pending
date_created: YYYY-MM-DD
date_started:
date_completed:
stories:
  - E##_S##
  - E##_S##
---

# Epic: <Title>

## Purpose
<What this epic achieves and why.>

## Definition of Done
- <Concrete, testable criterion>
- <Concrete, testable criterion>
```

### Story — `E##_S##_<slug>.md`

```markdown
---
id: E##_S##
epic_id: E##
title: <Title>
status: Pending
date_created: YYYY-MM-DD
date_started:
date_completed:
tasks:
  - E##_S##_T##
  - E##_S##_T##
---

# Story: <Title>

As a [type of user], I want [goal] so that [reason/value].

## Acceptance Criteria
- [ ] <Verifiable criterion — specific enough for a tester to check without asking>

## Definition of Done
- <Concrete, testable criterion>
```

### Task — `E##_S##_T##_<slug>.md`

```markdown
---
id: E##_S##_T##
story_id: E##_S##
epic_id: E##
title: <Title>
status: Pending
date_created: YYYY-MM-DD
date_started:
date_completed:
assigned_to: developer | tester | scrum_master
---

# Task: <Title>

## Description
<What needs to be done and why.>

## Acceptance Criteria
- [ ] <Verifiable criterion>
```

---

## Linking Convention

- Every story file must list its parent epic ID in the `epic_id` frontmatter field.
- Every task file must list both `story_id` and `epic_id`.
- Every epic file must list all of its constituent story IDs in the `stories` array.
- Every story file must list all of its constituent task IDs in the `tasks` array.
- These lists are the authoritative index. The scrum master maintains them; other agents must not modify them.

---

## File Locking (Concurrency Control)

Before writing to any board file, agents must:

1. Check for a `<filename>.lock` file adjacent to the target file.
2. If the lock file exists and its modification time is less than 60 seconds ago — wait up to 10 seconds and retry once. If still locked, abort and write a problem rapport.
3. If no lock exists (or it is stale, older than 60 seconds) — create the lock file, perform the write, then delete the lock file.
4. Always delete the lock file in success and failure paths. Use a `trap` or equivalent cleanup.

---

## Rapport Types

| Type                    | Used by            | Location                                        |
|-------------------------|--------------------|-------------------------------------------------|
| `conflict`              | developer          | `project/rapports/problems/`                    |
| `implementation_blocker`| developer          | `project/rapports/problems/`                    |
| `security_concern`      | developer          | `project/rapports/problems/`                    |
| `test_failure`          | tester             | `project/rapports/problems/`                    |
| `analysis`              | tester             | `project/rapports/analysis/`                    |

---

## Queue Trigger Types

### `scrum_triggers.jsonl` — processed by scrum master at session start

| Type             | Written by  | Purpose                                                |
|------------------|-------------|--------------------------------------------------------|
| `rapport_review` | on_session_end.sh | New problem rapport(s) detected; create backlog items or mark Failed |
| `status_review`  | on_session_end.sh | Session ended; review board for stale statuses        |
| `story_rollup`   | tester / on_session_end.sh | All tasks under story complete; check rollup |

### `developer_triggers.jsonl` — processed by developer at session start

| Type                     | Written by          | Purpose                                       |
|--------------------------|---------------------|-----------------------------------------------|
| `implementation_assignment` | on_session_end.sh (from scrum_master handoff) | New tasks ready for implementation |
| `rework_assignment`      | on_session_end.sh (from tester handoff) | Tests failed; address rapport and re-implement |

### `tester_triggers.jsonl` — processed by tester at session start

| Type              | Written by          | Purpose                                         |
|-------------------|---------------------|-------------------------------------------------|
| `test_assignment` | on_session_end.sh (from developer handoff) | Implementation complete; run tests against worktree |

### `.session_handoff.json` — transient, consumed by on_session_end.sh

Written by an agent as the **last action** of its session. Consumed and deleted by `on_session_end.sh`. The file must not persist across sessions.

| Field         | Required by          | Notes                                    |
|---------------|----------------------|------------------------------------------|
| `agent`       | all                  | `scrum_master`, `developer`, or `tester` |
| `status`      | all                  | See per-agent values below               |
| `session_id`  | all                  |                                          |
| `task_ids`    | scrum_master only    | Array of task IDs assigned for implementation |
| `task_id`     | developer, tester    | Single task ID                           |
| `story_id`    | all                  |                                          |
| `epic_id`     | all                  |                                          |
| `worktree`    | developer, tester    | Absolute path                            |
| `paths`       | developer, tester    | Commit SHAs                              |
| `rapport_file`| tester only          | Path to rapport if status is failed/error |
| `date`        | all                  | ISO 8601 UTC                             |

**Status values per agent:**
- `scrum_master`: `planning_complete`
- `developer`: `implementation_complete`
- `tester`: `passed`, `passed_with_remarks`, `failed`, `error`



Located at `project/configs/workflow.json`. Scaffolded by `/init` and owned by the scrum master.

```json
{
  "statuses": ["Pending", "In Progress", "Passed", "Passed with remarks", "Failed", "Rejected", "Blocked"],
  "rapport_types": ["conflict", "implementation_blocker", "security_concern", "test_failure", "analysis"],
  "paths": {
    "board": "project/board",
    "epics": "project/board/epics",
    "stories": "project/board/stories",
    "tasks": "project/board/tasks",
    "rapports_problems": "project/rapports/problems",
    "rapports_analysis": "project/rapports/analysis",
    "queue": "project/queue",
    "logs": "project/logs",
    "data": "project/data",
    "configs": "project/configs"
  },
  "agents": ["developer", "tester", "scrum_master"]
}
```
