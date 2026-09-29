# AURA Production Contract — Phase 0

**Status:** Approved for Phase 1 design on 2026-09-27
**Scope:** Production direction for a small public AURA website. This document defines decisions and acceptance criteria; it creates no AWS resources and changes no application runtime.

## 1. Product and load profile

### Initial operating target

| Item | Proposed target | Why it is enough for the first production release |
|---|---:|---|
| Daily users | 100–200 | The stated product target. |
| Concurrent active users | 10 normal / 20 burst | Capacity must be tested against concurrent chat requests, not daily users alone. |
| Public surface | Catalog browsing and Vietnamese shopping-advisor chat | The API is intentionally public; it is not an internal tool. |
| Deployment cadence | Staging on validated `main`; production only after approval | Keeps a small team fast while retaining a release gate. |

These are planning assumptions, not measured production results. A load test before production promotion must validate or revise them.

### Owner-approved operating choices

| Decision | Approved choice |
|---|---|
| Domain ownership | Managed by the owner. |
| DNS | Cloudflare for Release 1. `www` remains on Vercel; `api` is served through Cloudflare to the AWS origin. |
| Monthly infrastructure and AI budget | Target USD 20; hard ceiling USD 25. |
| Cost controls | Enable budget and forecast alerts before creating billable production resources. |
| Chat-history retention | No long-term server-side chat-history storage in the first release. |
| Audit/log retention | 30 days. |
| Availability / RPO / RTO | 99.5% monthly availability, 24-hour RPO, and 60-minute RTO accepted. |
| Frontend hosting | Continue using Vercel. |
| Production deployment | Human approval is mandatory. |

## 2. Service objectives

| Objective | Proposed initial target | Measurement |
|---|---|---|
| Availability | 99.5% per calendar month | External HTTP health and homepage checks. |
| Catalog API latency | p95 under 1.5 seconds | `/api/products` synthetic and access-log measurements. |
| Deterministic advisor latency | p95 under 3 seconds | Structured application metric. |
| External-AI advisor latency | p95 under 8 seconds | Structured application metric, including timeout/fallback outcomes. |
| Error rate | Under 1% 5xx across a rolling 30-minute window | Cloudflare, reverse-proxy, and application logs/alarms. |
| Recovery point objective | 24 hours initially | Daily backup of durable data and reproducible source catalog/index inputs. |
| Recovery time objective | 60 minutes initially | Written restore and rollback runbook exercised in staging. |

The availability target deliberately permits a single-instance launch. It does **not** claim high availability. A move to two application instances across Availability Zones requires a later decision based on measured usage, downtime cost, and budget.

### Cost guardrail

Before any billable production resource is created, Phase 1 must produce a region-specific AWS Pricing Calculator estimate. The design is rejected if the normal monthly estimate exceeds USD 20 or the plausible high-use estimate exceeds USD 25. The initial AWS Budget configuration must notify the owner at 50% actual spend, 80% forecast spend, and 100% actual or forecast spend; it must not automatically delete or stop production resources.

## 3. Architecture decisions

