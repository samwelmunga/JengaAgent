#!/bin/bash
# .claude/hooks/on_session_end.sh
# Triggered on SessionEnd by developer and tester agents.
#
# Responsibilities:
#   1. Log a sender event to events.json
#   2. Detect new problem rapports using a manifest (not a timestamp)
#      and write trigger payloads to the scrum master queue
#   3. Write a status-review trigger to the scrum master queue
#
# NOTE: Claude Code hooks cannot spawn a named agent session directly.
# Instead, we write structured trigger payloads to
# project/queue/scrum_triggers.jsonl. The scrum master reads and
# processes this queue at the start of its next session.

PROJECT_DIR="$CLAUDE_PROJECT_DIR"
RAPPORT_DIR="$PROJECT_DIR/project/rapports/problems"
MANIFEST="$PROJECT_DIR/.claude/hooks/.rapport_manifest.json"
QUEUE_DIR="$PROJECT_DIR/project/queue"
QUEUE_FILE="$QUEUE_DIR/scrum_triggers.jsonl"
EVENTS_LOG="$PROJECT_DIR/project/logs/events.json"
AGENT="${CLAUDE_AGENT_TYPE:-unknown}"
SESSION_ID="${CLAUDE_SESSION_ID:-}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$PROJECT_DIR/project/logs" "$QUEUE_DIR"

# --- 1. Log sender object ---

SENDER=$(jq -n \
  --arg agent "$AGENT" \
  --arg session_id "$SESSION_ID" \
  --arg date "$TIMESTAMP" \
  '{
    sender: {
      agent: $agent,
      session_id: $session_id,
      task_id: "",
      story_id: "",
      epic_id: "",
      date: $date,
      paths: [],
      worktree: ""
    }
  }')

if [ -f "$EVENTS_LOG" ]; then
  jq --argjson entry "$SENDER" '. += [$entry]' "$EVENTS_LOG" > /tmp/events_tmp.json \
    && mv /tmp/events_tmp.json "$EVENTS_LOG"
else
  echo "[$SENDER]" > "$EVENTS_LOG"
fi

# --- 2. Manifest-based rapport detection ---
# Use a JSON array of known filenames instead of a mtime sentinel file.
# This prevents silently missing rapports written before the session ends
# but after the sentinel was last touched.

if [ ! -f "$MANIFEST" ]; then
  echo "[]" > "$MANIFEST"
fi

if [ -d "$RAPPORT_DIR" ]; then
  # Collect current rapport files (exclude .IGNORE.md files — already resolved)
  # Results are stored in a bash array to avoid word-splitting on paths.
  mapfile -t CURRENT_FILES < <(find "$RAPPORT_DIR" -name "*.md" ! -name "*.IGNORE.md" 2>/dev/null | sort)

  # Identify new files not present in the manifest
  NEW_FILES=()
  for file in "${CURRENT_FILES[@]}"; do
    known=$(jq --arg f "$file" 'index($f) != null' "$MANIFEST" 2>/dev/null)
    if [ "$known" != "true" ]; then
      NEW_FILES+=("$file")
    fi
  done

  if [ "${#NEW_FILES[@]}" -gt 0 ]; then
    echo "New rapport(s) detected: ${#NEW_FILES[@]} file(s). Writing trigger to queue."

    # Build a safe JSON array of file paths — never interpolate paths into strings
    FILES_JSON=$(printf '%s\n' "${NEW_FILES[@]}" | jq -R . | jq -s .)

    TRIGGER=$(jq -n \
      --arg type "rapport_review" \
      --arg agent "$AGENT" \
      --arg session_id "$SESSION_ID" \
      --arg date "$TIMESTAMP" \
      --argjson files "$FILES_JSON" \
      '{
        type: $type,
        sender: { agent: $agent, session_id: $session_id, date: $date },
        rapport_files: $files,
        message: "New problem rapport(s) detected. Review each file and either create a backlog item or set the affected task/story/epic status to Failed with a rapport reference. Report back to the user with a summary."
      }')

    echo "$TRIGGER" >> "$QUEUE_FILE"

    # Update the manifest to include all current files
    printf '%s\n' "${CURRENT_FILES[@]}" | jq -R . | jq -s . > "$MANIFEST"
  fi
fi

# --- 3. Status-review trigger ---

TRIGGER=$(jq -n \
  --arg type "status_review" \
  --arg agent "$AGENT" \
  --arg session_id "$SESSION_ID" \
  --arg date "$TIMESTAMP" \
  '{
    type: $type,
    sender: { agent: $agent, session_id: $session_id, date: $date },
    message: "A session has just ended. Review the scrum board and update the status of any tasks, stories, or epics where status may have changed based on recent activity. Check story and epic rollup. Report back to the user with a summary of what changed."
  }')

echo "$TRIGGER" >> "$QUEUE_FILE"