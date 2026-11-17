---
name: rust-coverage-prune
description: Find Rust code that never runs in real end-to-end use, and functions or parameters whose values never vary, using LLVM source-based coverage and a return-value tracer; classify every unexecuted region, write an evidence-backed report, and optionally remove the code on a local branch that is rebuilt and re-verified end to end. Use when asked to slim down a large Rust PR or crate, find dead, redundant or never-hit code, or find functions that always return the same value.
---

# Prune Rust code with LLVM coverage

Measure which code real end-to-end runs execute and which values never vary, read every
unexecuted region, and remove only what has a structural reason to be unnecessary.

Prefer this to GDB breakpoints or print statements in every function: coverage counts every
function, line and branch region exactly, needs no source edits, and follows the code into
child processes and embedded binaries.

## Inputs

Settle these first. Ask only what the code and the request cannot answer.

- **Code under study:** the files of interest (for a PR, `git diff --name-only <merge-base> -- '*.rs'`)
  and the crates that hold them.
- **Binaries:** every binary crate whose process runs that code, including binaries embedded in
  or spawned by others.
- **Entry point and scenarios:** the command a real user runs, and the inputs to run it on (Step 2).
- **Outcome:** a report only (default), or also a slimmed local branch. Never push.

## Layout

`$SKILL` is this skill's directory. `$S` is a scratch directory outside the checkout, or ignored
by git. The checkout under study stays pristine; tracing edits go into a separate worktree.

```
$S/target-cov  $S/target-cov-test  $S/target-rt   one target dir per build kind
$S/cov/<scenario>/*.profraw  $S/cov/unit  $S/cov/junk
$S/runs/<scenario>/          kept work dirs and outputs
$S/rt/<scenario>/            rettrace dumps
$S/analysis/                 merged profiles, exports, listings
```

## Step 1: Coverage build

```sh
cd <repo>                              # so rust-toolchain.toml selects the toolchain
rustup component add llvm-tools        # must match rustc's LLVM; system llvm-cov will not do
cargo install rustfilt
export COV_CRATES="my_lib my_tool"     # rustc crate names, `-` as `_`
RUSTC_WRAPPER=$SKILL/scripts/rustc-cov-wrapper.sh CARGO_TARGET_DIR=$S/target-cov \
  cargo build --release -p <binary package>
```

- **List the binary crates in `COV_CRATES`, not only the libraries.** A binary whose own crate is
  not instrumented links, even carries `__llvm_covmap`, but writes no profile.
- The wrapper beats `RUSTFLAGS`: `RUSTFLAGS` replaces `build.rustflags` from `.cargo/config.toml`
  and instruments every dependency. The wrapper also reaches binaries built as artifact
  dependencies (`bindeps`) or by build scripts, since every rustc call goes through it.
- It replaces any other `RUSTC_WRAPPER`, such as sccache.
- Cargo does not rebuild when `COV_CRATES` changes. Use a fresh target dir for a new set.

Confirm every binary is instrumented, including embedded ones
(`find $S/target-cov -path '*artifact*' -type f -perm -u+x` finds bindeps):

```sh
readelf -S <bin> | grep -c __llvm_covmap                     # nonzero
LLVM_PROFILE_FILE=/tmp/probe-%p.profraw <bin> --help; ls /tmp/probe-*.profraw
```

Unit tests, to tell "no test reaches it" from "only tests reach it". Install what `#[ignore]`d
tests need and include them:

```sh
RUSTC_WRAPPER=$SKILL/scripts/rustc-cov-wrapper.sh CARGO_TARGET_DIR=$S/target-cov-test \
  LLVM_PROFILE_FILE=$S/cov/unit/%p-%m.profraw cargo test -p <pkg> -- --include-ignored
# The unit-test objects for Step 3 (paths vary with the cargo layout; do not glob):
RUSTC_WRAPPER=$SKILL/scripts/rustc-cov-wrapper.sh CARGO_TARGET_DIR=$S/target-cov-test \
  cargo test -p <pkg> --no-run --message-format=json | jq -r 'select(.profile.test) | .executable'
```

## Step 2: Run scenarios

The scenarios define what "never runs" means, so span the real input space. Each of these
reached code the others did not:

- every supported flavor of input (variants, architectures, feature combinations);
- an old or unsupported input that should fail;
- the case the code under study exists for, with inputs it produced itself;
- a rerun that reuses earlier state, and a run without "keep" flags, for the cleanup path;
- an interruption mid-run (SIGINT to the process group), for cancellation;
- a tampered input that must be rejected (flip one bit).

