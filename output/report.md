# PRD Feasibility Report

**Generated:** 2026-03-28T00:36:58Z  
**Rounds Completed:** 1  
**Personas Active:** 6  
**Total Findings:** 39

---

## PRD Analysis Summary

**Total Sections:** 13

**Risk Distribution:**
- 🔴 High Risk (4-5): 11 sections
- 🟡 Medium Risk (3): 1 sections
- 🟢 Low Risk (1-2): 1 sections

**Sections Identified:**

- **SEC-001:** Overview (Risk: 1/5)
- **SEC-002:** OAuth Integration (Risk: 5/5)
- **SEC-003:** Session Management (Risk: 5/5)
- **SEC-004:** Stripe Integration (Risk: 5/5)
- **SEC-005:** Subscription Management (Risk: 5/5)
- **SEC-006:** Transaction History (Risk: 4/5)
- **SEC-007:** API Design (Risk: 4/5)
- **SEC-008:** Security Requirements (Risk: 5/5)
- **SEC-009:** Performance Requirements (Risk: 5/5)
- **SEC-010:** Testing Requirements (Risk: 4/5)
- **SEC-011:** Monitoring & Observability (Risk: 5/5)
- **SEC-012:** Deployment Strategy (Risk: 5/5)
- **SEC-013:** Success Metrics & Timeline (Risk: 3/5)


---

## Executive Summary

**Overall Feasibility Score:** 23/100

**Findings Breakdown:**
- 🔴 Critical: 11
- 🟠 High: 14
- 🟡 Medium: 8
- 🟢 Low: 4
- ℹ️ Info: 2


---

## Section-by-Section Analysis

### SEC-001: Overview

**Risk Score:** 1/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|

### SEC-002: OAuth Integration

**Risk Score:** 5/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|
| devops | ❌ Blocked (2/10) | 11 findings, 7 high+ |

### SEC-003: Session Management

**Risk Score:** 5/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|
| devops | ✅ Good (N/A/10) | 0 findings, 0 high+ |

### SEC-004: Stripe Integration

**Risk Score:** 5/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|
| devops | ❌ Blocked (3/10) | 13 findings, 8 high+ |

### SEC-005: Subscription Management

**Risk Score:** 5/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|
| devops | ❌ Blocked (2/10) | 15 findings, 10 high+ |

### SEC-006: Transaction History

**Risk Score:** 4/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|

### SEC-007: API Design

**Risk Score:** 4/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|

### SEC-008: Security Requirements

**Risk Score:** 5/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|

### SEC-009: Performance Requirements

**Risk Score:** 5/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|

### SEC-010: Testing Requirements

**Risk Score:** 4/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|

### SEC-011: Monitoring & Observability

**Risk Score:** 5/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|

### SEC-012: Deployment Strategy

**Risk Score:** 5/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|

### SEC-013: Success Metrics & Timeline

**Risk Score:** 3/5

| Persona | Feasibility | Key Findings |
|---------|-------------|--------------|


---

## All Findings by Severity

### 🔴 CRITICAL (11)

**[OAuth tokens stored in browser localStorage - server-side code impossible]** (SEC-002, devops)

PRD Section 2.1 requires 'Store access tokens securely' but tokenManager.ts:14-15 stores OAuth tokens in localStorage. This is browser-only storage and CANNOT work in a Node.js/Express server environment (package.json:14 shows Express dependency). localStorage is undefined on the server. This makes the entire OAuth implementation non-functional in production. Even if this were client-side code, storing tokens in localStorage is insecure (vulnerable to XSS attacks). Production OAuth requires secure, HttpOnly cookies or server-side session storage with Redis/database backend.

- **Code:** src/auth/tokenManager.ts:14-15, src/auth/tokenManager.ts:25, src/auth/tokenManager.ts:30, package.json:14
- **PRD:** Section 2.1: Store access tokens securely
- **Recommendation:** Replace localStorage with Redis or PostgreSQL for server-side token storage. Implement encrypted token storage with rotation. Use HttpOnly, Secure, SameSite cookies for session management. Estimate: 1 week dev work + Redis infrastructure ($20-50/month for managed Redis).

**[Multi-device session tracking infrastructure missing]** (SEC-002, devops)

