# AURA Phase 1 — AWS Architecture and Cost Gate

**Status:** `t3a.micro` is the approved x86_64 candidate. A complete calculator estimate and 1 GiB staging memory/load evidence are required before any Terraform apply.
**Date:** 2026-09-29
**Depends on:** `DEVOPS_PHASE_0_PRODUCTION_CONTRACT.md`

## 1. Owner decisions captured

The owner approved the following Release 1 constraints on 2026-09-27:

- Cloudflare is the DNS/proxy provider; `www` stays on Vercel and the actual production domain stays private until DNS work.
- The sustainable AWS limit is USD 20 in a normal month and USD 25 under plausible high use. A calculator result above either threshold prohibits `terraform apply`.
- x86_64 `t3a.micro` is the approved compute candidate. This architecture change resets the calculator gate; the previous ARM and `t3a.small` estimates cannot authorize an apply.
- Chroma uses encrypted EBS and must have a daily S3 backup/rebuild path proven in staging for the 24-hour RPO.
- The resource scope is frozen to VPC/networking, EC2, encrypted EBS, IAM, ECR, S3, SSM, CloudWatch, secrets, and AWS Budget. ALB, NAT Gateway, RDS, ASG, Kubernetes, and multi-AZ replicas are deferred.
- The GitHub `production` environment requires an explicit human approval before promotion.

## 2. Cost-driven architecture correction

Phase 0 approved a USD 20 target and USD 25 hard monthly ceiling. The original proposal of an AWS Application Load Balancer (ALB) in front of EC2 is technically sound, but it is not compatible with that first-release budget.

AWS bills an ALB for every running hour and for Load Balancer Capacity Units. AWS's published US-East example puts the hourly ALB base rate at USD 0.0225, or about USD 16.43 for 730 hours before LCU usage; a `t3a.small` reference price in the same region is USD 0.0188/hour, about USD 13.72/month before storage, public IPv4, backup, logs, or transfer. This already exceeds the hard ceiling and South-East Asia pricing can differ. The pricing gate therefore rejects **ALB + EC2** for the first release.

NAT Gateway is also excluded from the initial topology because it adds both an hourly and per-GB processing charge.

A direct public IPv4 address on EC2 is also too expensive for the normal-month limit. AWS charges USD 0.005 per hour for one public IPv4 address, or USD 3.65 for 730 hours. The exact Singapore `t3a.micro` rate requires a new AWS Pricing Calculator run, so no cost conclusion is claimed from the prior `t3a.small` result. The public-IPv4 surcharge remains a known budget risk; the IPv6-only tunnel design stays the selected candidate pending proof.

## 3. Candidate architectures

| Option | Description | Production properties | Cost-gate result |
|---|---|---|---|
| A — ALB + EC2 | Public ALB, EC2 private target, ACM TLS | Best network isolation and upgrade path to multiple instances | **Rejected for Release 1:** fixed ALB cost plus EC2 exceeds USD 25 before normal operational extras. |
| B1 — Cloudflare + public-IPv4 EC2 | Cloudflare proxies `api` to HTTPS Nginx/FastAPI on EC2 | No public SSH or FastAPI; one compute single point of failure | **Rejected:** public IPv4 means the normal-month floor already consumes the USD 20 budget. |
| B2 — Cloudflare Tunnel + IPv6-only EC2 | Cloudflare Tunnel makes an outbound connection from EC2 to Cloudflare; tunnel forwards locally to Nginx/FastAPI | No Internet ingress, no public IPv4, one compute single point of failure | **Selected candidate with `t3a.micro`:** cost and 1 GiB memory/load gates must both pass before staging. |
| C — ALB/ASG | ALB with at least two application instances and rolling replacement | Higher availability and safer host replacement | **Deferred:** revisit after measured demand or a higher budget. |

This is an explicit trade-off: Release 1 targets recoverability and controlled deployment, not multi-AZ high availability. It remains consistent with the accepted 99.5% availability objective.

## 4. Recommended Release 1 topology

```text
Users ── HTTPS ──> www.<domain> ──> Vercel frontend
Users ── HTTPS ──> api.<domain> ──> Cloudflare edge ──> Cloudflare Tunnel
                                                               │ outbound IPv6
                                                               v
                                                       EC2 (no public IPv4/inbound)
                                                               │
                                      cloudflared ──> Nginx loopback ──> Docker FastAPI :8000
                                                                        │
                                      encrypted EBS: Chroma data   S3: backup/state
                                                                        │
                                  ECR image pull · SSM operations · CloudWatch logs
```

