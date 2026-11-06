# 4. Deliver secrets with External Secrets Operator

- Status: Accepted
- Date: 2026-11-06

## Context

The worker needs a token for a downstream API. The value is owned in AWS
Secrets Manager (rotation, audit, access via IAM). It must not appear in Git,
in Terraform variables, or in container images.

## Options considered

- **Kubernetes Secret written by Terraform** — the value passes through
  Terraform state and plan output. Rejected.
- **App reads Secrets Manager with the AWS SDK** — no copy in the cluster,
  but every service needs SDK code, caching and retry logic for config.
- **Secrets Store CSI Driver** — mounts secrets as files; syncing to env vars
  needs an extra option and the pod must be running for the sync to happen.
- **External Secrets Operator (ESO)** — an `ExternalSecret` keeps a normal
  Kubernetes Secret in sync with Secrets Manager; the app sees env vars.

## Decision

Use ESO. Each workload that declares `secrets` gets its own `SecretStore`
authenticated with **its own** service account (IRSA, see ADR 3) and an
`ExternalSecret` that produces `<name>-env`, loaded with `envFrom`.
The ESO controller itself has no AWS permissions.

## Consequences

- Applications stay simple: configuration is environment variables.
- A workload can only read secrets its own IAM role allows; one team's store
  cannot read another team's secrets.
- The value exists as a Kubernetes Secret in etcd. The cluster module enables
  KMS envelope encryption for Secrets for this reason.
- Env vars are read at process start. After a rotation ESO updates the Secret
  within `refreshInterval`, but running pods keep the old value until they
  restart (a tool like Reloader, or a rollout, handles this).
- The example generates the demo token with `random_password`, which does put
  it in Terraform state. That is a shortcut for a self-contained example only;
  in real use the secret value is set outside Terraform.