PRD Section 2.1 requires 'Support multi-device sessions' but sessionManager.ts:2 uses an in-memory Map for session storage. This is non-persistent (lost on restart) and single-instance only (won't work across load-balanced servers). No database or Redis infrastructure exists for shared session state. The codebase has only a mock database (database.ts:1-27) with console.log statements, no real persistence. Production multi-device sessions require distributed session storage with Redis or database backend, plus session sync across instances.

- **Code:** src/auth/sessionManager.ts:2, src/utils/database.ts:1-27
- **PRD:** Section 2.1: Support multi-device sessions
- **Recommendation:** Deploy Redis cluster for session storage. Implement database-backed session persistence with device tracking table. Add session sync mechanism. Infrastructure: Redis cluster ($50-150/month), PostgreSQL database (if not exists, $20-100/month). Effort: 1-2 weeks.

**[No automatic token refresh mechanism - manual call only]** (SEC-002, devops)

PRD Section 2.1 requires 'Refresh tokens automatically before expiration' but tokenManager.ts:24-32 only provides a manual refreshToken() function with no automatic scheduling. There is no cron job, background worker, or token expiry monitoring. No infrastructure exists for scheduled tasks (no job queue, no worker processes in package.json scripts). Tokens will expire silently, breaking user sessions. Production requires a background job system (Bull/BullMQ with Redis) or cron-based token refresh scheduler that proactively refreshes tokens before expiry.

- **Code:** src/auth/tokenManager.ts:24-32, package.json:6-9
- **PRD:** Section 2.1: Refresh tokens automatically before expiration
- **Recommendation:** Implement background job queue (Bull/BullMQ) with Redis backend. Add token expiry tracking in database. Schedule refresh jobs 5-10 minutes before expiry. Infrastructure: Redis (shared with sessions, $50-150/month total), worker process deployment. Effort: 1 week.

**[No Stripe webhook infrastructure for payment reconciliation]** (SEC-004, devops)

PRD requires recurring billing and 3D Secure authentication, both of which rely on asynchronous Stripe webhooks for state updates. Current codebase has zero webhook handling infrastructure. Scenario SCEN-004-009 (user closes browser after payment) cannot be handled - the system has no way to reconcile payment state without the client being present. Subscriptions (src/api/subscriptions.ts:23-27) are created but there's no webhook endpoint to handle invoice.payment_succeeded, invoice.payment_failed, or customer.subscription.updated events. This means recurring billing will silently fail with no notification or retry mechanism.

- **Code:** src/api/subscriptions.ts:23-37, src/api/payments.ts:27-37
- **PRD:** Section 3.1: Store payment methods securely for recurring billing
- **Recommendation:** Implement Stripe webhook endpoint with signature verification, event processing queue (Redis + Bull or similar), and idempotent event handlers. Deploy webhook endpoint with public HTTPS URL and register with Stripe dashboard. Add monitoring for webhook delivery failures. Estimate: 1 week development + $50-100/month for Redis infrastructure.

**[In-memory rate limiting breaks under horizontal scaling]** (SEC-004, devops)

Rate limiter (src/utils/rateLimiter.ts:1-23) uses in-memory Map for tracking requests. This completely breaks under load balancing or multi-instance deployment. Scenario SCEN-004-007 (500 simultaneous payments on Black Friday) would require horizontal scaling, but each instance would have independent rate limit counters. A user could make 100 requests to instance A, 100 to instance B, 100 to instance C simultaneously, bypassing the intended 100 req/min limit. Additionally, in-memory storage causes memory leaks - the Map never clears old entries, growing unbounded over time.

- **Code:** src/utils/rateLimiter.ts:1, src/utils/rateLimiter.ts:8-20
- **PRD:** Section 3.1: Support for high-volume payment processing
- **Recommendation:** Replace in-memory Map with Redis-backed rate limiting (redis-rate-limiter or ioredis with Lua scripts). This enables shared state across instances and automatic TTL expiration. Add Redis cluster for high availability. Cost: +$50-200/month for managed Redis (AWS ElastiCache/Redis Cloud). Effort: 2-3 days.

**[Zero observability for payment processing SLAs]** (SEC-004, devops)

PRD requires 'process refunds within 24 hours' but there's no infrastructure to track or alert on this SLA. No metrics, no monitoring, no alerting. Scenario SCEN-004-010 specifically tests 24-hour refund compliance but the system cannot measure it. Console.log statements (payments.ts:15, database.ts:4, database.ts:8) are the only 'observability' - these go to stdout with no aggregation, searching, or alerting capability. Cannot answer: What's the p95 payment confirmation latency? How many payments failed in the last hour? Are refunds meeting the 24hr SLA? What's the Stripe API error rate?

- **Code:** src/api/payments.ts:15, src/utils/database.ts:4, src/utils/database.ts:8, src/api/payments.ts:39-48
- **PRD:** Section 3.1: Process refunds within 24 hours
- **Recommendation:** Implement observability stack: 1) Structured logging (Winston/Pino) with transaction IDs, 2) Metrics collection (Prometheus client or StatsD) for payment latency, success/failure rates, refund processing time, 3) APM (Datadog/New Relic) or OpenTelemetry for distributed tracing, 4) Alerting (PagerDuty/Opsgenie) for SLA violations. Minimum: Prometheus + Grafana + Alertmanager. Cost: $100-500/month depending on volume. Effort: 1 week.

**[No webhook infrastructure for Stripe payment events]** (SEC-005, devops)

PRD requires '3 retry attempts' for failed payments (SCEN-005, SCEN-010), but there is no webhook endpoint implemented to receive payment_failed events from Stripe. The codebase has no webhook handling at all (grep shows zero results). Without webhooks, the system cannot detect failed payments, trigger retries, or send notifications. SCEN-010 highlights webhook signature validation concerns that cannot even be addressed because webhooks don't exist. This is a complete blocker for the retry mechanism.

- **Code:** src/api/subscriptions.ts:1-73, src/api/payments.ts:1-49
- **PRD:** Section 3.2: 'Handle failed payments with 3 retry attempts'
- **Recommendation:** Implement Stripe webhook endpoint with signature validation, event processing logic, and idempotency handling. Requires: webhook route handler, signature verification middleware, event storage for deduplication, and integration with retry job queue. Estimate: 3-5 days development + security review.

**[No job queue infrastructure for payment retry mechanism]** (SEC-005, devops)

PRD mandates '3 retry attempts' for failed payments with email notifications at each stage. This requires asynchronous job processing with scheduling, retry logic, and failure tracking. No job queue system exists (no Redis, Bull, RabbitMQ, or SQS found in package.json or codebase). SCEN-005 asks 'what if retries span multiple days' - without persistent job storage, retries would be lost on server restart. SCEN-007 highlights the need to queue email notifications separately from payment processing.

- **Code:** package.json:11-15, src/api/subscriptions.ts:40-59
- **PRD:** Section 3.2: 'Handle failed payments with 3 retry attempts'
- **Recommendation:** Add job queue infrastructure: Redis for persistence, Bull for job processing, implement payment retry job with exponential backoff (attempt 1: immediate, attempt 2: 1 day, attempt 3: 3 days). Separate email notification queue to handle service outages. Infrastructure cost: ~$30-50/month for managed Redis. Development: 1-2 weeks.

**[No database transaction support - partial failure guaranteed]** (SEC-005, devops)

Database implementation (src/utils/database.ts) is a mock with console.log statements and no real persistence. SCEN-001 asks 'what happens if Stripe charges succeed but database update fails' - currently this would result in charging users without recording their subscription upgrade. The updateSubscription function (subscriptions.ts:40-59) makes two separate calls (Stripe API then DB update) with zero error handling or rollback capability. SCEN-004 concurrency scenario would cause race conditions with no locking mechanism.

- **Code:** src/utils/database.ts:1-28, src/api/subscriptions.ts:40-59
- **PRD:** Section 3.2: 'Allow users to upgrade/downgrade instantly'
- **Recommendation:** Replace mock database with real database supporting ACID transactions (PostgreSQL or MongoDB). Implement distributed locking for subscription updates (Redis-based locks). Add compensating transactions to reverse Stripe charges if DB updates fail. Wrap all subscription operations in try-catch with proper rollback. Estimate: 2-3 weeks + database infrastructure costs ($50-200/month).

**[Zero authorization checks - any user can modify any subscription]** (SEC-005, devops)

SCEN-002 explicitly tests this: 'what prevents a malicious user from calling updateSubscription with another user's subscription ID?' Answer: nothing. The updateSubscription endpoint (subscriptions.ts:40-59) has no authorization checks whatsoever. It accepts a subscriptionId parameter and immediately calls Stripe and updates the database without verifying the requesting user owns that subscription. A user could enumerate subscription IDs and upgrade their own account or downgrade competitors.

- **Code:** src/api/subscriptions.ts:40-59
- **PRD:** Section 3.2: Subscription Management (implicit security requirement)
- **Recommendation:** CRITICAL: Add authorization middleware before ANY deployment. Verify req.user.id matches subscription.userId before allowing updates. Add audit logging for all subscription changes. Implement rate limiting specifically for subscription endpoints (beyond the generic 100 req/min). Security review mandatory before production.