### AWS resources in scope for the first design

| Area | Minimum component | Design rule |
|---|---|---|
| Region | `ap-southeast-1` candidate | Use for the first estimate because it is close to the primary audience and broadly supports the required services. It is not selected until the calculator result and IPv6 service-connectivity test are approved. |
| Compute | One EC2, 1 GiB-memory candidate | Use x86_64 `t3a.micro`; do not select it from price alone. A complete calculator estimate and staging memory/load result are mandatory. |
| Network | VPC, one IPv6-enabled subnet, Internet Gateway, restrictive security group | The instance has no open inbound rule, no public IPv4, and FastAPI/Nginx are loopback-only. Outbound IPv6 is tested only for required Cloudflare and AWS services. |
| Public ingress | Cloudflare Tunnel to `api.<domain>` | The tunnel's authenticated outbound connection replaces a public origin listener. Cloudflare owns public TLS; tunnel credentials are stored as a secret, never in image or Git. |
| Image registry | ECR private repository | Image is tagged by Git SHA and deployed by immutable digest. |
| Operations | SSM Session Manager | No bastion and no SSH key management. |
| Data | Encrypted EBS mounted outside the container root | Chroma lives at an explicit data mount, not on an accidental container/OS path. |
| Backup | S3 bucket plus EBS snapshot policy | Daily backup/rebuild input for the 24-hour RPO; restore is tested in staging. |
| Secrets | Standard SSM Parameter Store `SecureString` with the AWS-managed SSM KMS key | External-AI keys never enter image layers, Git, logs, or Terraform state. |
| Observability | CloudWatch Logs, basic metrics, AWS Budget | Cost, instance health, disk, container/app health, and access logs are retained for 30 days. |

`www` stays on Vercel. The current frontend API routing must later be changed from the Render URL to `https://api.<domain>` only after staging proves the AWS backend.

## 5. DNS and TLS decision

**Approved:** Cloudflare is the owner-managed DNS provider for Release 1.

- `www.<domain>` is a Vercel record.
- `api.<domain>` is a Cloudflare-managed hostname that routes through the tunnel to the EC2 origin.
- Cloudflare gives the low-cost topology a proxy/rate-control layer without a public origin. The EC2 security group must have no inbound Internet rule.
- The production domain is not recorded here and is not placed in public source until the owner supplies it for DNS configuration.

The remaining decision gate is evidence, not ownership: prove x86_64 and IPv6/tunnel connectivity in staging, then obtain a passing calculator estimate.

## 6. Preliminary monthly cost model

This is a bill-of-material and risk gate, **not a quote**. Prices vary by region, tax, data transfer, image size, logs, and external-AI usage. AWS Pricing Calculator must produce the final estimate after the region and instance architecture are selected.

| Cost item | Release 1 approach | Budget treatment |
|---|---|---|
| EC2 | One 2 GiB candidate, on demand | Largest fixed item; select only after memory/load test. |
| Public IPv4 | None; use IPv6-only EC2 with Cloudflare Tunnel | Required to preserve the USD 20 normal-month headroom. A direct-public-IPv4 variant is rejected. |
| EBS | Small encrypted gp3 volume for OS and Chroma | Size from measured Chroma growth; snapshots are separate. |
| ECR | Small immutable image retention set | Retain current and rollback images; lifecycle-delete old images. |
| S3 | Terraform state and compact daily backup/rebuild inputs | Versioned state; lifecycle policy for old backup versions. |
| CloudWatch | 30-day logs and a minimal alarm set | Sampling/retention must avoid uncontrolled log cost. |
| Cloudflare | DNS/proxy plan chosen by owner | Treat any paid plan separately from AWS budget. |
| External AI | Per-provider usage | Set provider quotas independently; this is not an AWS infrastructure charge. |

### Budget headroom before the calculator run

The following is a conservative decision worksheet, **not** the final calculator result. It assumes 730 running hours and excludes tax and external-AI usage.