| ID | Decision | Status | Rationale |
|---|---|---|---|
| ADR-01 | Keep the existing Vercel frontend for the first AWS backend release. Use `www` for frontend and `api` for the AWS API. | Approved | Avoids a simultaneous frontend-hosting migration. |
| ADR-02 | Use Cloudflare as the Release 1 DNS/proxy provider. | Approved | Keeps `www` on Vercel and provides the public API edge without an ALB. |
| ADR-03 | Run the FastAPI Docker workload on one x86_64 `t3a.small` EC2 with encrypted EBS. | Approved with cost gate reset | Uses the normal x86_64 container path; the complete AWS calculator estimate must be re-approved before any apply. |
| ADR-04 | Use a Cloudflare Tunnel to an IPv6-only EC2 origin if, and only if, its cost calculation and staging connectivity tests pass. No SSH, FastAPI port, or public IPv4 is exposed. | Proposed replacement | This is the cost-compatible way to remove the public-IPv4 charge and inbound attack surface. It must be proven before selection. |
| ADR-05 | Use Amazon ECR private repository for the AWS production image. | Approved | GitHub Actions and EC2 can use scoped IAM roles without a long-lived GHCR pull token. |
| ADR-06 | Use GitHub Actions OIDC to assume a narrowly scoped AWS deployment role. | Approved | No long-lived AWS access keys in GitHub. |
| ADR-07 | Terraform state is remote, encrypted, versioned, and locked from the first Terraform apply. | Required before Phase 1 implementation | Local state is not a safe shared production control plane. |
| ADR-08 | Staging and production are separate environments with separate state, secrets, URLs, and approval gates. The GitHub `production` environment requires explicit human approval. | Approved | A staging success must not be treated as production evidence. |

## 4. Data and secret inventory

| Asset | Current evidence | Production policy to decide/implement |
|---|---|---|
| Product catalog | CSV selected through `PRODUCT_CATALOG_PATH` | Store source/versioned exports durably; deploy a known catalog revision. |
| Chroma policy/vector data | Persistent local path `./chroma_db` | Define whether it is rebuilt from source or restored from backup; do not leave it only on an instance root disk. |
| Conversation state | Currently supplied in the API request contract | Confirm whether server-side chat history will be retained. If yes, use a durable database with retention policy. |
| External AI credentials | Google/OpenAI, Tavily and Llama Cloud keys are environment inputs | Store only in AWS Secrets Manager or SSM Parameter Store; redact from logs; rotate on exposure. |
| Harness audit trail | Optional `HARNESS_AUDIT_PATH` | Define retention, access control, and whether prompts/responses may contain personal data. |

### Data classification

Initial classification is **internal operational data** for catalog and telemetry, plus **potentially personal content** for user chat text. No production logging or backup policy may assume chat input is non-sensitive.

## 5. Security baseline before public staging

- No AWS root credentials for day-to-day work; MFA and named IAM identities/roles only.
- No public SSH. Operations use Systems Manager Session Manager.
- The public API terminates at Cloudflare. The Release 1 EC2 candidate has no Internet ingress and no public IPv4; Cloudflare Tunnel connects outward from the origin.
- Nginx and FastAPI listen only on loopback/container-local paths behind the tunnel.
- EBS, Terraform state, backups, and secrets are encrypted at rest.
- GitHub OIDC trust is restricted to this repository, branch/environment, and the deploy role's minimum actions.
- Public chat has request-size limits, application-level rate limits, timeout/fallback behavior, and abuse monitoring.
- `/metrics` and diagnostic traces are not a public production interface unless explicitly protected.

## 6. Delivery and recovery contract

```text
Pull request
  -> backend tests + AI regression + frontend build + Docker smoke test
  -> staging deployment of immutable image digest
  -> public staging health/API/AI smoke tests
  -> production approval
  -> production deployment of the same digest
  -> public verification of release SHA and critical paths
```

Rollback means redeploying the previously known-good image digest and confirming public health. It is not "rebuild current source and hope it works".

## 7. Phase 0 exit criteria

Phase 0 is complete. The owner has approved Cloudflare, the minimum Release 1 resource scope, x86_64 `t3a.small`, the Chroma recovery objective, and the GitHub production approval requirement. The production domain is intentionally withheld until DNS configuration begins.

## 8. Immediate Phase 1 work after approval

1. Produce and review the final AWS Pricing Calculator estimate; do not apply Terraform unless it meets both approved cost limits.
2. Prove native x86_64 image/smoke compatibility and Cloudflare Tunnel plus IPv6-only staging connectivity.
3. Build Terraform only for the frozen minimum resource list after those gates pass.
4. Define and test the Chroma/catalog backup-or-rebuild workflow before the first deployment.