```sh
mkdir -p $S/cov/<scenario>
LLVM_PROFILE_FILE=$S/cov/<scenario>/%p-%m.profraw <bin> <args> > $S/runs/<scenario>.out 2>&1
```

- `%p` gives every process its own file; children inherit the variable. `%m` separates binaries.
- Profiles are written at normal exit. A process that is killed or aborts writes none.
- Send incidental runs of an instrumented binary, such as a build that makes a scenario's input,
  to `$S/cov/junk`.
- Keep each scenario's work dir, so a cheap stage can be replayed without the expensive ones.
- Instrumented binaries are slower. Run independent scenarios in parallel and watch disk.
- Record each result and why. A scenario that fails for the wrong reason covers the wrong code.
- Delete any cloud resources a scenario creates once it is no longer needed.

## Step 3: Coverage analysis

```sh
python3 -I $SKILL/scripts/cov-analyze.py --src <repo> --cov $S/cov --out $S/analysis \
  --object <bin> [--object <bin>]... [--unit-object <test bin>]... <files relative to repo>...
```

It merges the profiles per scenario, for all scenarios (e2e) and for the unit tests, and writes:

- `cov-functions.json`: each function's demangled name, file and first line, with its call count
  end to end, per scenario and in unit tests; generic instantiations combined;
- `cov-regions.json`: never-executed regions inside functions that did run;
- `uncovered/<file>`: never-run lines in contiguous blocks tagged `unit:all|some|none`, `U`
  marking lines the unit tests run;
- `annotated/<file>`: `llvm-cov show` listing; `report.txt`: per-file summary.

Reading it:

- "no coverage data for <file>" means it was not instrumented or is in none of the objects. Fix
  the build before reading anything else.
- Expect far more functions than named ones: every closure is its own function, and derives and
  tests count too.
- A never-called `async fn` shows a count of 0 on its first line only; its body has none. Read
  the whole function.

## Step 4: Values that never vary (optional)

Use this when the question includes functions that always return the same value, or parameters
that never vary.

- `$SKILL/rettrace`: `#[::rettrace::trace("label")]` counts calls and records each named argument
  and the return value by a hash of their `Debug` output, capped at 2 KiB. Truncated values never
  count as constant; values without `Debug` are opaque. At exit it writes JSON to `$RETTRACE_DIR`,
  if the process called a traced function.
- `$SKILL/rewriter`: puts the attribute on every non-test, non-const function with a body except
  `main`, on the function's own line, so line numbers match the coverage listings.

```sh
cp -r $SKILL/rettrace $SKILL/rewriter $S/ && (cd $S/rewriter && cargo build --release)
git -C <repo> worktree add --detach $S/src-rt HEAD
cd $S/src-rt && $S/rewriter/target/release/rewriter . <files>...
# In [dependencies] of every rewritten crate: rettrace = { path = "<$S>/rettrace/rettrace" }
CARGO_TARGET_DIR=$S/target-rt cargo build --release -p <binary package>   # no wrapper, no --locked
mkdir -p $S/rt/<scenario> && RETTRACE_DIR=$S/rt/<scenario> <traced bin> <args>
python3 -I $SKILL/scripts/rt-analyze.py --rt $S/rt --out $S/analysis
```

- Check `[workspace.lints]` first: the injected code must not trip a `deny`.
- If one function will not compile with the attribute, remove it from that function.
- Prefer replaying the cheap stage of each kept scenario over rerunning everything. Check that its
  output is byte-identical to the coverage run's, which shows tracing changed nothing.
- `rt-constant.json` lists functions whose return value, or one of whose arguments, took one value
  in every call of every scenario.

## Step 5: Classify

Never-run code is not automatically removable; most of it is error handling. Read every block
in `uncovered/` and every entry in `rt-constant.json`, and put each into one group:

1. Error handling, or diagnostics for failures that did not occur. Keep.
2. Code that cannot change the outcome, such as a tolerance that could only turn a failure into a
   pass when another check must already have failed. Delete.
3. Code that only excuses a condition that another change in the same PR, or an input the code
   ignores, already removes. Delete, or make that input explicit.
4. Compatibility for older inputs or particular hosts. Decide with the user; often a follow-up PR.
5. Parameters, flags and branches that never vary: a single caller passing a constant (confirm
   with grep), a flag no caller sets. Inline or delete.
6. A separate feature or functional change mixed in. Its own PR.

Rules of evidence:

- Coverage is evidence, not proof. Each removal needs a structural argument for why the code can
  never matter, from how its inputs are really produced. Check that argument's facts across every
  supported version: a rationale true only for the newest version will be challenged.
- A constant counts only if it held in every call of every scenario, or static analysis shows a
  single caller passing it. Constants that follow from the choice of scenarios mean nothing.
- Ask whether planned work needs the code. If it would, keep it, or say what is reusable and
  name the commit where it is preserved.
- A removal that rests on a prediction ("after change X this cannot happen") is a hypothesis
  until Step 8 confirms it end to end.
- Removing a tolerance makes the program stricter. Say what users will see differently.
- Count lines as non-blank production lines, excluding test modules. Measure; do not estimate.

## Step 6: Report

One markdown file:

- **Summary:** whether the code works end to end, blocking findings, and a table of what can go:
  finding, what, non-blank production lines, end-to-end evidence, recommendation (Delete, Inline,
  Own PR, Keep).
- **Method:** the instrumentation, the exact commands, a scenarios table (id, input, result), and
  what the measurements mean: end-to-end and unit line coverage, the groups of Step 5, the rule
  for constants.
- **Findings,** one per removal group: problem, evidence (input and result), conclusion, fix.
- **Appendix:** functions and lines run per file; named functions never run end to end, with unit
  reach and group; values that never varied, with call counts and reading.

Copy the tools and the small text outputs (JSON, listings) next to the report and link them.
Profiles are useless without their instrumented binaries; do not keep them.

## Step 7: Remove (when asked)

- Split the findings into groups whose files and items do not overlap, and tabulate who owns what.
- Write one shared brief:
  - what to read first: the report, and the group's findings;
  - the ownership table, and what is left to the integrator;
  - rules: own worktree, no push, no stash; match the surrounding code; remove dead code fully,
    including imports, helpers, tests and dependencies only it used; no commented-out code;
    conventional commit messages without agent attribution;
  - build, lint and test commands, with a per-group `CARGO_TARGET_DIR`;
  - deliverables: the commits; per removal, What, Why it is safe, Behavior change and Tests; a
    final message with SHAs, `git diff --shortstat`, results and judgment calls.
- Give each group a worktree, branch and target dir (`git worktree add -b slim/<group> <dir> <base>`),
  and one agent if fanning out. Ask the user before fanning out wider than that.
- Integrate on one branch: cherry-pick, resolve conflicts, do the cross-group work, then read the
  shared user-facing text (help, notes, docs) as a whole.
- At the head, run fmt, `clippy --all-targets -- -D warnings` and every test, including ignored
  ones. Fix lint in nearby untouched code in a separate commit.
- Have an independent reviewer look for regressions, given the diff and the intended behavior but
  not your conclusions.

## Step 8: Verify end to end

- Rerun every Step 2 scenario with the slimmed build. Negative cases must still fail, for the right
  reason: assert on the message, not the exit code.
- When a run contradicts a finding, fix the code and the report, and say so under "What testing
  changed". A prediction can fail: a proof predicted removable came back for 2 of 5 real inputs.
- Write the removal document: per group What, Why it is safe, Behavior change and Tests; how the
  work was done (commits, with line deltas); what testing changed; end-to-end results; not done
  here. Measure every number at the branch head before writing it.
- Keep the scenario runner scripts with the report's artifacts.

## Cleanup

- `git worktree remove` each worktree, if clean. Leave branches unless the user says otherwise.
- Delete scratch once the report links nothing in it. Ask first if it holds anything that cannot
  be recreated.
- Delete cloud resources the runs created, and say so in the report.

## Go code

For Go parts of the change: `go build -cover -coverpkg=<module>/...`, run with `GOCOVERDIR=<dir>`,
then `go tool covdata textfmt -i <dir> -o cover.out` and `go tool cover -func cover.out`.

## Reference run

twoliter PR #763 (`twoliter verify ami`; crates reprosys, pcrsys, twoliter), 2026-11-10: eight
scenarios against real AMIs ran 81% of 3,638 executable lines; 548 function records for 191 named
functions; 37 of 144 traced functions had a constant. About 950 of 4,649 production lines were
found removable and 939 removed. If still present, under
`~/Repositories/bottlerocket-forest/groves/jmt-verify/`: `twoliter-763-sdk-402-review.md` (the
report), `twoliter-763-slim-removals.md` (the removal document), `review-artifacts/slim/BRIEF.md`
(the brief) and `review-artifacts/` (tools and outputs).
