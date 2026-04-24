---
name: do
description: Execute tasks from the scrum board. Reads from project/todo.md, resolves each entry to its full scrum board context, and drives the developer agent through implementation with the correct sender object and communication contract. Loops until all selected tasks are done or the user exits.
metadata: 
  prefered_agent: developer
---

# Do — Execute Scrum Board Tasks

## Instructions

### 1. Check for `project/todo.md`
If the file does not exist, inform the user there are no queued tasks and exit.

### 2. List tasks and let the user choose
Display the contents of `project/todo.md`. Ask the user:
- Execute a specific task (by number or title)
- Execute the next task from the top of the list
- Exit

### 3. Resolve the task to full scrum board context
Each todo entry uses the format: `<mission title>: <E##_S##_T##>` (or `E##_S##` if no task ID).

Before starting:
1. Read `project/configs/workflow.json` to confirm board paths (default: `project/board/`)
2. Locate and read the matching file from `project/board/tasks/` (or `project/board/stories/` if story-level)
3. If the file does not exist, warn the user and skip — do not proceed with a task that has no scrum board definition
4. Present a brief summary of the task: title, acceptance criteria, parent story, parent epic

### 4. Invoke the developer agent
Pass the following to the developer agent:

**Sender object**: Copy `assets/sender_template.json` and populate all known fields (session_id, task_id, story_id, epic_id, current ISO 8601 UTC date).

**Context payload** (plain text alongside the sender object):
- Full task/story file content (title, description, acceptance criteria)
- Parent story and epic summaries (read from board files)
- Any relevant context from `project/PROJECT_SUMMARY.md`

The developer agent will:
- Log the incoming sender object to `project/logs/events.json`
- Create a worktree named `<E##_S##_T##-short-slug>`
- Implement, commit at milestones, and invoke the tester agent
- Return when the tester has verified the work

### 5. Update documentation
After code changes are complete, update **all** affected documentation:
- `project/epics/` and `project/stories/` — adjust descriptions, status, or scope if the redo alters them.
- `project/tasks/` — update or add instruction files if user-action prerequisites changed.
- `documentation/plans/` — if a plan file exists for the original work, append a "Redo" section describing the revision.
- `documentation/summaries/` — create or update phase summaries to reflect the redo.
- `README.md` and `WARP.md` — update if the redo changes user-facing behaviour or project setup.

### 6. After successful completion
- Invoke the `/commit` skill to commit the work (if not already committed by the developer)
- Remove the completed task from `project/todo.md`
- If `project/todo.md` is now empty, delete it

### 7. Loop
Go back to step 1.