**[No email notification system - PRD requirement impossible]** (SEC-005, devops)

PRD requires 'Send email notifications for billing events' but grep shows zero email/notification infrastructure. No email service (SendGrid, SES, Mailgun) in dependencies. SCEN-007 asks what happens when email service is down - but there's no email service to be down. Failed payments, upgrades, downgrades would all occur silently. Users would have no idea their subscription changed or payment failed until they notice features missing or try to use the app.

- **Code:** package.json:11-15, src/api/subscriptions.ts:1-73
- **PRD:** Section 3.2: 'Send email notifications for billing events'
- **Recommendation:** Integrate email service provider (recommend AWS SES for cost: ~$0.10 per 1000 emails). Implement email templating system, delivery queue with retry logic (reuses job queue from finding #2), bounce/complaint handling, and delivery status tracking. Add email preferences table for user opt-outs. Estimate: 1-2 weeks + ~$10-50/month for email service.


### 🟠 HIGH (14)

**[GitHub OAuth provider not implemented - only Google exists]** (SEC-002, devops)

PRD Section 2.1 requires 'authenticate via OAuth 2.0 (Google, GitHub)' but only Google OAuth is implemented (tokenManager.ts:1,7-10). No GitHub OAuth integration exists. README.md:23-24 only lists GOOGLE_CLIENT_ID/SECRET environment variables. No github-oauth or similar packages in package.json dependencies. Adding GitHub OAuth requires additional OAuth client library, callback endpoints, provider configuration, and separate token management flows.

- **Code:** src/auth/tokenManager.ts:1, src/auth/tokenManager.ts:7-10, README.md:23-24, package.json:11-15
- **PRD:** Section 2.1: OAuth 2.0 (Google, GitHub)
- **Recommendation:** Install passport.js or octokit for GitHub OAuth. Add GitHub OAuth routes and callbacks. Update environment variables. Implement multi-provider token management. Effort: 3-5 days. No additional infrastructure cost.

**[Token revocation doesn't call OAuth provider - incomplete cleanup]** (SEC-002, devops)

PRD Section 2.1 requires 'Handle token revocation gracefully' but tokenManager.ts:34-37 only removes tokens from localStorage without calling Google's token revocation endpoint. This leaves tokens valid on Google's side, creating a security gap. Revoked users can still use cached tokens until natural expiry. Proper revocation requires calling oauth2Client.revokeToken() for Google and similar for GitHub, plus handling network failures gracefully.

- **Code:** src/auth/tokenManager.ts:34-37
- **PRD:** Section 2.1: Handle token revocation gracefully
- **Recommendation:** Add OAuth provider revocation calls with retry logic. Implement graceful degradation if provider revocation fails (mark token as revoked locally, continue). Add monitoring for revocation failures. Effort: 2-3 days.

**[No monitoring, metrics, or alerting for OAuth flows]** (SEC-002, devops)

No observability infrastructure exists for OAuth operations. No Prometheus, Datadog, CloudWatch, or logging framework found in codebase. Only basic console.log statements in payments.ts:15,22. Cannot monitor: token refresh failures, OAuth provider outages, token revocation success rates, session creation/expiry metrics. Production OAuth requires monitoring for: failed authentications, token refresh errors, provider API latency, session counts per user/device. Without this, OAuth outages are invisible until users report issues.

- **Code:** src/api/payments.ts:15, src/api/payments.ts:22
- **PRD:** Section 2.1: OAuth Integration (operational requirements)
- **Recommendation:** Implement structured logging (Winston/Pino). Add Prometheus metrics or APM tool (Datadog/New Relic). Create dashboards for OAuth metrics. Set up alerts for: auth failure rate >5%, token refresh errors, provider timeouts. Infrastructure: APM service ($20-200/month) or self-hosted Prometheus (free, $10/month hosting). Effort: 3-5 days.

**[In-memory rate limiting won't scale across multiple instances]** (SEC-002, devops)

rateLimiter.ts:1 uses in-memory Map for rate limiting, which is per-instance only. When deployed behind a load balancer with multiple servers, each instance has separate rate limit counters. A user can bypass rate limits by hitting different instances (100 req/min per instance = 300 req/min total with 3 instances). OAuth endpoints need distributed rate limiting to prevent credential stuffing attacks. Requires Redis-backed rate limiting (ioredis + rate-limiter-flexible) for shared state across instances.

- **Code:** src/utils/rateLimiter.ts:1
- **PRD:** Section 2.1: OAuth Integration (security)
- **Recommendation:** Replace in-memory Map with Redis-backed rate limiter (rate-limiter-flexible library). Share rate limit state across all instances. Use Redis shared with sessions. Effort: 2 days.

**[No deployment infrastructure or CI/CD pipeline]** (SEC-004, devops)

Zero deployment automation exists. No Dockerfile, no docker-compose.yml, no Kubernetes manifests, no Terraform/CloudFormation, no GitHub Actions/CircleCI. Package.json shows basic npm scripts (start/build/test) but no deployment target. Deploying this to production would be entirely manual. Scenario SCEN-004-007 (Black Friday traffic spike) requires auto-scaling infrastructure, but there's nothing to scale - no container orchestration, no load balancer config, no health checks.

- **Code:** package.json:6-10
- **PRD:** Section 3.1: High availability payment processing
- **Recommendation:** Implement containerized deployment: 1) Dockerfile with multi-stage build, 2) Kubernetes manifests (Deployment, Service, HPA, Ingress) or ECS task definitions, 3) Terraform/Pulumi for infrastructure provisioning (load balancer, Redis, RDS), 4) CI/CD pipeline (GitHub Actions) with automated testing, security scanning, and blue-green deployment. Minimum viable: Docker + docker-compose + basic CI. Effort: 1-2 weeks. Infrastructure cost: $200-500/month for production-grade setup (ALB, ECS/EKS, RDS, Redis).

**[No idempotency keys for Stripe API calls - duplicate charge risk]** (SEC-004, devops)

Scenario SCEN-004-004 tests double-submission (user clicks Pay twice) but the code has zero idempotency protection. All Stripe API calls (payments.ts:9, subscriptions.ts:15, subscriptions.ts:23, payments.ts:42) lack idempotency_key parameter. If a user double-clicks or network timeout causes retry, Stripe will process both requests, resulting in duplicate charges or subscriptions. This is a critical payment correctness issue that violates financial compliance requirements.

