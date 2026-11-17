# LAB: etcd-io/raft

Lab fork of [etcd-io/raft](https://github.com/etcd-io/raft) for step 2 of the verification-research programme. Upstream code is unchanged; lab work lives on the `lab` branch, and this file is its log. The knowledge-base notes this lab builds on are in `../verification-research`: [Raft](../verification-research/papers/2014-ongaro-raft/), [trace validation](../verification-research/papers/2024-cirstea-trace-validation/), [Mocket](../verification-research/papers/2023-wang-mocket/), [ModelFuzz](../verification-research/papers/2025-gulcan-modelfuzz/) and gaps G1–G2.

## Pin

| | |
|---|---|
| Upstream | `https://github.com/etcd-io/raft.git`, branch `main` |
| Base commit | `99f9ffb3d19c2dee73cc802737cd7e1e5f008986` (2026-11-11, "Merge pull request #555 … go1.26.11") |
| Go required | `go 1.26`, toolchain `go1.26.11` (`go.mod`) |
| Local tools | Java 25.0.1 present (enough for TLC). **Go not installed yet.** |

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
| E1 | Run TLC on `MCetcdraft` with **pinned** `tla2tools.jar` and `CommunityModules-deps.jar` versions, and record states, time and the invariants checked | next |
| E2 | Validate `example.ndjson` with `Traceetcdraft`: record states, time and verdict | |
| E3 | Write a `TraceLogger` for the interaction environment (`go test -tags=with_tla`), emit one trace per `testdata/*.txt` scenario, and validate all 28 | needs Go |
| E4 | Seed a known bug (e.g. ModelFuzz's quorum `n/2+1 → n/3+1`) and check whether E3's traces are rejected | |
| E5 | Read how `Traceetcdraft` handles `UpdateTerm` (finding 4) | |
| E6 | Spec delta for PreVote and CheckQuorum, then validate `prevote*.txt` and `checkquorum.txt` traces (Raft assessment, idea 1) | |

## Notes for Windows

The `validate*.sh` scripts assume GNU tools (`wget`, `nproc`, `sed -i`, `mktemp`). Run them under Git Bash or WSL, or call TLC directly with `java -cp tla2tools.jar;CommunityModules-deps.jar tlc2.TLC …`; note the `;` path separator on Windows.
