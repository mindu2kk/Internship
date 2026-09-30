# AURA Phase 1 completion report

**Completed:** 2026-09-30
**Scope:** production architecture, Terraform/release scaffold, CI gates, and sustainable AWS cost evidence.
**Safety boundary:** no Terraform apply, AWS resource creation, DNS change, or production deployment was performed.

## Outcome

Phase 1 is complete as a design-and-cost phase. Release 1 uses:

- Vercel for the React frontend.
- Cloudflare DNS and an outbound Cloudflare Tunnel for `api.<domain>`.
- One IPv6-only x86_64 `t3a.small` EC2 origin in `ap-southeast-1`, with no public IPv4 and no inbound security-group rule.
- Nginx as a backend-only API proxy; frontend static assets are not duplicated on EC2.
- FastAPI and Chroma on encrypted gp3 EBS, daily recovery inputs/snapshots, S3, ECR, SSM, CloudWatch, GitHub OIDC, and AWS Budget alerts.
- Explicit human approval in the GitHub `production` Environment.

## Cost gate

| Scenario | Calculator | ECR/S3/CloudWatch allowance | Total | Approved limit |
|---|---:|---:|---:|---:|
| Normal | USD 22.10 | USD 0.50 | **USD 22.60** | USD 23 |
| Plausible high | USD 27.16 | USD 0.50 | **USD 27.66** | USD 28 |

Saved evidence:

- Normal: https://calculator.aws/#/estimate?id=72ef5410d4837bc742ba2ac6bae08b39f6006c5b
- Plausible high: https://calculator.aws/#/estimate?id=ef0a6dfa4ccf84c4fcddc675347a5ad8224e86d3

The estimates use on-demand pricing and do not deduct free-tier credits. Taxes and external-AI provider usage are outside the AWS infrastructure gate.

## Verified gates

| Gate | Result |
|---|---|
| Native `linux/amd64` backend build, `/health`, and catalog smoke | Passed in GitHub Actions run `36549156799`. |
| Vercel production verification | Passed in run `36562367656`. |
| Current public endpoints | Vercel frontend and existing Render `/health` both returned HTTP 200 on 2026-09-30. |
| GitHub Production approval protection | Configured with required reviewer, `main`-only deployment, and no administrator bypass. |
| Terraform/static bootstrap | Revalidated locally after the Vercel/API-proxy architecture correction. |
| Backend-only API proxy | Image build, standalone `/healthz`, and AWS Compose rendering passed locally. |
| AWS apply | **Not run.** |

## Next gate before staging apply

Phase 1 completion does not make the AWS topology a deployed system. Before any staging apply:

1. Review the fresh Terraform plan after this Phase 1 commit.
2. Confirm the MFA-authenticated operator session and the owner-approved alert email.
3. Confirm the private Cloudflare tunnel hostname/token and reviewed cloudflared digest outside Git.
4. Obtain explicit approval for the short-lived billable staging apply.
5. In staging, prove SSM, ECR dual-stack pull, Cloudflare Tunnel, health/catalog, backup/restore, rollback, and memory/load behavior on the 2 GiB host.

Production remains blocked until staging passes and a human approves the protected GitHub production deployment.
