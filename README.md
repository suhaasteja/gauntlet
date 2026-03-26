# Gauntlet 🛡️

> **Your PRD runs the gauntlet.**

Gauntlet is a bash-based CLI tool that spawns persona-based AI agents to adversarially red-team a Product Requirements Document (PRD) against a codebase, producing a structured feasibility report.

Think of it as a multi-agent code review system where each agent has a different expertise (engineer, QA, PM, UX, security, DevOps) and actively stress-tests your PRD's claims against what's actually built.

---

## Features

- **Multi-Persona Review** - 6 specialized AI agents (engineer, qa, pm, ux, security, devops)
- **Adversarial Scenarios** - Generates stress-test scenarios for high-risk sections
- **Risk-Based Triage** - Focuses deep review on high-risk areas
- **Lock-Free Parallelism** - Multiple agents run concurrently using atomic filesystem operations
- **Structured Output** - Markdown report with severity rankings and feasibility scores
- **Iterative Rounds** - Orchestrator decides if deeper investigation is needed

---

## Architecture

```
PRD → Analyzer (splits sections)
      ↓
    Triage (scores risk 1-5)
      ↓
    Scenario Generator (creates failure scenarios for high-risk sections)
      ↓
    Persona Reviews (parallel agents review section + scenarios against codebase)
      ↓
    Orchestrator (evaluates findings, decides if more rounds needed)
      ↓
    Report Generator (aggregates findings into markdown)
```

**Agent Types:**
- **Analyzer** - Splits PRD into reviewable sections
- **Triage** - Scores sections by risk (security, complexity, ambiguity)
- **Scenario Generator** - Creates adversarial stress-test scenarios
- **Personas** - 6 specialized reviewers (engineer, qa, pm, ux, security, devops)
- **Orchestrator** - Evaluates round results, decides if more rounds needed

---

## Prerequisites

1. **jq** - JSON processor
   ```bash
   brew install jq
   ```

