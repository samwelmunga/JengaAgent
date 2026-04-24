#!/bin/bash
# hooks/distribute-changes.sh
#
# Bump the workflow version and distribute updates to all consuming projects
# identified by jenga.config.json.
#
# Usage:
#   ./.agents/hooks/distribute-changes.sh [--release-type <major|minor|patch|amend>] [--dry-run] [--force] [--paths <file>]
#
# Flags:
#   --release-type  major|minor|patch — bump version then distribute to all projects
#                   amend             — keep version, distribute only to out-of-date or new projects
#   --dry-run       Preview all actions without copying anything
#   --force         Skip workflow version compatibility check
#   --paths <file>  Override default .jenga_paths file location
#
# A project is considered "new" when its jenga.config.json is either empty or
# contains only an empty object ({}).
#
# Search paths are read from .jenga_paths (one absolute path per line).
# Each path is scanned at depth 0 (the path itself), 1, and 2 levels deep for directories containing jenga.config.json.
# Exclusions per project are read from <project_root>/.jenga_ignore.
#
# Requirements: bash 4+, jq

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_PATHS_FILE="$REPO_ROOT/.jenga_paths"

DRY_RUN=false
FORCE=false
PATHS_FILE="$DEFAULT_PATHS_FILE"
RELEASE_TYPE=""
AMEND_MODE=false

# Project-scoped temp directory (never writes outside the repo)
TMP_DIR="$REPO_ROOT/.jenga_tmp"

# Top-level workflow items to copy into target_dir
distribute_ITEMS=("agents" "hooks" "mcp" "skills" "templates" "settings.json")

# Counters
COUNT_UPDATED=0
COUNT_SKIPPED=0
COUNT_FAILED=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[ok]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
log_error()   { echo -e "${RED}[error]${RESET} $*"; }
log_dry()     { echo -e "${YELLOW}[dry]${RESET}   $*"; }
log_skip()    { echo -e "${YELLOW}[skip]${RESET}  $*"; }

require_jq() {
  if ! command -v jq &>/dev/null; then
    log_error "jq is required but not found. Install it and retry."
    exit 1
  fi
}

# Read a field from a JSON file; returns empty string on failure
jq_field() {
  local file="$1" field="$2"
  jq -r "$field // empty" "$file" 2>/dev/null || true
}

# Compare semver strings; returns 0 if $1 <= $2
semver_lte() {
  local a="$1" b="$2"
  # Use sort -V (version sort); if a is first it is <= b
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$a" ]]
}

# Bump a semver string by the given release type
bump_version() {
  local current="$1" type="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"
  case "$type" in
    major) major=$(( major + 1 )); minor=0; patch=0 ;;
    minor) minor=$(( minor + 1 )); patch=0 ;;
    patch) patch=$(( patch + 1 )) ;;
    *)
      log_error "Invalid release type: $type (must be major, minor, patch, or amend)"
      exit 1
      ;;
  esac
  echo "$major.$minor.$patch"
}

# Returns 0 (true) if a project's jenga.config.json is new (empty file or bare {})
is_new_project() {
  local config_file="$1"
  if [[ ! -s "$config_file" ]]; then
    return 0  # empty file
  fi
  local content
  content="$(jq -c '.' "$config_file" 2>/dev/null || echo "")"
  [[ "$content" == "{}" ]]
}

# Update a JSON file atomically using a project-scoped temp file.
# Usage: atomic_json_update <file> [jq-args...] <jq-filter>
atomic_json_update() {
  local file="$1"
  shift
  mkdir -p "$TMP_DIR"
  local tmp="$TMP_DIR/$(basename "$file").tmp"
  jq "$@" "$file" > "$tmp" && mv "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=true; shift ;;
    --force)        FORCE=true;   shift ;;
    --paths)        PATHS_FILE="$2"; shift 2 ;;
    --release-type) RELEASE_TYPE="$2"; shift 2 ;;
    *)
      log_error "Unknown flag: $1"
      echo "Usage: $0 [--release-type <major|minor|patch|amend>] [--dry-run] [--force] [--paths <file>]"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
require_jq

if $DRY_RUN; then
  echo -e "${BOLD}${YELLOW}DRY RUN — no files will be written${RESET}"
fi

if [[ ! -f "$PATHS_FILE" ]]; then
  log_error "Paths file not found: $PATHS_FILE"
  log_error "Create it (see .jenga_paths.example) and add at least one search path."
  exit 1
fi

REPO_CONFIG="$REPO_ROOT/project.config.json"
if [[ ! -f "$REPO_CONFIG" ]]; then
  log_error "project.config.json not found at $REPO_CONFIG"
  exit 1
fi
REPO_VERSION="$(jq_field "$REPO_CONFIG" '.workflow_version')"
if [[ -z "$REPO_VERSION" ]]; then
  log_error "workflow_version missing from $REPO_CONFIG"
  exit 1
fi

