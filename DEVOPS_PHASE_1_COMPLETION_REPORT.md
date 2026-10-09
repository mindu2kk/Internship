# AURA Phase 1 completion report

**Design completed:** 2026-09-30

**Staging infrastructure applied and verified:** 2026-10-09

**Scope:** production architecture, Terraform/release scaffold, CI gates, sustainable AWS cost evidence, remote state bootstrap, and the first AWS staging infrastructure apply.

**Safety boundary:** staging infrastructure is live, but no application image, Cloudflare tunnel/DNS change, or production deployment has been performed.

## Outcome

Phase 1 is complete as a design-and-cost phase. Release 1 uses:

- Vercel for the React frontend.
- Cloudflare DNS and an outbound Cloudflare Tunnel for `api.<domain>`.
- One IPv6-only x86_64 EC2 origin in `ap-southeast-1`, with no public IPv4 and no inbound security-group rule. The staging account rejected `t3a.small` under its Free Tier restriction, so the applied staging host uses the approved same-memory `t3.small` fallback.
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
| Terraform state bootstrap | Applied: encrypted/versioned private S3 state bucket, with a dedicated staging state key and S3 lockfile. Account-specific backend details remain outside Git. |
| AWS staging infrastructure | Applied: 34 Terraform-managed staging resources/state entries plus the separately managed five-resource state bootstrap. Final plan returned exit code 0 and `No changes`. |
| EC2 security/runtime | The staging origin is running as `t3.small`; no public IPv4, zero ingress rules, IMDSv2 required, encrypted 20 GiB gp3 root volume, and SSM Online. Resource identifiers remain outside Git. |
| Host bootstrap | Cloud-init completed; Docker 25 and Docker Compose v5.6.0 are active. The Compose binary matched the pinned SHA-256, and the deployment/backup scripts and daily backup timer were verified through SSM. |
| Cost guardrail | AWS Budget cap is USD 28; the AWS forecast at verification time was USD 20.017. |
| Application deployment | **Not run.** ECR repositories and release parameters are prepared, but application images, runtime secrets, Cloudflare Tunnel, and DNS cutover remain pending. |

## Remaining staging release gates

The Terraform foundation is deployed, but the website/API is not yet served from AWS. Complete these gates before calling staging operational:

1. Replace the temporary root bootstrap session with an MFA-protected least-privilege operator/assume-role flow for every future Terraform change.
2. Configure the private Cloudflare tunnel hostname/token and a reviewed cloudflared image digest outside Git.
3. Configure the remaining runtime secrets and the approved Vercel frontend URL in SSM.
4. Build and push immutable backend/API-proxy images to ECR, then run the manual staging release workflow.
5. Prove the public tunnel health/catalog path, CloudWatch delivery, backup/restore, rollback, and memory/load behavior on the 2 GiB host.

Production remains blocked until staging passes and a human approves the protected GitHub production deployment.