- **Code:** src/api/payments.ts:9-13, src/api/subscriptions.ts:15-21, src/api/subscriptions.ts:23-27, src/api/payments.ts:42-45
- **PRD:** Section 3.1: Secure payment processing
- **Recommendation:** Generate idempotency keys (UUID v4) for all Stripe API calls that mutate state (create payment, create subscription, create refund). Store keys in Redis with 24-hour TTL to track request deduplication. Add database constraints to prevent duplicate subscription/payment records. Effort: 2-3 days.

**[Mock database breaks all payment state persistence]** (SEC-004, devops)

Database layer (src/utils/database.ts:1-27) is entirely mock - just console.log statements with no actual persistence. All payment data, subscriptions, and transactions are lost on server restart. Scenario SCEN-004-005 (recurring billing with expired cards) cannot work because subscription state is never actually stored. The system cannot track which payment methods are stored, which subscriptions are active, or when to retry failed renewals. This is not a POC-ready implementation - it's non-functional for any real payment processing.

- **Code:** src/utils/database.ts:3-13, src/utils/database.ts:16-24
- **PRD:** Section 3.1: Store payment methods securely for recurring billing
- **Recommendation:** Implement production database: 1) PostgreSQL or MongoDB with proper schema for subscriptions/transactions, 2) Database migrations (TypeORM, Prisma, or Knex), 3) Connection pooling and timeouts, 4) Backup strategy (point-in-time recovery), 5) Encryption at rest for PCI DSS compliance. Cost: $50-200/month for managed DB (RDS, MongoDB Atlas). Effort: 1 week.

**[PCI DSS compliance gaps - logging and error exposure]** (SEC-004, devops)

Scenario SCEN-004-003 highlights security risk: payment intent IDs logged to stdout (payments.ts:15). Payment intent IDs can be used to retrieve full payment details from Stripe API, potentially exposing cardholder data in application logs. PCI DSS requirement 3.4 prohibits logging full PAN or security codes. Additionally, error responses (payments.ts:23) may leak sensitive Stripe error details to client. No log redaction, no secrets management for STRIPE_SECRET_KEY (stored in plaintext env vars), no audit logging for refund operations.

- **Code:** src/api/payments.ts:15, src/api/payments.ts:22-23, src/api/payments.ts:3
- **PRD:** Section 3.1: Store payment methods securely
- **Recommendation:** 1) Remove payment intent ID logging, log only transaction UUID for correlation, 2) Implement log scrubbing for sensitive fields (Winston log filters), 3) Use secrets manager (AWS Secrets Manager, HashiCorp Vault) for STRIPE_SECRET_KEY with automatic rotation, 4) Add audit log for all refund operations with user ID and timestamp, 5) Sanitize error messages returned to client. Effort: 3-5 days.

**[Missing error handling crashes payment confirmation]** (SEC-004, devops)

Scenario SCEN-004-012 specifically calls out confirmPayment (payments.ts:27-37) having no try-catch. If Stripe API throws (network timeout, card declined, authentication required), the entire request crashes with unhandled promise rejection. No differentiation between error types - card_declined should show user-friendly message, insufficient_funds needs different handling than network errors. Scenario SCEN-004-001 (Stripe 503 during confirmation) would crash the server process, not just fail the individual request.

- **Code:** src/api/payments.ts:27-37, src/api/subscriptions.ts:12-37, src/api/payments.ts:39-48
- **PRD:** Section 3.1: Reliable payment processing
- **Recommendation:** Add comprehensive error handling: 1) Try-catch all Stripe API calls, 2) Map Stripe error codes to user-friendly messages, 3) Implement exponential backoff retry for network errors (with max 3 retries), 4) Return appropriate HTTP status codes (400 for card_declined, 503 for Stripe downtime), 5) Add circuit breaker for Stripe API to prevent cascade failures. Effort: 2-3 days.

**[No proration logic implemented - billing errors inevitable]** (SEC-005, devops)

PRD explicitly requires 'Prorate charges when changing plans' but subscriptions.ts:40-59 has zero proration logic. The updateSubscription function just swaps the Stripe price ID without any proration_behavior parameter. SCEN-006 asks about same-day plan changes causing negative amounts - this would definitely break. SCEN-003 asks about mid-month downgrades with Stripe API failures - without explicit proration handling, users could be over/under-charged. Stripe defaults to create_prorations=true but the code doesn't handle the resulting invoices.

- **Code:** src/api/subscriptions.ts:40-59
- **PRD:** Section 3.2: 'Prorate charges when changing plans'
- **Recommendation:** Add proration_behavior: 'create_prorations' to stripe.subscriptions.update call. Implement invoice.created webhook handler to record proration invoices in database. Add logic to handle negative proration amounts for downgrades (issue credits). Add user-facing proration preview before confirming plan changes. Estimate: 3-5 days development + thorough testing.

