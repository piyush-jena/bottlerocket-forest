---
name: autonomous-task-loop
description: >-
  Generate planning artifacts (spec, tasks, progress) and a ralph-loop.sh driver
  for headless autonomous execution. Use when a feature or task is too large for
  a single agent session and needs to be broken into checkboxable steps that run
  one-per-iteration via kiro-cli --no-interactive.
---

# Autonomous Task Loop

Break a feature or multi-step task into planning artifacts that drive headless autonomous execution.

## When to Use

- The work spans multiple files, repositories, or stages.
- You want unattended execution — one task per kiro-cli session, looped.
- The problem is well-understood enough to enumerate concrete tasks with verify commands.

## When NOT to Use

- Single-step or single-file changes — just do them directly.
- Exploratory work where the task list can't be defined upfront — use `deep-research` or `fact-find` first.
- Work that requires human judgment between every step.

## Artifacts

The skill produces four files in a planning directory:

```
planning/<feature-name>/
├── spec.md            # Problem definition (goal, constraints, context, verification)
├── tasks.md           # Ordered checkboxable task list with verify commands
├── progress.md        # Append-only log (initially empty header)
└── ralph-loop.sh      # Headless driver script
```

## Procedure

### Step 1: Gather Information

Collect from the user or infer from context:

1. **Feature name** — short kebab-case identifier (e.g., `kubelet-extra-config`).
2. **Grove name** — which grove to work in (or create one).
3. **Goal** — what success looks like in user-visible terms.
4. **Constraints** — non-negotiable requirements.
5. **Relevant files/patterns** — code to study, patterns to follow.
6. **Verification approach** — how to confirm the work is correct.

If the user provides a rough plan, design doc, or conversation history, extract these from that material rather than asking redundant questions.

### Step 2: Write the Spec

Create `planning/<feature-name>/spec.md` following this template:

```markdown
# Spec: <Feature Name>

## Goal
What success looks like in user-visible terms.
One to three sentences.

## Constraints
Non-negotiable requirements the solution MUST satisfy.
- Constraint 1
- Constraint 2
- ...

## Acceptance Criteria
Numbered, testable criteria using GIVEN/WHEN/THEN format.
1. **AC-1: <Name>.** GIVEN ..., WHEN ..., THEN ...
2. **AC-2: <Name>.** GIVEN ..., WHEN ..., THEN ...

## Context
Relevant files and patterns to study.
- "Study X in `path/to/file` — this is where ..."
- "Follow the pattern established by Y"

### Repository Layout
If the work spans multiple repos, list them and what lives where.

## Suggestions (Optional)
Starting points the agent MAY consider. Clearly marked as non-binding.
- "One approach: ..."
- "Consider whether X pattern applies"

## Verification
How to confirm the solution works.
### Unit/Build Verification
- Commands to run, expected outcomes.
### Integration Verification (if applicable)
- Manual or automated steps on a live system.

## Delegation Plan
How to break the work into parallelizable stages.
### Stage 1: <Name>
- Repository, files, work description, isolation strategy.
### Stage 2: <Name> — depends on Stage 1
- ...
### Parallelism
- Which stages can run in parallel, which are sequential.
```

Guidelines for the spec:
- Describe the PROBLEM SPACE, not the solution. No line numbers, no exact code, no variable names.
- Each constraint should be independently verifiable.
- Acceptance criteria must be testable by the agent (a command it can run, output it can check).
- The delegation plan informs task grouping but the agent executes sequentially.

### Step 3: Write the Tasks

Create `planning/<feature-name>/tasks.md` following this template:

```markdown
# Tasks: <Feature Name>

Design spec: [spec.md](./spec.md)
Progress log: [progress.md](./progress.md)

## Repository Layout
Brief note on where repos live relative to the grove root.

## Tasks

### Stage 1: <Stage Name>

- [ ] **T01: <Concise description>**
  - File: `path/to/primary/file`
  - What to do (1-3 bullet points, behavior-focused).
  - Acceptance: AC-1, AC-10
  - Verify: `command to run`

- [ ] **T02: <Concise description>**
  - File: `path/to/file`
  - What to do.
  - Acceptance: AC-2
  - Verify: `command to run`

### Stage 2: <Stage Name>

- [ ] **T03: ...**
  ...
```

Guidelines for tasks:
- Each task is one logical unit of work completable in a single agent session.
- Tasks MUST have a `Verify:` command that the agent can run to confirm success.
- Order tasks so each builds on the previous (the agent works top-to-bottom).
- Group tasks by stage from the delegation plan.
- Keep task count reasonable — 5 to 25 tasks. Fewer for simple features, more for cross-repo work.
- A task that only runs a build/test suite to verify prior work is valid (e.g., "Verify full workspace compiles").
- Include a final verification task per stage.

### Step 4: Initialize Progress

Create `planning/<feature-name>/progress.md` with just the header:

```markdown
# Progress: <Feature Name>

Append-only log of learnings, decisions, and discoveries across ralph-loop iterations.

---
```

The agent appends entries during execution. Each entry follows this format:

```markdown
## Iteration N — T<XX>: <Task description>

**What was done:**
- ...

**Verification:**
- ...

**Learnings:**
- ...
```

### Step 5: Generate ralph-loop.sh

Create `planning/<feature-name>/ralph-loop.sh` from the template below.
Customize only the path variables at the top.
Make it executable (`chmod +x`).

The template is provided in the `scripts/` directory of this skill.
Copy it and update these variables:

```bash
FOREST_ROOT="/home/fedora/bottlerocket-forest"
GROVE_DIR="$FOREST_ROOT/groves/<grove-name>"
SPEC_DIR="$FOREST_ROOT/planning/<feature-name>"
SPEC_FILE="$SPEC_DIR/spec.md"
```

### Step 6: Present to User

Show the user:
1. The spec (for review of goal, constraints, acceptance criteria).
2. The task list (for review of ordering and completeness).
3. How to run: `./planning/<feature-name>/ralph-loop.sh [max_iterations]`

Wait for user approval before they run the loop.
Call out any assumptions or areas of uncertainty.

## Output Checklist

Before presenting artifacts to the user, verify:
- [ ] Spec has Goal, Constraints, Acceptance Criteria, Context, and Verification sections.
- [ ] Every acceptance criterion is referenced by at least one task.
- [ ] Every task has a Verify command.
- [ ] Tasks are ordered so dependencies come first.
- [ ] Progress file exists with the empty header.
- [ ] ralph-loop.sh has correct paths and is executable.
- [ ] The grove exists (or instructions to create it are provided).