2. **AI Tool** - One of:
   - [Amp CLI](https://github.com/codeium/amp) (recommended)
   - [Claude CLI](https://github.com/anthropics/claude-cli)

3. **API Keys** - Set up your chosen AI tool with API credentials

---

## Quick Start

```bash
# Clone or download Gauntlet
cd gauntlet

# Run with defaults (all personas, 3 rounds, amp)
./gauntlet.sh --prd docs/my-prd.md --codebase ../my-project

# Custom configuration
./gauntlet.sh \
  --prd docs/feature-spec.md \
  --codebase ../backend \
  --personas engineer,qa,security \
  --tool claude \
  --max-rounds 2 \
  --parallel 6
```

---

## Configuration

### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--prd FILE` | Path to PRD document | *required* |
| `--codebase DIR` | Path to codebase root | `.` |
| `--personas LIST` | Comma-separated personas | `all` |
| `--tool amp\|claude` | AI tool to use | `amp` |
| `--max-rounds N` | Maximum review rounds | `3` |
| `--parallel N` | Max parallel agents | `4` |
| `--risk-threshold N` | Min risk score for deep review | `3` |
| `--output DIR` | Report output directory | `./output` |

### Available Personas

- **engineer** - Technical feasibility, architecture, complexity
- **qa** - Testability, acceptance criteria, edge cases
- **pm** - Scope, prioritization, timeline risk
- **ux** - User flows, error states, accessibility
- **security** - Auth, data protection, vulnerabilities
- **devops** - Infrastructure, deployment, scalability

---

## How It Works

### 1. PRD Analysis
The **Analyzer** agent reads your PRD and splits it into logical sections (e.g., "User Authentication", "Dashboard UI", "Payment Processing"). Each section becomes a reviewable unit.

### 2. Risk Triage
The **Triage** agent scores each section 1-5 based on:
- Security sensitivity (payments, auth, PII)
- External dependencies (third-party APIs)
- Vague requirements ("handle gracefully", "should scale")
- Missing code (greenfield features)
- Complexity (cross-cutting concerns, state management)

### 3. Scenario Generation
For high-risk sections (score ≥ threshold), the **Scenario Generator** creates adversarial stress-test scenarios:
- Network failures (timeouts, 503s, DNS issues)
- Concurrency (race conditions, duplicate requests)
- Scale (10x load, resource exhaustion)
- Bad input (injection, boundary values)
- Partial failures (crashes mid-operation)
- User behavior (retries, back-button, session expiry)
- Third-party failures (API changes, rate limits)

### 4. Persona Reviews
Multiple **Persona** agents run in parallel, each claiming reviews from a lock-free queue. Each persona:
- Reads the PRD section
- Reads the stress-test scenarios
- Explores the codebase (grep, read files, check tests)
- Compares PRD claims vs. code reality
- Tests against scenarios
- Documents findings with severity and evidence

### 5. Orchestrator Evaluation
After each round, the **Orchestrator** evaluates:
- Are there critical/high findings that need deeper investigation?
- Are personas contradicting each other?
- Are there code areas mentioned but not yet reviewed?
- Is the analysis converging or discovering new issues?

**Decision:** `MORE_ROUNDS` (continue), `SUFFICIENT` (stop), or `STUCK` (blocked)

### 6. Report Generation
The **Report Generator** aggregates all findings into a structured markdown report:
- Executive summary with overall feasibility score
- Section-by-section analysis with persona verdicts
- All findings grouped by severity
- Recommendations for critical/high issues
- Round summaries with orchestrator reasoning

---

## Directory Structure

```
gauntlet/
├── gauntlet.sh              # Main orchestrator
├── README.md                # This file
├── lib/
│   ├── util.sh              # Logging, timestamps, helpers
│   ├── agent.sh             # Agent lifecycle management
│   ├── review.sh            # Review queue operations
│   └── report.sh            # Report generation
├── prompts/
│   ├── analyzer.md          # PRD section splitter
│   ├── triage.md            # Risk scorer
│   ├── scenario-generator.md # Stress-test scenario creator
│   ├── orchestrator.md      # Round evaluator
│   └── personas/
│       ├── engineer.md
│       ├── qa.md
│       ├── pm.md
│       ├── ux.md
│       ├── security.md
│       └── devops.md
├── state/                   # Generated during runs (gitignored)
│   ├── config.example.json  # Example configuration
│   ├── prd-sections/        # Parsed PRD sections
│   ├── scenarios/           # Generated scenarios
│   ├── reviews/             # Persona findings
│   ├── agents/              # Active agent registry
│   ├── rounds/              # Round summaries
│   └── logs/                # Per-agent logs
└── output/                  # Generated reports
    └── report.md
```

---

## Example Output

```markdown
# PRD Feasibility Report

**Generated:** 2026-03-25T14:30:00Z
**Rounds Completed:** 2
**Personas Active:** 6
**Total Findings:** 23

---

## Executive Summary

**Overall Feasibility Score:** 62/100

**Findings Breakdown:**
- 🔴 Critical: 2
- 🟠 High: 5
- 🟡 Medium: 8
- 🟢 Low: 6
- ℹ️ Info: 2

---

## Section-by-Section Analysis

### SEC-001: User Authentication

**Risk Score:** 4/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|
| engineer | ⚠️ Caution (6/10) | 3 findings, 1 high+ |
| security | ❌ Blocked (3/10) | 4 findings, 2 high+ |
| qa | ⚠️ Caution (5/10) | 2 findings, 1 high+ |

---

## All Findings by Severity

### 🔴 CRITICAL (2)

**[OAuth tokens stored in localStorage]** (SEC-001, security)

PRD Section 3.1 requires OAuth authentication, and the implementation stores access tokens in localStorage (src/auth/tokenManager.ts:15). This is vulnerable to XSS attacks...

- **Code:** src/auth/tokenManager.ts:15-25, src/auth/oauth.ts:90-100
- **PRD:** Section 3.1: OAuth authentication
- **Recommendation:** Store tokens in httpOnly cookies, not localStorage. Implement token rotation. Add CSP headers.
```

---

## Key Design Decisions

### Lock-Free Task Claiming
Reviews are claimed using atomic `mv` operations - no locks needed. If two workers try to claim the same review, one wins via filesystem atomicity and the other retries with a different review.

### Fresh Context Per Agent
Each agent iteration is a fresh AI instance. Memory persists only via state files (sections, reviews, rounds). This prevents context pollution and allows unlimited parallelism.

### Small, Focused Reviews
Each review is (persona × section), completable in one AI invocation. This keeps context windows manageable and allows fine-grained parallelism.

### Scenario-Based Probing
High-risk sections get adversarial scenarios that stress-test PRD claims. This shifts from passive "does code exist?" to active "does code handle this failure mode?"

---

## Comparison to Mr. Burns

Gauntlet is inspired by [Mr. Burns](https://github.com/codeium/mrburns) but serves a different purpose:

| Aspect | Mr. Burns | Gauntlet |
|--------|-----------|----------|
| **Purpose** | Build features from goals | Review PRD feasibility |
| **Agents** | Executive, Planner, Worker | Analyzer, Triage, Personas, Orchestrator |
| **Output** | Code changes, git commits | Feasibility report, findings |
| **Git** | Creates branches, merges | Read-only, no changes |
| **Parallelism** | Workers on tasks | Personas on reviews |
| **State** | Tasks, agents, progress | Sections, scenarios, reviews |

Both use lock-free `mv` claiming and bash orchestration with AI CLI tools.

---

## Troubleshooting

### "jq: command not found"
Install jq: `brew install jq`

### "amp: command not found"
Install amp CLI or use `--tool claude`

### "No completion signal detected"
The AI agent didn't output the expected `<gauntlet>` signal. Check `state/logs/` for details. This usually means the agent ran out of context or encountered an error.

### Agents claiming the same review
This shouldn't happen due to atomic `mv`, but if it does, check filesystem atomicity support. Some network filesystems don't guarantee atomic renames.

### Reviews stuck in "claimed" status
Run cleanup: `rm state/reviews/*.json state/agents/*.json` and restart.

---

## Extending Gauntlet

### Add a New Persona

1. Create `prompts/personas/yourpersona.md` with role definition
2. Add to `--personas` list when running
3. The persona will automatically participate in reviews

### Customize Risk Scoring

Edit `prompts/triage.md` to adjust risk heuristics (e.g., add domain-specific signals)

### Add New Scenario Categories

Edit `prompts/scenario-generator.md` to include new failure modes

### Change Report Format

Edit `lib/report.sh` to customize markdown output

---

## License

MIT

---

## Credits

Inspired by [Mr. Burns](https://github.com/codeium/mrburns) and Cursor's research on autonomous coding agents.

Built with bash, jq, and AI CLI tools (Amp/Claude).