**[In-memory data structures don't scale across multiple instances]** (SEC-005, devops)

Rate limiter (src/utils/rateLimiter.ts:1-24) uses in-memory Map for request tracking. Session manager uses in-memory Map. These work for single-instance deployment but SCEN-009 describes '1000 users simultaneously downgrade' - this requires horizontal scaling with multiple app instances. In-memory state would cause: (1) rate limits to not work correctly across instances, (2) session invalidation issues, (3) no shared state for job processing. SCEN-004 concurrent requests could hit different instances and race.

- **Code:** src/utils/rateLimiter.ts:1-24, src/auth/sessionManager.ts:1-35
- **PRD:** Section 3.2: Subscription Management (implicit scale requirement)
- **Recommendation:** Replace in-memory storage with Redis for: rate limiting (use redis-rate-limit or similar), session storage, distributed locks for subscription updates. Configure app for stateless horizontal scaling behind load balancer. Implement sticky sessions if needed for websocket/long-polling. Redis cost: $30-100/month. Load balancer: $20-50/month. Development: 1 week.

**[Zero monitoring infrastructure - production failures invisible]** (SEC-005, devops)

No monitoring, logging, metrics, or alerting infrastructure exists. SCEN-003 asks about Stripe API unavailability - the system has no way to detect this, alert on-call engineers, or track API error rates. SCEN-001 database failures would be silent. SCEN-005 retry failures would go unnoticed. The only 'observability' is console.log statements in the mock database. Critical billing operations need comprehensive monitoring: Stripe API latency/errors, payment success rates, retry attempts, webhook delivery, email delivery, subscription state transitions.

- **Code:** src/api/subscriptions.ts:1-73, src/api/payments.ts:15-24
- **PRD:** Section 3.2: Subscription Management (implicit operational requirement)
- **Recommendation:** Implement observability stack: (1) Structured logging (Winston/Pino) with correlation IDs, (2) Metrics collection (Prometheus client), (3) APM for distributed tracing (Datadog, New Relic, or self-hosted Jaeger), (4) Alerting rules for: payment failures >1%, Stripe API errors, webhook processing lag, job queue depth >100. Cost: $100-500/month for hosted solution. Development: 1-2 weeks.

**[No deployment infrastructure or CI/CD - manual deploys are error-prone]** (SEC-005, devops)

Zero deployment infrastructure: no Dockerfile, docker-compose.yml, Kubernetes manifests, or Terraform/IaC. No CI/CD pipeline (no .github/workflows, no Jenkins, no GitLab CI). Package.json only has basic build/start scripts. Deploying subscription management changes requires manual steps prone to errors. SCEN-008 asks about payment processing when users close browser - this needs webhook-based async processing which requires careful deployment sequencing (deploy webhook handler before enabling Stripe webhooks). No deployment docs exist.

- **Code:** package.json:6-10, README.md:13-18
- **PRD:** Section 3.2: Subscription Management (implicit deployment requirement)
- **Recommendation:** Implement: (1) Dockerfile for containerized deployment, (2) docker-compose.yml for local dev environment matching production, (3) CI/CD pipeline with automated tests, security scanning, and staged rollout, (4) Infrastructure-as-Code (Terraform or CloudFormation) for reproducible environments, (5) Deployment runbook documenting rollback procedures. Use blue-green deployment for zero-downtime updates. Estimate: 1-2 weeks.

**[No error handling in subscription operations - failures cascade]** (SEC-005, devops)

Subscription endpoints have zero error handling: updateSubscription (subscriptions.ts:40-59) has no try-catch, no validation, no error responses. If Stripe API call fails (SCEN-003: 503 error), the function throws uncaught exception crashing the server. If database update fails (SCEN-001), no rollback occurs. createSubscription and cancelSubscription have same issues. Only payments.ts has a single try-catch (payments.ts:8-24) but it returns generic 'Payment failed' with no useful error info for debugging.

- **Code:** src/api/subscriptions.ts:40-72, src/api/payments.ts:21-24
- **PRD:** Section 3.2: Subscription Management
- **Recommendation:** Wrap all subscription operations in comprehensive error handling: (1) Specific catch blocks for Stripe errors vs database errors vs validation errors, (2) Proper HTTP status codes (400 for validation, 402 for payment issues, 409 for conflicts, 500 for server errors), (3) Structured error logging with context, (4) User-friendly error messages, (5) Rollback/compensation logic for partial failures. Add input validation middleware. Estimate: 3-5 days.


### 🟡 MEDIUM (8)

**[No deployment configuration or CI/CD pipeline]** (SEC-002, devops)

No deployment infrastructure found: no Dockerfile, docker-compose.yml, Kubernetes manifests, or IaC (Terraform/CloudFormation). No CI/CD pipeline (.github/workflows, .gitlab-ci.yml, etc.). Only basic npm scripts (package.json:6-9): test, start, build. No environment-specific configs (dev/staging/prod). Deploying OAuth requires: secure environment variable management (not .env files in prod), HTTPS endpoints for OAuth callbacks, health checks, zero-downtime deployments for token refresh continuity. Current setup requires manual deployment with high error risk.

- **Code:** package.json:6-9
- **PRD:** Section 2.1: OAuth Integration (deployment)
- **Recommendation:** Create Dockerfile + docker-compose for local dev. Add Kubernetes manifests or Terraform for cloud deployment. Implement CI/CD with GitHub Actions (build, test, deploy pipeline). Add secrets management (AWS Secrets Manager, HashiCorp Vault). Infrastructure: container registry ($5-20/month), K8s cluster or managed service ($50-200/month). Effort: 1 week.

**[No error handling or retry logic for OAuth provider failures]** (SEC-002, devops)

tokenManager.ts:27 calls Google's refreshAccessToken with no error handling or retry logic. If Google's OAuth API is down or rate-limited, token refresh fails and user sessions break. No circuit breaker pattern, no fallback mechanism. OAuth providers have SLAs of 99.9% = 43 minutes downtime/month. Need retry with exponential backoff, circuit breaker to prevent cascade failures, and graceful degradation (allow limited access with expired tokens during provider outages).

- **Code:** src/auth/tokenManager.ts:27
- **PRD:** Section 2.1: Refresh tokens automatically before expiration
- **Recommendation:** Add retry logic with exponential backoff (3 retries, 1s/2s/4s delays). Implement circuit breaker (opossum library). Add fallback: extend session temporarily if refresh fails. Monitor provider API health. Effort: 2-3 days.

**[PRD requirements completely unimplemented - 3D Secure, digital wallets, multi-currency]** (SEC-004, devops)

PRD explicitly requires: 3D Secure authentication, digital wallets (Apple Pay/Google Pay), and multi-currency support (USD/EUR/GBP). Code has none of this. Payments hardcoded to USD (payments.ts:11). Scenario SCEN-004-002 tests 3D Secure failure handling, SCEN-004-006 tests multi-currency refunds, SCEN-004-008 tests digital wallet timeout - all would fail because the features don't exist. 3D Secure requires handling payment_intent.requires_action status and redirecting to authentication URL. Digital wallets need Apple Pay JS SDK and Google Pay API integration. Multi-currency needs currency validation and exchange rate tracking for refunds.

- **Code:** src/api/payments.ts:11
- **PRD:** Section 3.1: Handle 3D Secure authentication, Support digital wallets, Support multiple currencies
- **Recommendation:** Implement missing features: 1) 3D Secure: handle requires_action status, implement frontend redirect flow, add webhook for authentication completion, 2) Digital wallets: integrate Stripe Payment Request Button API, add domain verification for Apple Pay, 3) Multi-currency: validate currency parameter against allowed list [USD, EUR, GBP], store original currency in transaction record for accurate refunds. Effort: 2-3 weeks total (1 week per major feature).

**[No retry or failure queue for recurring billing]** (SEC-004, devops)

Scenario SCEN-004-005 tests expired card handling for subscription renewals, but there's no job queue infrastructure to process recurring charges. Subscriptions are created (subscriptions.ts:23-27) but no scheduled job to attempt monthly/annual renewals. When payment fails (expired card, insufficient funds), there's no retry mechanism or dunning management. Stripe invoices may be created but never polled. At scale, need distributed job queue (Bull/BullMQ with Redis) to process thousands of subscription renewals daily with configurable retry policies.

- **Code:** src/api/subscriptions.ts:23-37
- **PRD:** Section 3.1: Store payment methods securely for recurring billing
- **Recommendation:** Implement job queue for subscription management: 1) Bull/BullMQ with Redis for job processing, 2) Scheduled jobs to sync Stripe invoice status, 3) Retry policy for failed payments (retry at 3 days, 7 days, 14 days), 4) Email notifications for payment failures, 5) Webhook handlers for invoice.payment_failed events to update subscription status. Infrastructure: Redis queue (shares instance with rate limiter). Effort: 1 week.

