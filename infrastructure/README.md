# AURA AWS infrastructure

This directory implements the approved Release 1 shape only:

`Cloudflare Tunnel -> IPv6-only EC2 -> Docker Nginx -> FastAPI`, with no public IPv4, no inbound security-group rule, no ALB, no NAT Gateway, and no SSH.

It is deliberately safe to review locally:

```powershell
terraform -chdir=infrastructure/aws init -backend=false
terraform -chdir=infrastructure/aws validate
terraform -chdir=infrastructure/aws fmt -check -recursive
```

Do not run `apply` until all Phase 1 evidence in `../DEVOPS_PHASE_1_ARCHITECTURE_AND_COST.md` is complete. In particular, a complete calculator estimate for the approved x86_64 `t3a.micro` must be within USD 20 normal and USD 25 plausible-high use, native x86_64 CI must pass, and a short-lived staging tunnel plus memory/load test must prove the 1 GiB instance is adequate.

## State bootstrap and environments

Terraform's production state must not remain local. `state-bootstrap/` is a one-time, separately reviewed stack that creates an encrypted, versioned S3 bucket with an S3 lockfile. Apply it using controlled administrator credentials only after the cost and account checks are approved. It is not invoked by CI.

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

Terraform creates non-secret release/configuration placeholders for backend image, frontend image, frontend URL, and cloudflared image. Before the first refresh, set `frontend_url` to the real private domain and `cloudflared_image` to a reviewed x86_64 image **digest**, not a tag. `aura-refresh` rejects `pending` or tag-only image values.

The Cloudflare named tunnel and its public hostname are owner-managed because the domain remains private. Its remote ingress service must target `http://frontend:8080`; the tunnel token is the only Cloudflare value installed on EC2.

The release workflow writes only immutable backend/frontend ECR image references to the two non-secret SSM parameters created by Terraform. It runs only by manual dispatch, and its production job uses the GitHub `production` environment; configure that environment to require human approval before enabling the workflow.

## Required operator checks

1. Set `budget_alert_email` in a secure tfvars file. The plan intentionally fails without it.
2. Create the owner-approved staging and production GitHub environments. Configure `AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`, `ECR_BACKEND_REPOSITORY`, `ECR_FRONTEND_REPOSITORY`, `SSM_BACKEND_RELEASE_PARAMETER`, `SSM_FRONTEND_RELEASE_PARAMETER`, and `PHASE_1_COST_GATE=approved` only after the cost gate passes. Add production reviewer protection.
3. Run `terraform plan`; inspect only. A subsequent apply remains a separate cost-producing decision.
4. When an instance exists, verify SSM, ECR dual-stack pull, S3 backup/restore, CloudWatch delivery, and the Cloudflare tunnel before DNS cutover.
