# 3. Give pods AWS access with IRSA, one role per service account

- Status: Accepted
- Date: 2026-11-06

## Context

Three kinds of pods call AWS APIs: the HTTP service (sends to SQS), the
worker (receives from SQS), and two operators (KEDA reads queue depth,
External Secrets reads Secrets Manager on behalf of a workload).

Node instance-profile credentials would give every pod on a node the union of
all permissions, so pods need their own identity.

## Options considered

- **Node IAM role** — simplest, but any pod can use any permission. Rejected.
- **IRSA** (IAM Roles for Service Accounts): the cluster's OIDC issuer is an
  IAM identity provider; a role's trust policy names one
  `system:serviceaccount:<namespace>:<name>`.
- **EKS Pod Identity**: an EKS add-on (agent DaemonSet) plus
  `aws_eks_pod_identity_association` resources; trust policies don't
  reference the cluster's OIDC issuer.

## Decision

Use IRSA. Every workload gets its own IAM role, trusted only by its own
service account (`modules/workload`). KEDA's operator gets a separate role
with no permissions of its own; each queue autoscaler adds read access to one
queue.

Why IRSA over Pod Identity here:

- It works the same way on any Kubernetes cluster with an OIDC issuer, so the
  pattern is portable and widely understood.
- External Secrets' `SecretStore` can authenticate with a workload's own
  service account token (`auth.jwt.serviceAccountRef`). With IRSA that means
  the store has exactly the workload's permissions and no shared "secrets
  reader" role is needed.
- KEDA's chart has first-class IRSA settings for its operator.
- No extra add-on or DaemonSet on the nodes.

## Consequences

- Trust policies contain the cluster's OIDC issuer URL. Replacing the cluster
  (blue/green upgrade) means every role trust must be updated — Terraform does
  it, but it is a reason to revisit Pod Identity if clusters become
  short-lived or numerous.
- A role is tied to one namespace + service account name; renaming either
  breaks access until the role is updated (by design).
- The IAM trust-policy size limit caps how many clusters one role can trust;
  with one role per workload per cluster this is not a concern.