# Handle --release-type
if [[ -n "$RELEASE_TYPE" ]]; then
  if [[ "$RELEASE_TYPE" == "amend" ]]; then
    AMEND_MODE=true
    log_info "Amend mode — version stays at ${BOLD}$REPO_VERSION${RESET}; only out-of-date or new projects will be updated."
  else
    NEW_VERSION="$(bump_version "$REPO_VERSION" "$RELEASE_TYPE")"
    log_info "Bumping workflow version: $REPO_VERSION → $NEW_VERSION ($RELEASE_TYPE)"
    if $DRY_RUN; then
      log_dry "  project.config.json: workflow_version → $NEW_VERSION"
    else
      atomic_json_update "$REPO_CONFIG" --arg v "$NEW_VERSION" '.workflow_version = $v'
    fi
    REPO_VERSION="$NEW_VERSION"
  fi
fi

log_info "Workflow version (this repo): ${BOLD}$REPO_VERSION${RESET}"

# ---------------------------------------------------------------------------
# Discover consumer projects
# ---------------------------------------------------------------------------

declare -a CONSUMER_PROJECTS=()

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  # Strip inline comments and trim whitespace
  line="${raw_line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"  # ltrim
  line="${line%"${line##*[![:space:]]}"}"  # rtrim
  [[ -z "$line" ]] && continue

  if [[ ! -d "$line" ]]; then
    log_warn "Path does not exist or is not a directory: $line"
    continue
  fi

  # Scan depth 0 (the path itself), 1, and 2 below the configured path
  while IFS= read -r -d '' candidate; do
    config_file="$candidate/jenga.config.json"
    # Skip the agents repo itself
    [[ "$candidate" -ef "$REPO_ROOT" ]] && continue
    if [[ -f "$config_file" ]]; then
      CONSUMER_PROJECTS+=("$candidate")
    fi
  done < <(find "$line" -mindepth 0 -maxdepth 2 -type d -print0 2>/dev/null)

done < "$PATHS_FILE"

if [[ ${#CONSUMER_PROJECTS[@]} -eq 0 ]]; then
  log_warn "No consumer projects found. Check your .jenga_paths entries."
  exit 0
fi

echo ""
log_info "Found ${#CONSUMER_PROJECTS[@]} consumer project(s):"
for p in "${CONSUMER_PROJECTS[@]}"; do
  echo "    $p"
done
echo ""

# ---------------------------------------------------------------------------
# distribute to each consumer project
# ---------------------------------------------------------------------------

distribute_to_project() {
  local project_root="$1"
  local config_file="$project_root/jenga.config.json"
  local project_name ignore_file target_dir consumer_version

  # Parse jenga.config.json — seed empty/bare configs before parsing
  if [[ ! -s "$config_file" ]] || [[ "$(jq -c '.' "$config_file" 2>/dev/null)" == "{}" ]]; then
    if ! $DRY_RUN; then
      echo '{}' > "$config_file"
    fi
  fi

  if ! jq . "$config_file" &>/dev/null; then
    log_error "Malformed jenga.config.json in: $project_root — skipping"
    (( COUNT_SKIPPED++ )) || true
    return
  fi

  project_name="$(jq_field "$config_file" '.project_name')"
  target_dir="$(jq_field "$config_file" '.target_dir')"
  consumer_version="$(jq_field "$config_file" '.workflow_version')"

  [[ -z "$project_name" ]] && project_name="$(basename "$project_root")"
  [[ -z "$target_dir" ]]   && target_dir=".agents"

  echo -e "${BOLD}→ $project_name${RESET} ($project_root)"

  # Amend mode: skip projects that are already at the current version and not new
  if $AMEND_MODE && ! is_new_project "$config_file"; then
    if [[ "$consumer_version" == "$REPO_VERSION" ]]; then
      log_skip "  already at version $REPO_VERSION"
      (( COUNT_SKIPPED++ )) || true
      echo ""
      return
    fi
    log_info "  version drift: $consumer_version → $REPO_VERSION"
  fi

  # Version check
  if [[ -n "$consumer_version" ]] && ! $FORCE; then
    if ! semver_lte "$consumer_version" "$REPO_VERSION"; then
      log_warn "Consumer version ($consumer_version) is ahead of repo ($REPO_VERSION). Use --force to override. Skipping."
      (( COUNT_SKIPPED++ )) || true
      return
    fi
  fi

  local dest="$project_root/$target_dir"
  if [[ ! -d "$dest" ]] && ! $DRY_RUN; then
    mkdir -p "$dest"
  fi

  # Read .jenga_ignore
  ignore_file="$project_root/.jenga_ignore"
  declare -a ignore_patterns=()
  if [[ -f "$ignore_file" ]]; then
    while IFS= read -r iline || [[ -n "$iline" ]]; do
      iline="${iline%%#*}"
      iline="${iline#"${iline%%[![:space:]]*}"}"
      iline="${iline%"${iline##*[![:space:]]}"}"
      [[ -z "$iline" ]] && continue
      ignore_patterns+=("$iline")
    done < "$ignore_file"
    [[ ${#ignore_patterns[@]} -gt 0 ]] && log_info "  Ignoring: ${ignore_patterns[*]}"
  fi

  # Copy each distribute item
  local project_had_error=false
  for item in "${distribute_ITEMS[@]}"; do
    local src="$REPO_ROOT/$item"
    [[ ! -e "$src" ]] && continue  # item doesn't exist in repo, skip silently

    # Check ignore patterns
    local skip=false
    for pattern in "${ignore_patterns[@]+"${ignore_patterns[@]}"}"; do
      if [[ "$item" == "$pattern" || "$item" == "$pattern/"* ]]; then
        log_skip "  $item (ignored)"
        skip=true
        break
      fi
    done
    $skip && continue

    if $DRY_RUN; then
      log_dry "  cp -r $src → $dest/$item"
    else
      mkdir -p "$TMP_DIR"
      if cp -r "$src" "$dest/" 2>"$TMP_DIR/cp_err"; then
        log_ok "  $item"
      else
        log_error "  Failed to copy $item → $dest/"
        log_error "  $(cat "$TMP_DIR/cp_err")"
        project_had_error=true
      fi
    fi
  done

  # Mirror the same items into .claude/ (create if absent, overwrite if present)
  local claude_dest="$project_root/.claude"
  if $DRY_RUN; then
    log_dry "  mkdir -p $claude_dest"
  else
    mkdir -p "$claude_dest"
  fi
  for item in "${distribute_ITEMS[@]}"; do
    local src="$REPO_ROOT/$item"
    [[ ! -e "$src" ]] && continue

    local skip=false
    for pattern in "${ignore_patterns[@]+"${ignore_patterns[@]}"}"; do
      if [[ "$item" == "$pattern" || "$item" == "$pattern/"* ]]; then
        skip=true
        break
      fi
    done
    $skip && continue

    if $DRY_RUN; then
      log_dry "  cp -rf $src → $claude_dest/$item"
    else
      mkdir -p "$TMP_DIR"
      if cp -rf "$src" "$claude_dest/" 2>"$TMP_DIR/cp_err"; then
        log_ok "  .claude/$item"
      else
        log_error "  Failed to copy $item → $claude_dest/"
        log_error "  $(cat "$TMP_DIR/cp_err")"
        project_had_error=true
      fi
    fi
  done

  # Copy AGENT.md to project root as AGENT.md, CLAUDE.md, and WARP.md
  local agent_md_src="$REPO_ROOT/AGENT.md"
  if [[ -f "$agent_md_src" ]]; then
    for target_name in "AGENT.md" "CLAUDE.md" "WARP.md"; do
      if $DRY_RUN; then
        log_dry "  cp $agent_md_src → $project_root/$target_name"
      else
        if cp "$agent_md_src" "$project_root/$target_name" 2>"$TMP_DIR/cp_err"; then
          log_ok "  $target_name (project root)"
        else
          log_error "  Failed to copy AGENT.md → $project_root/$target_name"
          log_error "  $(cat "$TMP_DIR/cp_err")"
          project_had_error=true
        fi
      fi
    done
  else
    log_warn "  AGENT.md not found in repo root — skipping AGENT.md/CLAUDE.md/WARP.md"
  fi

  # Update updated_at and workflow_version in jenga.config.json
  if ! $DRY_RUN && ! $project_had_error; then
    local today
    today="$(date -u +%Y-%m-%d)"
    if atomic_json_update "$config_file" \
        --arg d "$today" --arg v "$REPO_VERSION" \
        '.updated_at = $d | .workflow_version = $v' 2>/dev/null; then
      log_ok "  updated_at → $today"
      log_ok "  workflow_version → $REPO_VERSION"
    else
      log_warn "  Could not update jenga.config.json"
    fi
    (( COUNT_UPDATED++ )) || true
  elif $project_had_error; then
    (( COUNT_FAILED++ )) || true
  else
    # dry-run counts as updated (preview)
    log_dry "  jenga.config.json: workflow_version → $REPO_VERSION, updated_at → $(date -u +%Y-%m-%d)"
    (( COUNT_UPDATED++ )) || true
  fi

  echo ""
}

for project in "${CONSUMER_PROJECTS[@]}"; do
  distribute_to_project "$project"
done

# Clean up project-scoped temp dir
rm -rf "$TMP_DIR"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "${BOLD}── Summary ──────────────────────────────────${RESET}"
echo -e "  ${GREEN}✔ Updated : $COUNT_UPDATED${RESET}"
echo -e "  ${YELLOW}⊘ Skipped : $COUNT_SKIPPED${RESET}"
echo -e "  ${RED}✖ Failed  : $COUNT_FAILED${RESET}"
echo ""

if [[ $COUNT_FAILED -gt 0 ]]; then
  exit 1
fi