# 1. Record architecture decisions

- Status: Accepted
- Date: 2026-11-06

## Context

Choices in this repo (how workers scale, how pods get AWS access, how secrets
reach the app) are not obvious from the Terraform alone. Six months from now
the code shows *what* was built, not *why*, or which options were rejected.

## Decision

Keep Architecture Decision Records in `docs/decisions/`, one Markdown file per
decision, numbered in order. Each record has Context, Options considered,
Decision, and Consequences (good and bad).

A record is never rewritten after it is accepted. If a decision changes, a new
record supersedes it and the old one gets `Status: Superseded by NNNN`.

## Consequences

- Reviewers and new team members can read the reasoning next to the code.
- A decision that turns out wrong is visible as a decision, with the
  assumptions it was based on, which makes it easier to revisit.