| Item | Preliminary monthly amount | Basis | Decision use |
|---|---:|---|---|
| Linux `t3a.micro` in Singapore | Pending recalculation | The prior ARM64 and `t3a.small` prices are not transferable to this candidate. | New AWS Pricing Calculator result required. |
| Public IPv4 | USD 0.00 | IPv6-only tunnel design | Direct IPv4 would add USD 3.65 and fail the normal gate. |
| 20 GiB encrypted gp3 EBS | USD 1.92 | Public AWS Pricing Calculator input for `ap-southeast-1`; no extra IOPS or throughput | Calculator-verified, before snapshots. |
| Daily snapshot allowance | USD 1.75 | Daily snapshots with 1 GiB changed per snapshot | This is a 30-day, 30 GiB incremental-snapshot assumption, not a full-volume copy each day. |
| Core EC2 + EBS + snapshot | **USD 19.15** | Public AWS Pricing Calculator, on-demand Linux, 730 hours | Leaves only **USD 0.85** for ECR, S3, CloudWatch Logs, and any paid data transfer. |

**Provisional conclusion:** B2 is the only in-scope topology that can still meet the budget, but its **normal-month gate is not yet passed**: its calculator-verified core is USD 19.15, so all remaining normal-use AWS services must fit within USD 0.85. B1 cannot meet the normal limit. No apply is approved until the complete normal and high estimates both pass.

### Required estimator output

Before `terraform apply`, record:

1. Selected AWS region and exact instance type.
2. Normal-month and plausible-high-use estimates, excluding and including tax where applicable.
3. Native x86_64 image build/smoke evidence and a staging memory/load result for the selected `t3a.micro` target.
4. Any free-tier credit assumption, separately from sustainable recurring cost.
5. A monthly AWS Budget: 50% actual, 80% forecast, and 100% actual/forecast alerts. Alerts notify only; they do not automatically stop production.

## 7. Security and data boundary

| Inbound path | Allowed | Forbidden |
|---|---|---|
| Internet → Vercel | Public HTTPS | Direct backend credentials or secrets. |
| Internet → Cloudflare → Tunnel → EC2 | Public API through authenticated outbound tunnel | Any EC2 inbound port, public IPv4, SSH, Docker socket, FastAPI `:8000`, Chroma, SSM, or ECR. |
| EC2 → AWS | ECR pull, SSM, approved secret reads, S3 backup, CloudWatch | Broad AWS administrative permissions. |
| GitHub Actions → AWS | OIDC-assumed deployment role only | Long-lived AWS access keys. |

The app currently has external-AI environment keys and an optional audit path, while its Chroma store is persistent local storage. These inputs are the reason EBS mount, secret manager, log redaction, and 30-day retention are Phase 1 design requirements rather than later polish.

## 8. Phase 1 exit criteria

Phase 1 design is approved when all items below are recorded and reviewed:

- [x] Owner chose Cloudflare for Release 1.
- [x] Owner will provide the actual domain privately when DNS work begins; no domain is written into public source until approved.
- [ ] AWS Pricing Calculator estimate for the selected region/instance satisfies USD 20 normal and USD 25 high-use thresholds.
- [ ] Native x86_64 image choice is proven by a CI build/smoke test.
- [x] Chroma recovery requires encrypted EBS plus a daily backup/rebuild path and staging restore test.
- [x] Terraform resource list is frozen before any apply.
- [x] Production promotion requires an explicit GitHub `production` environment approval.

## 9. Explicitly deferred

- ALB, NAT Gateway, private-subnet-only EC2, RDS, Auto Scaling Group, multi-AZ application replicas, Kubernetes, and managed vector database.
- Production resource creation, DNS mutation, AWS account configuration, domain changes, and any Terraform apply.

These are deferrals driven by the approved cost ceiling, not omissions. The architecture can graduate to ALB + Auto Scaling Group when observed demand and budget justify it.

## 9.1 Implementation scaffold — 2026-09-28

The owner authorized implementation of the reviewed code artifacts, while AWS creation, DNS mutation, and Terraform apply remain out of scope until the gates below pass.

| Implemented artifact | Purpose | Current evidence boundary |
|---|---|---|
| `infrastructure/state-bootstrap` | Encrypted, versioned S3 state bucket with S3 lockfile support | `terraform validate` passed; it has not been applied. |
| `infrastructure/aws` | IPv6-only VPC/subnet/route, no-ingress origin security group, x86_64 `t3a.micro` EC2, encrypted gp3 root/data disk, ECR, S3 backup bucket, CloudWatch log group, SSM release pointers, IAM, Budget, and GitHub OIDC roles | `terraform validate` passed with the backend disabled; no plan or apply ran against an AWS account. |
| `SourceCode/deploy/aws` | Immutable-digest refresh, Cloudflare Tunnel container, 30-day log target, daily Chroma-only S3 backup timer, and no persistent chat database | Shell syntax and Compose rendering passed with inert test values; EC2/IPv6 runtime has not been tested. |
| `.github/workflows/aws-validate.yml` | Terraform static checks plus native x86_64 backend build/health/catalog smoke gate | GitHub Actions run `36549156799` passed. |
| `.github/workflows/aws-release.yml` | Manual release of the exact x86_64 image digests through OIDC, SSM, and a GitHub Environment approval gate | Defined locally but not enabled or run. Production approval must be configured in GitHub before use. |