**[High Stripe API call volume without optimization]** (SEC-004, devops)

Every payment operation makes synchronous Stripe API calls with no caching or batching. Scenario SCEN-004-007 (500 concurrent payments) would make 500+ simultaneous Stripe API requests. No caching of customer or subscription data - subscriptions.ts:44 retrieves full subscription just to update it. At scale, this creates unnecessary Stripe API costs (Stripe charges per API call beyond free tier) and latency. No webhook-based eventual consistency - everything is synchronous.

- **Code:** src/api/subscriptions.ts:44-51, src/api/payments.ts:9-13
- **PRD:** Section 3.1: Efficient payment processing at scale
- **Recommendation:** Optimize Stripe API usage: 1) Cache customer and subscription objects in Redis (5-minute TTL), 2) Use Stripe's expandable fields to reduce API calls (expand=['customer','payment_method'] in single request), 3) Process bulk operations via webhooks instead of synchronous polling, 4) Implement request coalescing for duplicate lookups. Cost savings: ~30-40% reduction in API calls. Effort: 3-5 days.

**[No Stripe API rate limiting or request optimization]** (SEC-005, devops)

SCEN-009 describes '1000 users simultaneously downgrade' - this would trigger 1000+ Stripe API calls in burst. Stripe rate limits vary by endpoint (default ~100 req/sec for writes). No rate limiting, request batching, or retry logic for Stripe API exists. The code makes blocking Stripe API calls with no timeout configuration. A burst of subscription changes could exhaust rate limits causing 429 errors, or trigger Stripe fraud detection. No caching of Stripe data (subscription objects are retrieved fresh every time).

- **Code:** src/api/subscriptions.ts:44-51
- **PRD:** Section 3.2: 'Allow users to upgrade/downgrade instantly'
- **Recommendation:** Implement: (1) Queue subscription changes to smooth traffic bursts, (2) Retry logic with exponential backoff for Stripe 429/503 errors, (3) Request timeout configuration (default 80s is too long), (4) Cache Stripe subscription objects in Redis with TTL, (5) Monitor Stripe API usage via Stripe dashboard. Consider Stripe client-side SDK for some operations to offload server. Estimate: 3-5 days.

**[No idempotency handling for duplicate requests]** (SEC-005, devops)

SCEN-004 asks about 'user rapidly clicks upgrade then downgrade within 2 seconds' - could create duplicate charges or inconsistent state. SCEN-005 mentions 'duplicate webhook deliveries' from network issues. Zero idempotency handling exists: no idempotency keys for Stripe requests, no deduplication for webhooks, no request tracking. The same subscription could be upgraded twice if user double-clicks, resulting in duplicate Stripe subscription items and double charges.

- **Code:** src/api/subscriptions.ts:12-38, src/api/subscriptions.ts:40-59
- **PRD:** Section 3.2: 'Allow users to upgrade/downgrade instantly'
- **Recommendation:** Add idempotency: (1) Generate idempotency keys for all Stripe write operations (use UUID v4 or hash of request params), (2) Store processed webhook event IDs in database to detect duplicates, (3) Add request deduplication middleware using Redis with 60-second TTL, (4) Return cached response for duplicate requests within window. Stripe supports idempotency keys natively. Estimate: 2-3 days.

**[No operational runbooks or incident response procedures]** (SEC-005, devops)

Multiple scenarios describe failure conditions (SCEN-001: partial failure, SCEN-003: Stripe outage, SCEN-005: retry bugs, SCEN-007: email service down) but zero operational documentation exists. No runbooks for: investigating failed payments, reconciling Stripe vs database inconsistencies, manually triggering retries, handling webhook replay, emergency subscription cancellations. On-call engineers would have no guidance during 2AM incidents. README.md only has basic setup instructions.

- **Code:** README.md:1-25
- **PRD:** Section 3.2: Subscription Management (operational requirement)
- **Recommendation:** Create operational documentation: (1) Runbook for common failure scenarios with step-by-step remediation, (2) Database schema documentation, (3) Stripe webhook event guide with example payloads, (4) Monitoring dashboard guide showing key metrics, (5) Emergency procedures for payment failures, (6) Stripe reconciliation scripts to detect discrepancies. Use wiki or docs-as-code approach. Estimate: 3-5 days.


### 🟢 LOW (4)

**[OAuth client secrets in environment variables - no secrets management]** (SEC-002, devops)

README.md:23-24 instructs storing GOOGLE_CLIENT_SECRET in environment variables, which is insecure for production. Environment variables are visible in process listings, logs, and crash dumps. No secrets management system (AWS Secrets Manager, HashiCorp Vault, Google Secret Manager) is configured. Production OAuth requires encrypted secrets storage with rotation capability and audit logging.

- **Code:** README.md:23-24, src/auth/tokenManager.ts:8-9
- **PRD:** Section 2.1: Store access tokens securely
- **Recommendation:** Implement secrets management service (AWS Secrets Manager $0.40/secret/month, Vault self-hosted). Load secrets at runtime, not from env vars. Add secret rotation automation. Effort: 2-3 days.

**[No health check endpoints for load balancer]** (SEC-004, devops)

No /health or /readiness endpoints defined. When deployed behind load balancer (required for SCEN-004-007 scale), LB cannot determine if instance is healthy. This causes traffic to be routed to crashed/restarting instances. Health check should verify: 1) Server is responding, 2) Database connection is alive, 3) Stripe API is reachable (with caching to avoid excessive health check traffic).

- **Code:** 
- **PRD:** Section 3.1: High availability payment processing
- **Recommendation:** Add health check endpoints: GET /health (liveness - is server running), GET /ready (readiness - can accept traffic, checks DB + Stripe connectivity with 5s timeout). Configure load balancer to poll every 10s with 3 failure threshold. Effort: 4 hours.

**[No backup/disaster recovery strategy for subscription data]** (SEC-005, devops)

While database is currently mock implementation, production deployment needs backup strategy. Subscription data is critical business data - losing it means not knowing who paid for what. No backup configuration, retention policies, or recovery procedures documented. SCEN-001 partial failures could corrupt data requiring restore from backup.

- **Code:** src/utils/database.ts:1-28
- **PRD:** Section 3.2: Subscription Management
- **Recommendation:** Implement automated database backups: (1) Daily full backups with 30-day retention, (2) Transaction log backups every 15 minutes for point-in-time recovery, (3) Test restore procedure monthly, (4) Store backups in separate region for disaster recovery, (5) Document RTO (2 hours) and RPO (15 minutes) targets. Managed database services (RDS, Cloud SQL) include this. Additional cost: ~$20-50/month for backup storage.

