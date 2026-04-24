---
name: distribute
description: distribute the latest workflow changes to all consumer projects registered in .jenga_paths. Detects projects via jenga.config.json, respects .jenga_ignore per project, and prints a summary.
---

# distribute — Sync Workflow to Consumer Projects

## Instructions

0. **Check for an attached path** — if the user attaches a path to the skill prompt (e.g. `/Users/me/projects/my-app`), add that path to `.jenga_paths` before proceeding, unless it is already present. Append it as a new line at the end of the file:

   ```bash
   echo "/the/attached/path" >> .jenga_paths
   ```

   Confirm to the user that the path has been registered, then continue with the steps below.

1. **Ask for the release type** — ask the user whether this is a `major`, `minor`, `patch`, or `amend` release:
   - `major` / `minor` / `patch` — bumps the version in `project.config.json`, then distributes to **all** consumer projects.
   - `amend` — **keeps the version unchanged**; distributes only to projects that are out of date (their `workflow_version` differs from the current one) or are new (empty or `{}` `jenga.config.json`).

   Pass the answer directly to the script via `--release-type`.

2. **Check for a dry-run request** — if the user has not explicitly asked to push changes, run with `--dry-run` first and show the preview output. Ask for confirmation before proceeding with the real distribute.

3. **Run the distribute script:**

   ```bash
   # Preview first (recommended)
   ./.agents/hooks/distribute-changes.sh --release-type <major|minor|patch|amend> --dry-run

   # Confirmed distribute
   ./.agents/hooks/distribute-changes.sh --release-type <major|minor|patch|amend>
   ```

   Available flags:
   | Flag | Effect |
   |---|---|
   | `--release-type major\|minor\|patch` | Bump `workflow_version`, distribute to all projects |
   | `--release-type amend` | Keep version, distribute only to out-of-date or new projects |
   | `--dry-run` | Preview all actions without writing anything |
   | `--force` | Skip the workflow version compatibility check |
   | `--paths <file>` | Use a custom paths file instead of `.jenga_paths` |

4. **Report the summary** — relay the full terminal output (updated / skipped / failed counts) back to the user, including any warnings or errors.

5. **If failures occurred** — explain which project failed and why (the script prints the `cp` error), and suggest remediation steps (e.g., permission issues, missing `target_dir`).

6. **If no paths are configured** — inform the user that `.jenga_paths` is empty and guide them to add absolute paths pointing to directories that contain (or parent) their consuming projects. Refer them to `.jenga_paths.example` for format guidance.