The implementation intentionally refuses to refresh if either AURA image or `cloudflared` is not an immutable digest. Secrets are fetched from SSM at runtime and never placed in Terraform values, state, workflow logs, or source files.

## 10. Gate execution record — 2026-09-28

### Native x86_64 container gate

| Check | Evidence | Result | Consequence |
|---|---|---|---|
| Local Docker engine | Docker Desktop is available. A native x86_64 build started, pulled the base image, then made no further progress while installing dependencies and was safely cancelled. | **Incomplete** | This is neither an architecture failure nor a passing smoke result; dependency resolution/download behavior must be made reproducible before retrying. |
| Existing CI evidence | The current Docker job builds and runs a Compose smoke test on the default GitHub Linux runner. | **Relevant but insufficient** | It does not prove the new dedicated Phase 1 x86_64 workflow has run. |
| Static image review | `python:3.11-slim`, `node:22-slim`, and `nginx:1.27-alpine` support x86_64. The Python dependency set includes resolver- and native-wheel-sensitive packages such as `PyMuPDF`, `chromadb`, and Hugging Face-related dependencies. | **Plausible, unproven** | A real native x86_64 build plus runtime smoke remains the acceptance evidence. |

The implementation defines a dedicated native `linux/amd64` CI job. It does not use QEMU. It builds the backend image, runs it with safe AI credentials disabled, and proves both `GET /health` and `GET /api/products?limit=1`. The existing frontend-image smoke is useful for its own packaging but is not a deployment gate for the Vercel frontend.

### IPv6-only origin connectivity gate

The staging instance must prove each dependency below before any production promotion:

| Dependency | Required staging proof |
|---|---|
| Cloudflare Tunnel | `cloudflared` x86_64 process establishes its outbound tunnel and serves the approved staging hostname. Cloudflare documents outbound-only connections on port 7844, with no public origin IP or inbound port. |
| ECR | EC2 pulls the immutable image through the dual-stack registry form `<account>.dkr-ecr.ap-southeast-1.on.aws`. |
| SSM | Use an SSM Agent version and configuration that enable dual-stack endpoints; verify Session Manager opens without SSH. For IPv6-only nodes, AWS documents `ssm`, `ssmmessages`, and `ec2messages` regional `.api.aws` endpoints. |
| S3 | Backups upload and restore through the regional S3 dual-stack endpoint. |
| Secrets and logs | EC2 reads only the allowed SSM SecureString paths and delivers bounded CloudWatch logs; no secret appears in command output or logs. |

This ordering is intentional: a passing calculator estimate comes **before** a billable staging apply. The native x86_64 CI gate can run before or after that estimate; tunnel and IPv6 reachability require an approved, short-lived staging environment and therefore cannot be truthfully proven from this Windows workstation alone.

### Calculator input sheet

Create one public AWS Pricing Calculator estimate for `ap-southeast-1`, on-demand Linux, 730 hours/month, with no free-tier-credit deduction. Record normal and plausible-high scenarios separately:

| Service | Normal input | Plausible-high input | Cost control |
|---|---|---|---|
| EC2 | 1 × `t3a.micro`, 730 hours | same | No Savings Plan is assumed. |
| EBS gp3 | 20 GiB encrypted root/data capacity plus daily snapshots with 1 GiB changed per snapshot | 30 GiB capacity plus the same 30-day, 30 GiB incremental snapshot allowance | Do not provision extra IOPS or throughput. |
| ECR private | 1 GiB retained images: current plus rollback | 4 GiB | Lifecycle policy deletes untagged images and retains only approved rollback candidates. |
| S3 | 2 GiB for Terraform state, catalog/rebuild inputs, and compressed daily backups | 15 GiB | Versioned state; explicit lifecycle expiry for old noncurrent objects/backups. |
| CloudWatch Logs | 0.5 GiB ingest and 30-day retention | 3 GiB ingest and 30-day retention | Structured operational logs only; never log chat content, secrets, or unbounded debug traces. |
| Data transfer | 20 GiB internet egress | 80 GiB internet egress | Both remain within AWS's shared 100 GiB/month free data-transfer-out allowance, subject to the account not consuming it elsewhere. |
| Parameter Store / Budgets | Standard SecureString parameters and notification-only budget | same | Standard Parameter Store has no additional charge; notification-only AWS Budgets are free. |

