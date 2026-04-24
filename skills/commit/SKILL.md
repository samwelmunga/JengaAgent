---
name: commit
description: Commit implemented epic, story, or task work using the EST naming convention. Also handles user-action prerequisites and new-epic boundaries. Use after completing any EST work item.
---

# Commit — Commit Completed Work

## Instructions

If no epic, task, or story has been implemented, exit with the message: "No implementation to commit."

1. **Document user-action prerequisites** — If the epic, task, or story has prerequisites or configurations that require user action (e.g. setting up a GitHub account, configuring OAuth), create an instructions file at:
   ```
   project/board/tasks/<Epic No.>_<Action_Name>_INSTRUCTIONS.md
   ```
   Example: `E02_SETUP_OAUTH_INSTRUCTIONS.md`. Use `assets/user_instructions_template.md` as the structure.

2. **Commit** using the following format:
   - **Epic:** `epic(<Epic Title>): <MAX_50_CHAR_SUMMARY>`
   - **Task/Story:** `story(<Epic Title>_<Story Title>): <MAX_50_CHAR_SUMMARY>`

3. **Check for next epic** — If a new epic is to be started, inform the user that a new conversation should be initiated. If there are no subsequent epics left, show the message: "All Done! 🎉"
