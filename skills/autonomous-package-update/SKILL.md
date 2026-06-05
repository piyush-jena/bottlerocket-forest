---
name: autonomous-package-update
description: >-
  Generate a step-by-step plan and planning artifacts (spec, tasks, progress) plus a
  ralph-loop.sh driver for headless autonomous execution of package updates. Use when you
  have a set of package updates too large for a single agent session that needs
  checkboxable steps run one-per-iteration via kiro-cli --no-interactive.
---

# Autonomous Package Update

Break a package update task into planning artifacts that drive headless autonomous execution.

## Scope and Phases

A package update has three phases with very different risk profiles. Decide with the user
which phases a run covers before generating artifacts.

- **Phase A — Update + local build + commit (headless-safe).** For each package: apply the
  change via SKILL: `update-package`, validate with a single-package build via SKILL:
  `build-package`, then create one local commit. Fully local, safe to run unattended.
- **Phase B — Full kit + variant build (long, local).** After ALL package updates land, build
  the whole kit once with SKILL: `build-kit-locally`, then a variant image with SKILL:
  `build-variant-from-local-kits`. Needs Docker and is slow; do it once, not per package.
- **Phase C — Functional testing (AWS).** Run the per-package tests from SKILL:
  `test-third-party-package`. This launches EC2 instances, boots AMIs, joins EKS clusters,
  runs Kubernetes conformance (hours per k8s minor), and SSM `sheltie` one-liners. Run this
  phase **when AWS credentials are present**; if no usable credentials are found, mark the
  Phase C tasks BLOCKED and note it. **Some Type 6 tests are destructive** — e.g. the kdump
  test (`kexec-tools`/`makedumpfile`/`libelf`) crashes the node on purpose. Run those on a
  throwaway instance, wait for it to reboot, then verify the crash dump landed (check
  `/var/log/kdump`). Never run a destructive test on an instance you need to keep.

The default ralph-loop covers **Phase A then Phase B**, and **Phase C when AWS credentials are
available**. Phase C tasks that need live AWS resources are skipped (BLOCKED) if credentials
are absent.

## Confirmed Conventions

These are settled defaults for this skill; restate them in the spec so the headless agent
follows them:

- **One commit per package**, created locally inside the loop. No push, no PR, no issue comments.
- **Commit format** follows SKILL: `update-package`: `packages: update <package-name> to <new-version>`.
  Note removed/rebased patches and notable upstream changes in the commit body. Do NOT sign
  commits — no `Signed-off-by` trailer and no GPG signing.
- **Autonomous remediation.** The agent performs GPG signing-key rotation and patch rebasing
  itself (see SKILL: `update-package` "Common Issues") — these do NOT count as "human judgment".
- **Skip, don't halt.** If a package genuinely cannot be completed autonomously (e.g. the build
  still fails after key rotation and patch rebasing, or the change needs a human decision), mark
  that package's task BLOCKED and continue to the next package. Do not stop the whole run.
- **Kit.** Unless told otherwise, all packages live in `bottlerocket-core-kit`. Still confirm
  each package's location during planning.

## When to Use

- When you have a set (1+) of packages to update and test.
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

## Prerequisites

- Working from within a grove directory
- Kit repository cloned in `kits/` directory (e.g., `kits/bottlerocket-core-kit`)

## Procedure

### Step 1: Gather inputs and resolve the problem

Collect from the user or infer from any provided plan/conversation. If the user supplied a
list, extract from it rather than asking redundant questions.

1. **Feature name** — short kebab-case identifier for the planning dir (e.g.,
   `core-kit-package-bumps-2026-06`).
2. **Grove name** — which grove to work in (or instructions to create one).
3. **Package list** — each package and its target version, exactly as the user gave them.
4. **Kit** — default `bottlerocket-core-kit`. Confirm every package actually lives there:

   ```bash
   ls kits/bottlerocket-core-kit/packages/<package-name>/
   ```

   Note any versioned directories (e.g. `kubernetes-1.34`, `containerd-1.7`). If a package
   is not in the assumed kit, flag it rather than guessing.
5. **Resolve version-specific details** so the headless agent has clear targets. For each
   package, confirm the new source URL pattern and, where the spec uses derived versions, note
   the values in the spec:
   - **Kubernetes packages** — the user gives the EKS release number (`%global releasever`,
     e.g. `53 → 54`); treat it as authoritative. The matching EKS-distro Kubernetes version
     (`%global gover`, e.g. `v1.30.x`) and download URL are determined by the agent during the
     task by following SKILL: `update-package` (check the EKS-distro releases page, or
     increment the patch until the URL resolves). Record the resolved `gover` in the commit
     body and `progress.md`.
   - Other macro-versioned packages (libncurses date, util-linux `majorminor`, Go `gover`,
     readline incremental patches) — see SKILL: `update-package` for the patterns.
