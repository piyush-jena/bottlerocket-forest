#!/usr/bin/env bash
# ralph-loop.sh — Minimal autonomous agent loop for kiro-cli
#
# Usage: ./ralph-loop.sh [max_iterations]
#
# Runs kiro-cli in headless mode, one task per iteration, fresh context each time.
# All work stays local — no commits, no pushes, no PRs, no issue comments.

set -uo pipefail

# ── Customize these paths ──────────────────────────────────────────────
FOREST_ROOT="/home/fedora/bottlerocket-forest"
GROVE_DIR="$FOREST_ROOT/groves/GROVE_NAME"
SPEC_DIR="$FOREST_ROOT/planning/FEATURE_NAME"
SPEC_FILE="$SPEC_DIR/spec.md"
# ───────────────────────────────────────────────────────────────────────

TASK_FILE="$SPEC_DIR/tasks.md"
PROGRESS_FILE="$SPEC_DIR/progress.md"
LOG_FILE="$SPEC_DIR/ralph-loop.log"
MAX_ITERATIONS="${1:-10}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
log()  { echo -e "${GREEN}[ralph $(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[ralph $(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[ralph $(date +%H:%M:%S)]${NC} $*"; }

# Count remaining unchecked tasks
remaining() { grep -c '^\s*- \[ \]' "$TASK_FILE" 2>/dev/null || echo 0; }

# ── Preflight checks ──────────────────────────────────────────────────
if [[ ! -f "$TASK_FILE" ]]; then
    err "No tasks.md found at $TASK_FILE"
    exit 1
fi
if [[ ! -f "$SPEC_FILE" ]]; then
    err "No spec file found at $SPEC_FILE"
    exit 1
fi
if [[ ! -d "$GROVE_DIR" ]]; then
    err "Grove not found at $GROVE_DIR"
    exit 1
fi
if ! command -v kiro-cli &>/dev/null; then
    err "kiro-cli not found in PATH"
    exit 1
fi

log "Ralph loop starting"
log "Grove: $GROVE_DIR"
log "Tasks: $TASK_FILE"
log "Max iterations: $MAX_ITERATIONS"
log "Remaining tasks: $(remaining)"
echo ""

cd "$GROVE_DIR"
log "Working directory: $(pwd)"

# ── Prompt builder ─────────────────────────────────────────────────────
build_prompt() {
    cat <<PROMPT
You are an autonomous coding agent working through a task list one task at a time.

CRITICAL RULES:
- Work ONLY inside the grove directory: $GROVE_DIR
- Do NOT run git commit, git push, gh pr, or any command that creates commits, PRs, or issue comments.
- Do NOT modify files outside the grove or the spec directory ($SPEC_DIR).
- Complete exactly ONE unchecked task (- [ ]) per session, then stop.

WORKFLOW:
1. Read the task file at $TASK_FILE to find the first unchecked task.
2. Read the spec at $SPEC_FILE for design context.
3. Read $PROGRESS_FILE for learnings from previous iterations.
4. Implement the task. All source files you edit must be under $GROVE_DIR.
5. Run the verify command listed in the task to confirm it works.
6. If verification passes, mark the task done in $TASK_FILE: change "- [ ]" to "- [x]".
7. Append a brief entry to $PROGRESS_FILE with: iteration number, task ID, what you did, and any learnings or gotchas discovered.
8. If verification fails after reasonable attempts, leave the task unchecked, note the blocker in $PROGRESS_FILE, and stop.

The task file uses this format:
- [ ] **T01: Description** — unchecked, work on this
- [x] **T01: Description** — checked, already done, skip it

Start now. Read the task file and begin.
PROMPT
}

# ── Main loop ──────────────────────────────────────────────────────────
iteration=0
while [[ $iteration -lt $MAX_ITERATIONS ]]; do
    iteration=$((iteration + 1))
    r=$(remaining)

    if [[ "$r" -eq 0 ]]; then
        log "All tasks complete!"
        exit 0
    fi

    log "=== Iteration $iteration / $MAX_ITERATIONS === ($r tasks remaining)"

    kiro-cli chat \
        --no-interactive \
        --trust-all-tools \
        "$(build_prompt)" \
        2>&1 | tee -a "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}

    if [[ $exit_code -ne 0 ]]; then
        warn "kiro-cli exited with code $exit_code (iteration $iteration)"
        {
            echo ""
            echo "## Iteration $iteration — ERROR"
            echo "kiro-cli exit code: $exit_code"
            echo ""
        } >> "$PROGRESS_FILE"
    fi

    log "Iteration $iteration complete. Remaining: $(remaining)"
    echo ""

    # Brief pause between iterations
    sleep 3
done

r=$(remaining)
if [[ "$r" -eq 0 ]]; then
    log "All tasks complete!"
else
    warn "Reached max iterations ($MAX_ITERATIONS). $r task(s) remaining."
    warn "Review $PROGRESS_FILE for blockers, then re-run."
    exit 1
fi
