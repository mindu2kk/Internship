# AURA Phase 1 operator identity

This directory records the manually bootstrapped IAM access model used before Terraform can manage Release 1 resources.

- IAM user: `aura-terraform-operator`
- Provisioning role: `aura-phase1-provisioner`
- Role policy: `aura-phase1-provisioner-policy.json`

The user receives no direct infrastructure permissions. It can only call `sts:AssumeRole` for the provisioning role. The role trust policy requires `aws:MultiFactorAuthPresent=true`; an unprotected sign-in cannot assume it.

No access key or console password is created by this bootstrap. The owner must create a console login profile, sign in as the new user, enrol a virtual or hardware MFA device, and then use short-lived assumed-role credentials locally. Never add an access key, temporary password, MFA seed, or QR code to this repository.

The provisioner policy permits only the AWS service actions needed by the current Phase 1 Terraform scope: VPC/EC2 networking, ECR, S3, CloudWatch Logs, scoped SSM/Budgets operations, and creation of the AURA runtime/OIDC IAM resources. It is intentionally attached to the role rather than directly to the user.
