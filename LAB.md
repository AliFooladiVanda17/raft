# LAB: etcd-io/raft

Lab fork of [etcd-io/raft](https://github.com/etcd-io/raft) for step 2 of the verification-research programme. Upstream code is unchanged; lab work lives on the `lab` branch, and this file is its log. The knowledge-base notes this lab builds on are in `../verification-research`: [Raft](../verification-research/papers/2014-ongaro-raft/), [trace validation](../verification-research/papers/2024-cirstea-trace-validation/), [Mocket](../verification-research/papers/2023-wang-mocket/), [ModelFuzz](../verification-research/papers/2025-gulcan-modelfuzz/) and gaps G1–G2.

## Pin

| | |
|---|---|
| Upstream | `https://github.com/etcd-io/raft.git`, branch `main` |
| Base commit | `99f9ffb3d19c2dee73cc802737cd7e1e5f008986` (2026-11-11, "Merge pull request #555 … go1.26.11") |
| Go required | `go 1.26`, toolchain `go1.26.11` (`go.mod`) |
| Local tools | Java 25.0.1 present (enough for TLC). **Go not installed yet.** |

## Pinned tools

Kept outside the repo, in `../tools/tla/`. [`lab/run-tlc.sh`](lab/run-tlc.sh) reproduces the runs below.

| Jar | Source | Size (bytes) | SHA-256 |
|-----|--------|-------------:|---------|
| `tla2tools-1.8.0.jar` (TLC 2026.11.15.002146, rev `bc1b506`) | [tlaplus v1.8.0 release](https://github.com/tlaplus/tlaplus/releases/tag/v1.8.0) (pre-release, 2026-11-15) | 4,510,884 | `7e53aa636dac8a3cb0533f343115c0548e03fc0ce5edc7739becf58d3d0fb84f` |
| `CommunityModules-deps-202611060952.jar` | [CommunityModules 202611060952](https://github.com/tlaplus/CommunityModules/releases/tag/202611060952) | 4,930,534 | `a3b27c40f1fb5085f30c6ead37e918457f8cfc62c1e50a1dc668ef592ad2b5fb` |

Sizes match the GitHub release assets. **Why not the last stable TLC (v1.7.4, 2024-08-08):** every CommunityModules build tried, from September 2024 and from November 2026, fails under it with `NoClassDefFoundError: tlc2/value/impl/KSubsetValue`, raised from the `FiniteSetsExt` override. CommunityModules tracks TLC's nightly builds. That is why the upstream scripts download `nightly` + `latest`, and why a pinned run needs a TLC newer than 1.7.4.

Machine: 20 cores, 23.7 GB RAM, Windows 11, Java 25.0.1.

## What is here (survey, 2026-11-17)

**TLA+ setup, `tla/`.** Added in `195edd6` (2024-04-18, "etcd Raft TLA+ Trace Validation"). The only later change is `96b36c4` (2025-12-21, a division-by-zero fix in `StepToNextTrace`).

| File | Lines | Role |
|------|------:|------|
| `etcdraft.tla` | 926 | Spec of the library's algorithm, including joint-consensus reconfiguration, learners, snapshots, restarts, message drop and duplication (`NextUnreliable`) |
| `MCetcdraft.tla` / `.cfg` | 119 / 68 | Model-checking wrapper |
| `Traceetcdraft.tla` / `.cfg` | 478 / 74 | Trace-validation spec; reads NDJSON traces via the `Json` and `IOUtils` community modules |
| `validate-model.sh`, `validate.sh` | 51, 191 | Bash drivers. They download the **nightly** `tla2tools.jar` and the **latest** `CommunityModules-deps.jar`, so versions are not pinned |
| `example.ndjson` | 4,888 | Example trace |

Invariants in `etcdraft.tla` include `LogInv`, `MoreThanOneLeaderInv`, `ElectionSafetyInv`, `LogMatchingInv`, `QuorumLogInv`, `MoreUpToDateCorrectInv`, `LeaderCompletenessInv` and `CommittedIsDurableInv`.

**Trace emission in Go.** `state_trace.go` (339 lines, build tag `with_tla`) emits 19 event kinds through `Config.TraceLogger`: `InitState`, `Ready`, `BecomeCandidate`, `BecomeFollower`, `BecomeLeader`, `Commit`, `Replicate`, `ChangeConf`, `ApplyConfChange`, send and receive of `RequestVote` and `AppendEntries` requests and responses, `SendSnapshot` and `ReceiveSnapshot`. `state_trace_nop.go` compiles them out otherwise.

**Deterministic test driver.** `rafttest/` contains the data-driven *interaction* environment (deliver messages, tick, campaign, propose, conf change, snapshot, …), with 28 scenario files in `testdata/`. It plays the role of CCF's scenario driver.

## Findings so far

1. **No CI job runs trace validation here.** None of the `.github/workflows` files mention `tla` or `with_tla`, and the `Makefile` doesn't either. Whether `etcd-io/etcd` runs it was not checked. The knowledge base currently says etcd "adopted" the tooling (Cirstea §6). That is true of the code, but it is not evidence of CI use.
2. **The trace producer for `example.ndjson` is not in the repo.** Its log lines name `rafttest/trace_logger.go:42`, a file that never existed in this repository's history. To validate traces we have to write the logger ourselves.
3. **PreVote and CheckQuorum are not modelled.** `etcdraft.tla` contains neither, although the library implements both (`testdata/prevote*.txt`, `checkquorum.txt`). This matches the open question in the Raft assessment.
4. **`UpdateTerm` is a separate disjunct of `Receive`** (`etcdraft.tla` line 664). That is the pattern Mocket reported as Raft spec bug #1 and CCF handles with action composition. `Traceetcdraft.tla` does not mention `UpdateTerm`; how it matches merged term updates is still to be read.

## Experiments

| # | Experiment | Status |
|---|-----------|--------|
| E0 | Clone, pin, survey (this file) | done |
| E1 | Run TLC on `MCetcdraft` with **pinned** `tla2tools.jar` and `CommunityModules-deps.jar` versions, and record states, time and the invariants checked | done (bounded), see below |
| E2 | Validate `example.ndjson` with `Traceetcdraft`: record states, time and verdict | prefixes done; full trace not finished in 25 min, see below |
| E3 | Write a `TraceLogger` for the interaction environment (`go test -tags=with_tla`), emit one trace per `testdata/*.txt` scenario, and validate all 28 | needs Go |
| E4 | Seed a known bug (e.g. ModelFuzz's quorum `n/2+1 → n/3+1`) and check whether E3's traces are rejected | |
| E5 | Read how `Traceetcdraft` handles `UpdateTerm` (finding 4) | |
| E6 | Spec delta for PreVote and CheckQuorum, then validate `prevote*.txt` and `checkquorum.txt` traces (Raft assessment, idea 1) | |

## Results

### E1: bounded model checking of `MCetcdraft` (2026-11-18)

Config `MCetcdraft.cfg` unchanged: `InitServer = {s1,s2,s3}`, `Server = {s1..s4}`, `ReconfigurationLimit = 2`, `MaxTermLimit = 10`, `RequestLimit = 5`, with `SYMMETRY` and `VIEW` and the 8 invariants listed above. BFS, 16 workers, 8 GB heap, stopped by a **20-minute** wall-clock limit. Log: [`lab/results/E1-model-check.log`](lab/results/E1-model-check.log).

| Measure | Value |
|---------|-------|
| Initial states | 1 |
| Depth reached | 16 |
| States generated | 75,795,295 |
| Distinct states | 14,629,034 |
| Queue when stopped | 10,515,084, still growing |
| Rate | ≈ 0.8 M distinct/min while E2 ran in parallel, ≈ 1.2 M/min alone |
| Invariant violations | **none** |
| State directory | 1.8 GB on disk after 20 min |

**Reading.** This is **not** an exhaustive check. The frontier grows by about 0.6 M states per minute at depth 16, so the configured model is far beyond a 20-minute run on this machine. That matches the upstream README ("at least hours"). The result is "no violation in the first 16 BFS levels", which says nothing about deeper behaviours, e.g. two reconfigurations plus a term change. A useful E1 for CI needs a smaller config, or TLC's simulation mode with a time budget, as CCF did (§4 of its paper).

### E2: validation of `tla/example.ndjson` (2026-11-18)

The trace has 4,888 lines from 10 `InitState` events, 1 leader election, 9 `ChangeConf` and 134 `ApplyConfChange`, and is dominated by `AppendEntries` traffic. It was preprocessed exactly as `validate.sh` does: strip any prefix before `{`, then `sort -t: -k 3`, which reorders the file. BFS with **one worker** (the spec `ASSUME`s both). Acceptance is the temporal property `TraceMatched` plus `etcdSpec` and the 7 invariants in `Traceetcdraft.cfg`.

| Run | Trace lines | Verdict | Distinct states | Depth | Time | Log |
|-----|------------:|---------|----------------:|------:|-----:|-----|
| E2b | first 1,000 (`MAX_TRACE=1000`) | **accepted** ("No error has been found") | 1,031 | 1,031 | 51 s | [log](lab/results/E2b-example-trace-prefix1000.log) |
| E2c | first 2,000 (`MAX_TRACE=2000`) | **accepted** | 2,040 | 2,040 | 2 min 50 s | [log](lab/results/E2c-example-trace-prefix2000.log) |
| E2 | all 4,888 | **not finished**: stopped at 25 min at 39% progress (1,971 distinct states), no violation so far | ≥ 1,971 | — | > 25 min | [log](lab/results/E2-example-trace.log) |

Observations:

1. **One state per trace line.** The state graph has outdegree at most 1 (E2b: "minimum is 0, the maximum 1"), and depth ≈ lines + the bootstrap steps. Logging is precise enough that TLC never branches: Cirstea et al.'s full-information case, $|T| = 1$.
2. **Cost grows faster than trace length.** Doubling the prefix from 1,000 to 2,000 lines multiplied the time by 3.3. In the full run, the first ~1,200 states took ≈ 9 min **alone** (≈ 0.45 s per state), against ≈ 0.05 s per state in E2b. So per-state cost depends on the length of the **whole** loaded trace, not just the position. *Our hypothesis, not yet checked:* operators that scan the full `TraceLog` (e.g. `BootstrapLogIndices`, `SelectInSeq`) are re-evaluated per state. This matters for online use in `raft-sim` (G1), where the checker must stay cheap per step. It is E7 below.
3. **The full run was confounded.** E1 ran in parallel from minute 12, and E2's rate fell from ≈ 130 to ≈ 30 states/min. A clean full-trace timing needs a run alone.
4. **The acceptance condition differs from the paper.** `Traceetcdraft` checks `TraceMatched == [](l <= Len(TraceLog) => [](TLCGet("queue") = 1 \/ l > Len(TraceLog)))`, a "poor man's hyperproperty" that only works with one BFS worker. Cirstea et al. describe a `TraceAccepted` postcondition on the graph diameter (§4.2). The etcd spec also checks `etcdSpec`, refinement of the trace behaviours into `NextDynamic`, which the paper's generic module does not.

### Follow-ups from E1–E2

| # | Experiment | Status |
|---|-----------|--------|
| E2-full | Validate all 4,888 lines with nothing else running; record the time | |
| E7 | Profile why per-state cost scales with total trace length (TLC `-coverage`, or the profiler); try caching the `TraceLog`-wide operators | |
| E1b | A CI-sized config (3 servers, `MaxTermLimit = 3`, `RequestLimit = 2`) that finishes exhaustively, plus a time-budgeted `-simulate` run of the full config | |

## Notes for Windows

The `validate*.sh` scripts assume GNU tools (`wget`, `nproc`, `sed -i`, `mktemp`). Run them under Git Bash or WSL, or call TLC directly with `java -cp tla2tools.jar;CommunityModules-deps.jar tlc2.TLC …`; note the `;` path separator on Windows. `lab/run-tlc.sh` picks the separator automatically and **does not** modify `tla/example.ndjson`, unlike `validate.sh`, which edits traces in place with `sed -i` and `sort -o`.
