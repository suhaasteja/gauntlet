# Gauntlet — CLAUDE.md

Gauntlet is a bash-based multi-agent CLI tool that adversarially reviews a codebase against a Product Requirements Document (PRD). It spawns specialized AI personas (engineer, QA, PM, UX, security, devops) that stress-test PRD claims against actual code and produce a structured feasibility report.

---

## Quick Orientation

```
gauntlet.sh              # Main entry point (~1645 lines), orchestrates everything
lib/
  util.sh                # Logging, JSON helpers, ID generation
  agent.sh               # Agent registry (spawn/track/cleanup)
  review.sh              # Lock-free review queue (claim/complete/release)
  report.sh              # Markdown report generation
  verify.sh              # Verification phase (classify → generate → run → verdict)
prompts/
  analyzer.md            # Splits PRD into sections
  triage.md              # Risk-scores sections 1–5
  scenario-generator.md  # Creates adversarial scenarios per section
  orchestrator.md        # Decides MORE_ROUNDS / SUFFICIENT / STUCK
  personas/
    engineer.md          # Technical feasibility, architecture
    qa.md                # Testability, edge cases, regression risk
    security.md          # Auth, input validation, data exposure
    pm.md                # Scope, dependencies, timeline risk
    ux.md                # User flows, error states, accessibility
    devops.md            # Infrastructure, deployment, scalability
  finding-classifier.md  # Classifies findings as unit/integration/untestable
  test-generator.md      # Writes one adversarial test per finding
  verifier.md            # Interprets test result → verdict
state/                   # All runtime state (JSON files, no DB)
output/                  # Final reports and verified tests
```

---

## Invocation

```bash
# Minimal
./gauntlet.sh --prd docs/prd.md --codebase /path/to/app

# Common options
./gauntlet.sh \
  --prd spec.md \
  --codebase . \
  --personas engineer,qa,security \
  --tool claude \            # 'amp' or 'claude' (default: claude)
  --model claude-sonnet-4-5 \
  --max-rounds 2 \
  --parallel 4 \
  --verify                   # Enable verification phase

# Verify-only (re-run verification on existing state)
./gauntlet.sh --verify-only --codebase . --report output/report.md

# Include Medium severity findings in verification
./gauntlet.sh --prd spec.md --codebase . --verify --verify-all
```

**Key flags:**

| Flag | Default | Purpose |
|------|---------|---------|
| `--prd` | required | PRD file path |
| `--codebase` | `.` | Codebase root |
| `--personas` | all 6 | Comma-separated list |
| `--tool` | `claude` | AI CLI: `amp` or `claude` |
| `--model` | `claude-sonnet-4-5` | Model name |
| `--max-rounds` | 3 | Max review rounds |
| `--parallel` | 4 | Max concurrent agents |
| `--risk-threshold` | 3 | Min risk score to generate scenarios |
| `--output` | `./output` | Report output directory |
| `--verify` | false | Run Gauntlet Verify after review |
| `--verify-only` | false | Skip review, run verify on existing state |
| `--verify-all` | false | Include Medium findings in verify |

---

## Execution Pipeline

### Phase 1: PRD Review

```
Analyzer → Triage → Scenario Generator → [Review Rounds] → Report
```

1. **Analyzer** — Splits PRD into `SEC-001`, `SEC-002`, … sections → `state/prd-sections/*.json`
2. **Triage** — Scores each section 1–5 for risk → updates section files
3. **Scenario Generator** — Parallel; one per section with `riskScore ≥ threshold`. Generates 5–10 adversarial scenarios → `state/scenarios/SEC-XXX-scenarios.json`
4. **Review Rounds** (up to `--max-rounds`):
   - Queue: every `(persona × section)` pair becomes a review item in `state/reviews/`
   - Persona agents run in parallel (up to `--parallel`), each claiming one review atomically
   - After all reviews complete, **Orchestrator** decides `SUFFICIENT` / `MORE_ROUNDS` / `STUCK`
5. **Report** — Aggregates findings → `output/report.md`

### Phase 2: Gauntlet Verify (optional)

```
Finding Classifier → Test Generator → Test Execution → Verdict Analysis → Verified Report
```

