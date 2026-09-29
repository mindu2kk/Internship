# GitHub Release Configuration

This repository deliberately keeps deployment URLs and AWS identifiers out of source control. Complete this configuration in GitHub before treating a release as verified.

## 1. Protect the production environment

In **Settings → Environments → production**:

1. Add the owner as a required reviewer. A deployment pauses until that person approves it.
2. Restrict deployments to the `main` branch.
3. Add these Environment secrets:

| Variable | Value at the current pre-AWS stage |
|---|---|
| `VERCEL_PRODUCTION_URL` | The owner-approved HTTPS Vercel/custom frontend URL, without a trailing slash. |
| `BACKEND_HEALTH_URL` | The owner-approved HTTPS backend base URL, without `/health`. |

The existing verifier adds `/` to the frontend URL and `/health` to the backend URL. It fails clearly if either is absent or not HTTPS.

## 2. Validate the existing Vercel/Render release path

Push a commit to `main`. A successful `CI` workflow automatically starts **Verify Vercel production** in the protected production Environment. The reviewer approves it only after the intended Vercel deployment is live.

For a controlled retry, run **Verify Vercel production** manually, type `VERIFY`, and either rely on the Environment secrets or enter both HTTPS URLs as workflow inputs. This is a health check only; it does not deploy application code.

## 3. Configure AWS only after the Phase 1 gates pass

Do not add these values or run the AWS release workflow until the cost gate, x86_64 image smoke test, and staging tunnel checks have passed:

- `AWS_REGION`
- `AWS_DEPLOY_ROLE_ARN`
- `ECR_BACKEND_REPOSITORY`
- `ECR_FRONTEND_REPOSITORY`
- `SSM_BACKEND_RELEASE_PARAMETER`
- `SSM_FRONTEND_RELEASE_PARAMETER`
- `PHASE_1_COST_GATE=approved`

The release workflow rejects a missing value and cannot run production without the GitHub Environment approval.