**[No cost monitoring or budget alerts for infrastructure]** (SEC-005, devops)

Adding all required infrastructure (Redis, database, email service, monitoring, load balancer) will increase monthly costs from near-zero to $300-800/month. No cost monitoring, budget alerts, or cost allocation tags exist. SCEN-009 burst traffic could trigger autoscaling causing unexpected cost spikes. No cost optimization strategy (reserved instances, spot instances, scaling policies).

- **Code:** 
- **PRD:** Section 3.2: Subscription Management
- **Recommendation:** Implement cost management: (1) Set up cloud provider budget alerts at $500 and $750/month, (2) Tag all infrastructure resources with cost center/feature tags, (3) Configure autoscaling limits to cap max cost, (4) Monthly cost review process, (5) Use reserved instances for baseline capacity (30-50% cost savings). Cost monitoring tools are usually free from cloud providers.


### ℹ️ INFO (2)

**[OAuth infrastructure cost estimate]** (SEC-002, devops)

Based on required infrastructure changes, estimated additional monthly costs: Redis cluster for sessions/rate-limiting/jobs ($50-150), APM/monitoring service ($20-200), managed PostgreSQL if needed ($20-100), secrets management ($5-20), container hosting/K8s ($50-200). Total: $145-670/month depending on scale and managed vs self-hosted choices. Development effort: 3-4 weeks for full production-ready OAuth implementation.

- **Code:** 
- **PRD:** Section 2.1: OAuth Integration
- **Recommendation:** Start with managed Redis ($50/month), basic monitoring ($20/month), existing database. Total minimum: ~$70/month additional. Scale up as needed. Consider AWS/GCP free tier for initial deployment.

**[Refund 24-hour SLA tracking requires operational tooling]** (SEC-004, devops)

PRD states 'process refunds within 24 hours' (Scenario SCEN-004-010). This requires: 1) Timestamp recording when refund is requested, 2) Monitoring dashboard to show pending refunds and time remaining, 3) Alerting when refunds approach 24hr deadline, 4) Admin interface to manually process stuck refunds. Current code has instant refund processing (payments.ts:39-48) but no workflow for manual review or approval processes that might cause delays.

- **Code:** src/api/payments.ts:39-48
- **PRD:** Section 3.1: Process refunds within 24 hours
- **Recommendation:** Clarify PRD requirement: Is '24 hours' an SLA for completion or a validation window? If SLA, add refund request tracking table with status (pending/approved/completed), admin dashboard showing pending refunds sorted by age, and alerts for requests >20 hours old. If validation window (must be requested within 24hr of payment), add timestamp check in refund endpoint. Effort: 2-3 days for full SLA tracking.



---

## Recommendations

