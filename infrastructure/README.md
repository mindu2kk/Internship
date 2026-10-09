# AURA AWS infrastructure

This directory implements the approved Release 1 shape only:

`Cloudflare Tunnel -> IPv6-only EC2 -> Docker Nginx -> FastAPI`, with no public IPv4, no inbound security-group rule, no ALB, no NAT Gateway, and no SSH.

It is deliberately safe to review locally:

```powershell
terraform -chdir=infrastructure/aws init -backend=false
terraform -chdir=infrastructure/aws validate
terraform -chdir=infrastructure/aws fmt -check -recursive
```

Phase 1 evidence in `../DEVOPS_PHASE_1_ARCHITECTURE_AND_COST.md` is complete. The approved staging foundation was applied and verified on 2026-10-09; see `../DEVOPS_PHASE_1_COMPLETION_REPORT.md`. This is not a production authorization. Staging must still prove the tunnel, recovery path, immutable release/rollback, and 2 GiB memory/load gate before any production promotion. The default remains `t3a.small`; an AWS Free Tier account that rejects it may use the same-memory x86_64 `t3.small` fallback for this short-lived proof.

## State bootstrap and environments

Terraform state must not remain local. `state-bootstrap/` is a one-time, separately reviewed stack that creates an encrypted, versioned S3 bucket with an S3 lockfile. The staging state backend has been bootstrapped; future environments must follow the same reviewed process. It is not invoked by CI.

For each environment, copy `aws/backend.hcl.example` outside the repository, set its unique state key, then initialize with it:

```powershell
terraform -chdir=infrastructure/aws init -reconfigure -backend-config=C:\secure\aura-staging.backend.hcl
terraform -chdir=infrastructure/aws plan -var-file=C:\secure\aura-staging.tfvars
```

`terraform.tfvars`, backend files, plans, and `.tfstate*` are ignored. They may contain account identifiers and must not be committed.

The GitHub OIDC provider is account-level. Let the first environment create it, then copy that stack's `github_deployer_role_arn`/provider ARN into the second environment's secure tfvars as `github_oidc_provider_arn`; this avoids attempting to create the same provider twice.

## Secret and Cloudflare setup

Terraform creates no secret values, because a `SecureString` managed by Terraform would put its value in state. Before the first instance boot, create these values out of state under the selected environment path:

- `/<project>/<environment>/cloudflare_tunnel_token`
- external AI keys required by the app, for example `openai_api_key`, `google_api_key`, `tavily_api_key`, and `llama_cloud_api_key`

Terraform creates non-secret release/configuration placeholders for the backend image, API-proxy image, Vercel frontend URL, and cloudflared image. Before the first refresh, set `frontend_url` to the owner-approved Vercel/custom URL and `cloudflared_image` to a reviewed x86_64 image **digest**, not a tag. `aura-refresh` rejects `pending` or tag-only image values.

The Cloudflare named tunnel and its public hostname are owner-managed because the domain remains private. Its remote ingress service must target `http://api-proxy:8080`; the tunnel token is the only Cloudflare value installed on EC2. The React frontend remains on Vercel and is not deployed to this host.

The release workflow writes only immutable backend/API-proxy ECR image references to the two non-secret SSM parameters created by Terraform. It runs only by manual dispatch, and its production job uses the GitHub `production` environment with required human approval.

## Monitoring and recovery

The staging origin publishes container logs to CloudWatch for 30 days. The
CloudWatch Agent publishes root-disk and memory utilization, and Terraform
creates CPU, instance-status, memory, and disk alarms plus a small operations
dashboard. Alert delivery requires confirming the owner email subscription sent
by SNS after apply.

Daily backups include a SHA-256 sidecar and can be restored only from the
configured S3 backup bucket. Each release retains a root-only immutable runtime
snapshot for rollback. Use [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md) to
perform and record staging backup/restore and rollback drills; a drill is not
passed merely because its scripts exist.

## Required operator checks

1. Set `budget_alert_email` in a secure tfvars file. The plan intentionally fails without it.
2. Create the owner-approved staging and production GitHub environments. Configure `AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`, `ECR_BACKEND_REPOSITORY`, `ECR_PROXY_REPOSITORY`, `SSM_BACKEND_RELEASE_PARAMETER`, `SSM_PROXY_RELEASE_PARAMETER`, and `PHASE_1_COST_GATE=approved` only after the cost gate passes. Keep production reviewer protection enabled.
3. Confirm the SNS subscription email after Terraform creates the operational-alert topic.
4. Run `terraform plan`; inspect only. A subsequent apply remains a separate cost-producing decision.
5. When an instance exists, verify SSM, ECR dual-stack pull, S3 backup/restore, CloudWatch delivery, and the Cloudflare tunnel before DNS cutover.
