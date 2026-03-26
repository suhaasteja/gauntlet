# Gauntlet Test Guide

This directory contains mock data for testing Gauntlet's PRD review capabilities.

## What's Included

### 📄 Sample PRD (`sample-prd.md`)
A realistic Product Requirements Document for a payment processing system with:
- OAuth authentication requirements
- Stripe payment integration
- Subscription management
- Security requirements
- Performance targets
- Testing requirements

### 💻 Mock Codebase (`sample-codebase/`)
A TypeScript/Node.js codebase with **intentional issues** for Gauntlet to discover:

**Security Issues:**
- ❌ OAuth tokens stored in `localStorage` (XSS vulnerable) - `src/auth/tokenManager.ts:15-16`
- ❌ Credit card data logged to console - `src/api/payments.ts:17`
- ❌ No encryption at rest implementation
- ❌ Missing 2FA for high-value transactions

**Architecture Issues:**
- ❌ In-memory session storage (won't scale) - `src/auth/sessionManager.ts:6`
- ❌ In-memory rate limiter (won't work across instances) - `src/utils/rateLimiter.ts:1`
- ❌ Mock database with no real persistence

**Missing Features:**
- ❌ No token refresh before expiration
- ❌ No retry logic for failed payments
- ❌ No webhook handling for Stripe events
- ❌ No proration logic for plan changes
- ❌ No 3D Secure implementation
- ❌ No multi-currency support
- ❌ No fraud detection

**Testing Gaps:**
- ❌ Only 2 basic tests (far from 80% coverage)
- ❌ No integration tests
- ❌ No webhook tests
- ❌ No error handling tests

**Error Handling:**
- ❌ Generic error messages - `src/api/payments.ts:23`
- ❌ No structured error format matching PRD spec
- ❌ Missing rate limit headers

## Running Gauntlet

### Basic Test Run

```bash
cd /Users/mac/Desktop/gauntlet

# Run with all personas
./gauntlet.sh \
  --prd test-data/sample-prd.md \
  --codebase test-data/sample-codebase
```

### Focused Security Review

```bash
./gauntlet.sh \
  --prd test-data/sample-prd.md \
  --codebase test-data/sample-codebase \
  --personas security,engineer \
  --max-rounds 2
```

### Quick QA + DevOps Check

```bash
./gauntlet.sh \
  --prd test-data/sample-prd.md \
  --codebase test-data/sample-codebase \
  --personas qa,devops \
  --parallel 2
```

### High-Risk Sections Only

```bash
./gauntlet.sh \
  --prd test-data/sample-prd.md \
  --codebase test-data/sample-codebase \
  --risk-threshold 4 \
  --max-rounds 1
```

## Expected Findings

Gauntlet should discover issues like:

### 🔴 Critical
- OAuth tokens in localStorage (XSS vulnerability)
- Payment data logged to console
- No encryption at rest
- In-memory session storage won't survive restarts

### 🟠 High
- Missing token refresh logic
- No retry mechanism for failed payments
- No webhook handling
- Rate limiter won't work in multi-instance deployment
- Missing 2FA for high-value transactions

### 🟡 Medium
- Insufficient test coverage (<10% vs 80% requirement)
- No integration tests
- Missing proration logic
- No fraud detection
- Generic error messages

### 🟢 Low / Info
- Missing CSV headers in export
- No database sharding implementation
- Mock database needs replacement

## What to Look For

After running Gauntlet, check the report (`output/report.md`) for:

1. **Section-by-section analysis** - Each PRD section scored by multiple personas
2. **Severity rankings** - Critical issues flagged first
3. **Code citations** - Specific file paths and line numbers
4. **Scenario testing** - How the code handles failure modes
5. **Feasibility scores** - Overall assessment per section
6. **Orchestrator reasoning** - Why it decided to continue/stop rounds

## Tips

- **First run:** Use all personas to get comprehensive coverage
- **Iteration:** Focus on specific personas based on initial findings
- **Performance:** Increase `--parallel` if you have API quota
- **Depth:** Increase `--max-rounds` for complex PRDs
- **Focus:** Adjust `--risk-threshold` to prioritize high-risk areas

## Customization

You can modify the test data:

- **Edit PRD:** Add/remove requirements in `sample-prd.md`
- **Fix issues:** Update code in `sample-codebase/src/` to see how findings change
- **Add features:** Implement missing functionality to improve feasibility scores
- **Add tests:** Expand `tests/` to improve QA persona ratings

## Expected Runtime

- **All personas (6), 3 rounds:** ~5-10 minutes (depends on AI API speed)
- **2 personas, 1 round:** ~1-2 minutes
- **Single persona, 1 round:** ~30-60 seconds

## Troubleshooting

If Gauntlet doesn't find issues:
1. Check that AI tool (amp/claude) is configured correctly
2. Verify the codebase path is correct
3. Try lowering `--risk-threshold` to 1
4. Check `state/logs/` for agent errors

If it finds too many issues:
1. This is expected! The mock codebase has intentional problems
2. Try fixing some issues and re-running to see scores improve
3. Focus on critical/high severity items first