1. **Finding Classifier** — Classifies findings: `unit-testable` / `integration-testable` / `untestable`
2. **Test Generator** — Parallel; writes one adversarial test per testable finding
3. **Test Execution** — Runs each test, captures exit code + output
4. **Verdict Analysis** — Parallel; interprets result → `confirmed_vulnerability` / `false_positive` / `inconclusive`
5. **Verified Report** → `output/verified-report.md`, confirmed tests → `output/verified-tests/`

---

## State Directory Layout

```
state/
├── prd-sections/           # { id, title, content, riskScore, riskFactors }
├── scenarios/              # { sectionId, scenarios: [{id, category, description, probe}] }
├── reviews/                # { id, sectionId, persona, status, findings, feasibilityScore }
├── agents/                 # { id, type, persona, status, currentReview, lastHeartbeat }
├── rounds/                 # { round, findingCounts, orchestratorDecision, reasoning }
├── logs/                   # Per-agent stdout logs
└── verify/
    ├── verifications/      # { id, reviewId, finding, testability, verdict, testResult }
    └── generated-tests/    # Raw test files before execution
```

All state is plain JSON. No external database. Safe to inspect/debug with `jq`.

---

## Key Design Patterns

### Lock-Free Concurrency
Review claiming uses atomic filesystem `mv`. The first agent to `mv` the file wins; all others fail and move on. No mutexes, no coordination needed.

### Signal-Based Agent Completion
Every prompt instructs the agent to output a specific XML-style tag when done:
```
<gauntlet>ANALYSIS_COMPLETE</gauntlet>
<gauntlet>REVIEW_COMPLETE:SEC-001:engineer</gauntlet>
<gauntlet>SUFFICIENT</gauntlet>
```
`gauntlet.sh` parses these signals to determine success. Everything else the AI outputs is discarded or logged.

### Fresh Agent Per Task
Each agent invocation is stateless — it reads context from JSON files, does one task, writes output, exits. No shared memory between agents.

### Atomic JSON Writes
All JSON mutations in `lib/util.sh` use:
```bash
jq '...' file.json > file.json.tmp && mv file.json.tmp file.json
```
Prevents partial writes corrupting state on crash.

### Stale Agent Detection
Agents write heartbeats to `state/agents/<id>.json`. Agents silent for >300s are marked stale; their claimed reviews are released back to the pending queue.

---

## Persona Review Output Schema

Every persona outputs the same JSON structure:
```json
{
  "findings": [
    {
      "severity": "critical|high|medium|low|info",
      "category": "feasibility|gap|conflict|risk|suggestion",
      "title": "Brief title (≤50 chars)",
      "finding": "Detailed explanation with evidence",
      "codeEvidence": ["src/auth/login.ts:42-55"],
      "prdReference": "Section 3.2",
      "scenarioRef": "SCEN-001",
      "recommendation": "Actionable fix",
      "effortEstimate": "trivial|small|medium|large|very_large"
    }
  ],
  "summary": "Overall assessment paragraph",
  "feasibilityScore": 7
}
```

---

## AI Tool Differences

| | Amp (`--tool amp`) | Claude (`--tool claude`) |
|--|--|--|
| Permission flag | `--dangerously-allow-all` | `--dangerously-skip-permissions` |
| Output flag | _(none needed)_ | `--print` |
| Model flag | `--model` | `--model` |

When adding new agent runners or modifying `gauntlet.sh`, ensure both tool branches are handled.

---

## Adding a New Persona

1. Create `prompts/personas/<name>.md` following the existing persona format
2. Add `<name>` to the persona list in `gauntlet.sh` (defaults and validation)
3. Ensure the completion signal pattern `REVIEW_COMPLETE:SEC-XXX:<name>` is parsed correctly (it should be — the pattern is generic)

## Modifying a Prompt

Prompts are in `prompts/`. They receive context injected by `gauntlet.sh` before the `---` separator. The AI sees: context first, then the prompt. Completion signals must appear exactly as specified or the orchestration will hang and retry until max attempts.

## Dependencies

- `bash` 4.0+
- `jq` (required — checked at startup)
- `amp` or `claude` CLI on PATH

---

## Output

| File | Contents |
|------|---------|
| `output/report.md` | Full feasibility report with per-severity findings and section verdicts |
| `output/verified-report.md` | Same + verification verdicts for each finding |
| `output/verified-tests/` | Confirmed adversarial test files, ready to add to the test suite |