1. **OAuth tokens stored in browser localStorage - server-side code impossible** - Replace localStorage with Redis or PostgreSQL for server-side token storage. Implement encrypted token storage with rotation. Use HttpOnly, Secure, SameSite cookies for session management. Estimate: 1 week dev work + Redis infrastructure ($20-50/month for managed Redis).
1. **Multi-device session tracking infrastructure missing** - Deploy Redis cluster for session storage. Implement database-backed session persistence with device tracking table. Add session sync mechanism. Infrastructure: Redis cluster ($50-150/month), PostgreSQL database (if not exists, $20-100/month). Effort: 1-2 weeks.
1. **No automatic token refresh mechanism - manual call only** - Implement background job queue (Bull/BullMQ) with Redis backend. Add token expiry tracking in database. Schedule refresh jobs 5-10 minutes before expiry. Infrastructure: Redis (shared with sessions, $50-150/month total), worker process deployment. Effort: 1 week.
1. **GitHub OAuth provider not implemented - only Google exists** - Install passport.js or octokit for GitHub OAuth. Add GitHub OAuth routes and callbacks. Update environment variables. Implement multi-provider token management. Effort: 3-5 days. No additional infrastructure cost.
1. **Token revocation doesn't call OAuth provider - incomplete cleanup** - Add OAuth provider revocation calls with retry logic. Implement graceful degradation if provider revocation fails (mark token as revoked locally, continue). Add monitoring for revocation failures. Effort: 2-3 days.
1. **No monitoring, metrics, or alerting for OAuth flows** - Implement structured logging (Winston/Pino). Add Prometheus metrics or APM tool (Datadog/New Relic). Create dashboards for OAuth metrics. Set up alerts for: auth failure rate >5%, token refresh errors, provider timeouts. Infrastructure: APM service ($20-200/month) or self-hosted Prometheus (free, $10/month hosting). Effort: 3-5 days.
1. **In-memory rate limiting won't scale across multiple instances** - Replace in-memory Map with Redis-backed rate limiter (rate-limiter-flexible library). Share rate limit state across all instances. Use Redis shared with sessions. Effort: 2 days.
3. **No Stripe webhook infrastructure for payment reconciliation** - Implement Stripe webhook endpoint with signature verification, event processing queue (Redis + Bull or similar), and idempotent event handlers. Deploy webhook endpoint with public HTTPS URL and register with Stripe dashboard. Add monitoring for webhook delivery failures. Estimate: 1 week development + $50-100/month for Redis infrastructure.
3. **In-memory rate limiting breaks under horizontal scaling** - Replace in-memory Map with Redis-backed rate limiting (redis-rate-limiter or ioredis with Lua scripts). This enables shared state across instances and automatic TTL expiration. Add Redis cluster for high availability. Cost: +$50-200/month for managed Redis (AWS ElastiCache/Redis Cloud). Effort: 2-3 days.
3. **Zero observability for payment processing SLAs** - Implement observability stack: 1) Structured logging (Winston/Pino) with transaction IDs, 2) Metrics collection (Prometheus client or StatsD) for payment latency, success/failure rates, refund processing time, 3) APM (Datadog/New Relic) or OpenTelemetry for distributed tracing, 4) Alerting (PagerDuty/Opsgenie) for SLA violations. Minimum: Prometheus + Grafana + Alertmanager. Cost: $100-500/month depending on volume. Effort: 1 week.
3. **No deployment infrastructure or CI/CD pipeline** - Implement containerized deployment: 1) Dockerfile with multi-stage build, 2) Kubernetes manifests (Deployment, Service, HPA, Ingress) or ECS task definitions, 3) Terraform/Pulumi for infrastructure provisioning (load balancer, Redis, RDS), 4) CI/CD pipeline (GitHub Actions) with automated testing, security scanning, and blue-green deployment. Minimum viable: Docker + docker-compose + basic CI. Effort: 1-2 weeks. Infrastructure cost: $200-500/month for production-grade setup (ALB, ECS/EKS, RDS, Redis).
3. **No idempotency keys for Stripe API calls - duplicate charge risk** - Generate idempotency keys (UUID v4) for all Stripe API calls that mutate state (create payment, create subscription, create refund). Store keys in Redis with 24-hour TTL to track request deduplication. Add database constraints to prevent duplicate subscription/payment records. Effort: 2-3 days.
3. **Mock database breaks all payment state persistence** - Implement production database: 1) PostgreSQL or MongoDB with proper schema for subscriptions/transactions, 2) Database migrations (TypeORM, Prisma, or Knex), 3) Connection pooling and timeouts, 4) Backup strategy (point-in-time recovery), 5) Encryption at rest for PCI DSS compliance. Cost: $50-200/month for managed DB (RDS, MongoDB Atlas). Effort: 1 week.
3. **PCI DSS compliance gaps - logging and error exposure** - 1) Remove payment intent ID logging, log only transaction UUID for correlation, 2) Implement log scrubbing for sensitive fields (Winston log filters), 3) Use secrets manager (AWS Secrets Manager, HashiCorp Vault) for STRIPE_SECRET_KEY with automatic rotation, 4) Add audit log for all refund operations with user ID and timestamp, 5) Sanitize error messages returned to client. Effort: 3-5 days.
3. **Missing error handling crashes payment confirmation** - Add comprehensive error handling: 1) Try-catch all Stripe API calls, 2) Map Stripe error codes to user-friendly messages, 3) Implement exponential backoff retry for network errors (with max 3 retries), 4) Return appropriate HTTP status codes (400 for card_declined, 503 for Stripe downtime), 5) Add circuit breaker for Stripe API to prevent cascade failures. Effort: 2-3 days.
4. **No webhook infrastructure for Stripe payment events** - Implement Stripe webhook endpoint with signature validation, event processing logic, and idempotency handling. Requires: webhook route handler, signature verification middleware, event storage for deduplication, and integration with retry job queue. Estimate: 3-5 days development + security review.
4. **No job queue infrastructure for payment retry mechanism** - Add job queue infrastructure: Redis for persistence, Bull for job processing, implement payment retry job with exponential backoff (attempt 1: immediate, attempt 2: 1 day, attempt 3: 3 days). Separate email notification queue to handle service outages. Infrastructure cost: ~$30-50/month for managed Redis. Development: 1-2 weeks.
4. **No database transaction support - partial failure guaranteed** - Replace mock database with real database supporting ACID transactions (PostgreSQL or MongoDB). Implement distributed locking for subscription updates (Redis-based locks). Add compensating transactions to reverse Stripe charges if DB updates fail. Wrap all subscription operations in try-catch with proper rollback. Estimate: 2-3 weeks + database infrastructure costs ($50-200/month).
4. **Zero authorization checks - any user can modify any subscription** - CRITICAL: Add authorization middleware before ANY deployment. Verify req.user.id matches subscription.userId before allowing updates. Add audit logging for all subscription changes. Implement rate limiting specifically for subscription endpoints (beyond the generic 100 req/min). Security review mandatory before production.
4. **No email notification system - PRD requirement impossible** - Integrate email service provider (recommend AWS SES for cost: ~$0.10 per 1000 emails). Implement email templating system, delivery queue with retry logic (reuses job queue from finding #2), bounce/complaint handling, and delivery status tracking. Add email preferences table for user opt-outs. Estimate: 1-2 weeks + ~$10-50/month for email service.
4. **No proration logic implemented - billing errors inevitable** - Add proration_behavior: 'create_prorations' to stripe.subscriptions.update call. Implement invoice.created webhook handler to record proration invoices in database. Add logic to handle negative proration amounts for downgrades (issue credits). Add user-facing proration preview before confirming plan changes. Estimate: 3-5 days development + thorough testing.
4. **In-memory data structures don't scale across multiple instances** - Replace in-memory storage with Redis for: rate limiting (use redis-rate-limit or similar), session storage, distributed locks for subscription updates. Configure app for stateless horizontal scaling behind load balancer. Implement sticky sessions if needed for websocket/long-polling. Redis cost: $30-100/month. Load balancer: $20-50/month. Development: 1 week.
4. **Zero monitoring infrastructure - production failures invisible** - Implement observability stack: (1) Structured logging (Winston/Pino) with correlation IDs, (2) Metrics collection (Prometheus client), (3) APM for distributed tracing (Datadog, New Relic, or self-hosted Jaeger), (4) Alerting rules for: payment failures >1%, Stripe API errors, webhook processing lag, job queue depth >100. Cost: $100-500/month for hosted solution. Development: 1-2 weeks.
4. **No deployment infrastructure or CI/CD - manual deploys are error-prone** - Implement: (1) Dockerfile for containerized deployment, (2) docker-compose.yml for local dev environment matching production, (3) CI/CD pipeline with automated tests, security scanning, and staged rollout, (4) Infrastructure-as-Code (Terraform or CloudFormation) for reproducible environments, (5) Deployment runbook documenting rollback procedures. Use blue-green deployment for zero-downtime updates. Estimate: 1-2 weeks.
4. **No error handling in subscription operations - failures cascade** - Wrap all subscription operations in comprehensive error handling: (1) Specific catch blocks for Stripe errors vs database errors vs validation errors, (2) Proper HTTP status codes (400 for validation, 402 for payment issues, 409 for conflicts, 500 for server errors), (3) Structured error logging with context, (4) User-friendly error messages, (5) Rollback/compensation logic for partial failures. Add input validation middleware. Estimate: 3-5 days.

---

## Review Rounds

### Round 1

- **Sections Reviewed:** SEC-002, SEC-003, SEC-004, SEC-005
- **Decision:** SUFFICIENT
- **Reasoning:** Round 1 (maxRounds limit) completed with 4 sections reviewed by devops persona. Analysis reveals systemic infrastructure gaps affecting all sections: no production database, no monitoring, no deployment pipeline, no webhook infrastructure, no job queue, and critical security issues (localStorage in Node.js, no authorization, PCI violations). Feasibility scores extremely low (2-3/10). Findings are converging on same infrastructure blockers across all reviewed sections. While additional personas (security, engineer, QA) and sections (SEC-006 through SEC-013) would provide more depth, the core systemic issues are clear and actionable. All 15 critical findings relate to missing production infrastructure that blocks deployment. Sufficient information exists to generate report identifying these blockers and estimating remediation effort (6-10 weeks, $300-800/month operational costs).