6. **Classify the test for each package** (needed when Phase C runs):

   ```bash
   skills/test-third-party-package/scripts/classify-package.sh <pkg> [<pkg> ...]
   ```

   The classifier maps each package to a test Type and runner. For any package it still
   returns `UNKNOWN` for (typically a pure library not yet in the matrix), default to boot-only
   validation — the node boots and the package's dependents work — and confirm with the user
   if unsure.

7. **Goal** — one local commit per package bumping it to the user's version, following the
   conventions in "Confirmed Conventions" above. Document the notable upstream changes between
   the old and new version in the commit body and in `progress.md`.
8. **Constraints** — the code must build end to end: the kit builds via SKILL:
   `build-kit-locally` and a variant builds via SKILL: `build-variant-from-local-kits`.
9. **Verification approach** — per-package: a clean single-package build (SKILL:
   `build-package`). Phase B: a successful full kit + variant build. Phase C (if in scope):
   the Type-specific test from SKILL: `test-third-party-package`, with results and command
   snippets recorded.

### Step 2: Write the Spec

The strategy is to use SKILL: `update-package` to produce the code change for each package,
then validate and commit it before moving to the next. Structure the work as ordered stages:

- **Stage 1 — Package updates.** One task per package: update (Cargo.toml, spec, patches via
  SKILL: `update-package`) → build with SKILL: `build-package` → commit one local commit
  `packages: update <package-name> to <new-version>`. The agent rotates GPG keys and rebases
  patches autonomously; if a package still cannot be completed, it is marked BLOCKED and the
  next package proceeds (see "Confirmed Conventions").
- **Stage 2 — Build kit.** After all packages are updated, build and publish the kit once via
  SKILL: `build-kit-locally`.
- **Stage 3 — Build variant.** Build a variant image from the local kit via SKILL:
  `build-variant-from-local-kits`.
- **Stage 4 — Functional tests (optional, supervised).** Only if Phase C is in scope. One
  task per Type from SKILL: `test-third-party-package`. Flag destructive tests for human
  oversight.

Each package gets its own commit. Use the format from SKILL: `update-package`:
`packages: update <package-name> to <new-version>`. Record removed/rebased patches and notable
upstream changes in the commit body.

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
- For Stage 1, each task updates exactly ONE package and ends by committing it. The `Verify:`
  command is the single-package build (e.g. `PACKAGE=<pkg> make twoliter build-package -e BUILDSYS_UPSTREAM_SOURCE_FALLBACK=true`).
- Tasks MUST have a `Verify:` command that the agent can run to confirm success.
- Order tasks so each builds on the previous (the agent works top-to-bottom): all Stage 1
  package tasks, then the Stage 2 kit build, then the Stage 3 variant build, then Stage 4 tests.
- Group tasks by stage from the delegation plan.
- Keep task count reasonable. For package bumps this is roughly one task per package plus the
  kit/variant build tasks; size `max_iterations` to match (see Step 5).
- A task that only runs a build/test suite to verify prior work is valid (e.g., "Build the
  full kit", "Build the variant image").
- Include a final verification task per stage.

**Blocked tasks.** The loop selects the first task still marked `- [ ]`. When a package cannot
be completed autonomously (build still fails after GPG-key rotation and patch rebasing, or it
needs a human decision), the agent marks that task `- [-]` (BLOCKED) instead of `- [x]`, logs
why in `progress.md`, and the loop moves on to the next package. Document this marker in
`tasks.md` so reviewers can find skipped packages.

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
Copy it and update these variables to the ACTUAL forest path (do not assume the placeholder
default — derive it, e.g. with `git rev-parse --show-toplevel` from the forest root):

```bash
FOREST_ROOT="/path/to/bottlerocket-forest"
GROVE_DIR="$FOREST_ROOT/groves/<grove-name>"
SPEC_DIR="$FOREST_ROOT/planning/<feature-name>"
SPEC_FILE="$SPEC_DIR/spec.md"
```

**Size `max_iterations`.** The loop completes at most one task per iteration, and a BLOCKED
task still consumes an iteration. Set the default `MAX_ITERATIONS` in the script to at least
`(number of tasks) + a small buffer` for occasional retries. For example, 17 package tasks +
1 kit build + 1 variant build = 19 tasks, so default to ~25. Users can still override via the
first CLI argument.

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
- [ ] Every package was located in its kit and (if Phase C is in scope) classified, with no
      unresolved `UNKNOWN`.
- [ ] Kubernetes packages have their `releasever` target captured (user-provided,
      authoritative); `gover`/URL resolution is delegated to the task per `update-package`.
- [ ] Every acceptance criterion is referenced by at least one task.
- [ ] Every task has a Verify command; Stage 1 tasks end with a per-package commit using
      `packages: update <package-name> to <new-version>`.
- [ ] Tasks are ordered so dependencies come first (all updates → kit build → variant build →
      optional tests).
- [ ] Progress file exists with the empty header.
- [ ] ralph-loop.sh points at the real forest path, has `MAX_ITERATIONS` sized to the task
      count, and is executable.
- [ ] The grove exists (or instructions to create it are provided).