`Secrets Manager` is deliberately not the Release 1 default: a small number of Standard SSM `SecureString` parameters with the AWS-managed SSM KMS key meet this workload's low-scale needs without a per-secret recurring charge. This is not a reduction in secret handling: values remain encrypted, IAM-scoped, excluded from Terraform state, and read only at deployment/startup.

### Prior ARM64 calculator record — invalidated

On 2026-09-28, a calculator exploration for Linux `t4g.small` produced a working design estimate of USD 19.87 normal and USD 22.90 plausible high. It was neither a saved calculator estimate nor an x86_64 estimate. The owner later selected `t3a.micro`, therefore **those figures are invalid for Release 1 and do not authorize `terraform apply`**.

### Prior x86_64 calculator record — rejected

On 2026-09-29, the public AWS Pricing Calculator was configured for `ap-southeast-1`, Linux, shared tenancy, one on-demand `t3a.small` instance, and 730 hours/month. It reported **USD 17.23/month for the instance alone**. The required 20 GiB gp3 EBS volume adds USD 1.92/month, producing a **USD 19.15/month minimum before snapshots, ECR, S3 backups, CloudWatch Logs, data transfer, or tax**.

The USD 0.85 remainder cannot cover the mandatory daily recovery path and operational services. Therefore the normal-month estimate cannot meet the approved USD 20 limit; a plausible-high estimate cannot repair a failed normal gate. This is a valid **REJECTED** result for `t3a.small`; it does not apply to the owner-approved `t3a.micro` candidate below.

### Current x86_64 calculator record — pending

The owner approved `t3a.micro` on 2026-09-29 to keep x86_64 while restoring cost headroom. Before any apply, record a fresh public AWS Pricing Calculator normal and plausible-high estimate for this exact instance, then prove the 1 GiB host can complete the approved staging health, catalog, backup/restore, and memory/load checks without swap pressure or OOM termination.

### Execution tracker — 2026-09-29

| Gate | Status | Evidence / next action |
|---|---|---|
| Terraform and bootstrap static validation | Passed locally | Both configurations validate with remote backends disabled; no plan or apply against an AWS account. |
| Native x86_64 workflow | Passed | GitHub Actions run `36549156799` built the x86_64 image and passed health/catalog smoke after the readiness repair. Instance memory remains a separate staging gate. |
| Existing Vercel release verification | Waiting for human approval | The workflow now reads the two existing GitHub **Environment variables**, not secrets. Run `36551268257` is correctly paused at the protected Environment. |
| GitHub `Production` Environment | Configured | Required reviewer `mindu2kk`, `main`-only deployments, and no administrator bypass are enabled. The two approved URL variables remain in that Environment. |
| AWS cost gate | Pending `t3a.micro` estimate | The `t3a.small` result remains rejected; the owner authorized a new x86_64 micro estimate. |
| AWS staging | Blocked by current cost and memory gates | No plan/apply, account configuration, or billable staging resource may proceed until the new estimate and 1 GiB memory/load gate pass. |

## Sources used for the estimate gate

- AWS ELB pricing: https://aws.amazon.com/elasticloadbalancing/pricing/
- AWS EC2 T3/T3a reference pricing: https://aws.amazon.com/ec2/instance-types/t3/
- AWS NAT Gateway pricing model: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html
- AWS public IPv4 charging note: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-ip-addressing.html
- AWS public IPv4 pricing: https://aws.amazon.com/vpc/pricing/
- AWS EBS pricing: https://aws.amazon.com/ebs/pricing/
- AWS Budgets: https://aws.amazon.com/aws-cost-management/aws-budgets/
- Cloudflare Tunnel architecture: https://developers.cloudflare.com/tunnel/
- Cloudflared downloads: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/
- AWS IPv6 service support: https://docs.aws.amazon.com/vpc/latest/userguide/aws-ipv6-support.html
- AWS ECR IPv6 image pulls: https://docs.aws.amazon.com/AmazonECR/latest/userguide/ecr-ug.pdf
- AWS SSM in IPv6-only environments: https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager-server-patching-iPv6-tutorial.html
- AWS Systems Manager pricing: https://aws.amazon.com/systems-manager/pricing/
- AWS Budgets pricing: https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/
- AWS EC2 data transfer pricing: https://aws.amazon.com/ec2/pricing/on-demand/
