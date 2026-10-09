# AURA staging operations runbook

This runbook is for the Terraform-managed AWS staging origin. It deliberately
contains commands and identifiers only; application keys remain in SSM
SecureString parameters outside Git.

## Release prerequisites

Before the first staging release, create these SSM SecureStrings:

- `/aura/staging/api_bearer_token`
- only the external-AI keys actually enabled by the backend

Set the non-secret SSM `frontend_url` to the approved HTTPS Vercel URL.
Configure the staging GitHub Environment with the Terraform outputs for AWS
Region, OIDC deploy-role ARN, ECR repositories, and release-parameter names.
Then dispatch the `AWS release` workflow with `staging` and confirmation
`RELEASE`.

## HTTPS and DNS cutover

Apply the ALB stack once with `enable_https_listener=false`. Terraform outputs
an ACM DNS-validation CNAME; create that exact CNAME in ZoneDNS. When ACM marks
the certificate as issued, set `enable_https_listener=true` and apply again.
After the ALB target is healthy, create the public ZoneDNS CNAME for the API
hostname using the `alb_dns_name` output. Do not create A or AAAA records for
the EC2 origin.

## Monitoring and alerts

The origin sends container logs to the 30-day CloudWatch log group. The
CloudWatch Agent reports only memory and root-disk utilization every 60 seconds
under `AURA/staging`; EC2 supplies CPU and status metrics. The Terraform
dashboard combines those four signals, while SNS emails the owner for status,
CPU, memory, and disk alarms.

After `terraform apply`, confirm the SNS subscription email. An unconfirmed
email subscription cannot deliver alerts.

## Backup and restore drill

The daily timer uploads both `aura-<timestamp>.tar.gz` and its SHA-256 sidecar
to the private S3 backup bucket. To create an on-demand backup, dispatch
`AWS operational recovery` with `operation=backup` and confirmation `OPERATE`.

At least once per staging release, use Session Manager to run:

```bash
sudo /usr/local/bin/aura-restore s3://<backup-bucket>/daily/aura-<timestamp>.tar.gz
```

The restore command refuses a bucket outside the configured backup bucket,
verifies the downloaded checksum before extraction, retains the previous Chroma
directory under `/srv/aura/data/`, then starts the Compose stack and checks the
local API-proxy health endpoint. Record start/end times and the selected backup
timestamp. The drill passes only if its backup age is no more than 24 hours and
the service is restored within 60 minutes.

## Rollback drill

Every successful `aura-refresh` stores a root-only runtime snapshot under
`/etc/aura/releases/`; only the latest ten are retained. Pick a previous
`release-YYYYMMDDTHHMMSSZ-<12hex>.env` snapshot, then dispatch `AWS operational
recovery` with `operation=rollback`, that exact filename, and confirmation
`OPERATE`. The command pulls the immutable image references from that snapshot,
waits for Compose health, and checks local `/healthz`.

The first release has no older version to roll back to. Create and verify a
second release before treating the rollback drill as passed.

## Incident sequence

1. Inspect the CloudWatch dashboard and the relevant alarm.
2. Use SSM, never SSH, to inspect `cloud-init`, Docker, ALB target health, and
   `docker compose` status.
3. If release-related, rollback to the last known-good snapshot.
4. If Chroma data is suspected, restore the newest checksum-verified backup.
5. Record impact, timestamps, root cause, and corrective action before the next
   production promotion.
