# 2. Scale queue workers with KEDA on SQS backlog, not HPA on CPU

- Status: Accepted
- Date: 2026-11-06

## Context

Queue workers pull jobs from SQS and call downstream systems (APIs, a
database). Most of their time is spent waiting on I/O, not using CPU.

They were scaled with a standard HorizontalPodAutoscaler on CPU utilisation
(target 70%). In practice this showed two problems:

1. **CPU does not track the backlog.** When a burst of jobs arrives, each pod
   still processes one message at a time and mostly waits on the network.
   CPU stays at 15–30%, the HPA sees nothing to do, and the queue grows.
   Conversely, a CPU-heavy message can trigger a scale-up while the queue is
   nearly empty. The thing we care about — *how long a job waits in the
   queue* — is not an input to the scaling decision at all.

2. **Bursts are handled too late.** Even after switching the signal to queue
   depth, the obvious HPA route reads it from CloudWatch. SQS publishes its
   CloudWatch metrics at one-minute granularity and with a delay of a few
   minutes, and the HPA adds its own sync interval and stabilisation window
   on top. By the time the HPA reacts, a short burst has already turned into
   a latency spike.

What we need: a scaling rule of the form *"one pod per N waiting messages"*,
fed by a near-real-time queue depth, with explicit control over how fast it
scales up and how cautiously it scales down.

## Options considered

### A. HPA on CPU (status quo)

- Built in, nothing to install.
- Wrong signal for I/O-bound consumers (problem 1). Tuning the CPU target
  does not fix it; it only moves the point where it breaks.

### B. HPA on an External metric from CloudWatch (via a metrics adapter)

`ApproximateNumberOfMessagesVisible` exported to the Kubernetes
`external.metrics.k8s.io` API through a CloudWatch or Prometheus adapter,
with an `AverageValue` target per pod.

- Gives the right *kind* of rule (backlog per pod).
- Still bound to CloudWatch's one-minute, delayed SQS metrics (problem 2).
- Adds an adapter plus, for the Prometheus route, an exporter and Prometheus
  itself — more moving parts than option C, and the AWS-specific CloudWatch
  adapter is no longer actively maintained.
- Each queue needs its metric wired through adapter configuration that lives
  far from the worker it scales.

### C. KEDA `ScaledObject` with the `aws-sqs-queue` scaler (chosen)

- KEDA calls `sqs:GetQueueAttributes` directly every `pollingInterval`
  (15 s here), so the backlog it sees is seconds old, not minutes.
- `queueLength` is a per-pod target: desired replicas =
  `ceil((visible + in-flight) / queueLength)`. That is exactly the rule we
  wanted, expressed in one number per worker.
- `scaleOnInFlight` counts messages already being processed, so pods that are
  busy are not scaled away in the middle of a burst.
- Scale-up and scale-down behaviour (HPA `behavior` policies) live in the same
  object as the trigger, next to the worker they apply to.

Important: KEDA does **not replace** the HPA. It creates and owns a regular
HPA (`keda-hpa-<name>`) and serves the queue depth to it as an external metric.
The scaling math and `behavior` policies are still the HPA's. KEDA's job is to
provide a fresh, correct signal and to manage the 0 ↔ 1 transition, which an
HPA cannot do.

### D. KEDA `ScaledJob` (one Kubernetes Job per message batch)

- Good for long, rare, heavy jobs.
- Our workers are long-running consumers handling many short messages; a pod
  start per message would cost more than the work itself.

## Decision

Scale every SQS queue worker with a KEDA `ScaledObject` using the
`aws-sqs-queue` trigger, packaged as the `queue-autoscaler` module:

| Setting | Default | Why |
|---|---|---|
| `messages_per_pod` (`queueLength`) | 20 | What one pod clears within the latency target (≈2 msg/s × 10 s). Set per worker. |
| `scale_on_in_flight` | true | Busy pods count as load. |
| `polling_interval` | 15 s | Fresh enough for bursts. With the HPA's own 15 s metric queries that is up to ~350k `GetQueueAttributes` calls per queue per month, about $0.15. |
| Scale-up | +max(4 pods, 100%) every 15 s, no stabilisation | 1 → 5 → 10 → 20 pods in ~45 s. |
| Scale-down | −50% per minute after 5 min stable | A short lull should not throw away capacity that the next wave needs. |
| `min_replicas` | 1 | See "Scale to zero" below. |
| `max_replicas` | 20 | Protects downstream systems from too many consumers. |
| `fallback_replicas` | 2 | If KEDA cannot read the queue 3 times in a row, hold a safe size instead of freezing. |

KEDA's operator uses its **own** IRSA role. Each `queue-autoscaler` instance
grants that role `sqs:GetQueueAttributes` on exactly one queue. KEDA cannot
read messages, and workers do not need permission to read queue attributes
for scaling.

### Scale to zero

KEDA makes `min_replicas = 0` possible, but it was not a reason for this
decision and is not the default: the first message after an idle period would
wait for a pod to be scheduled and start (and possibly for a node). It is a
per-worker switch for queues where that delay is acceptable.

## Consequences

Good:

- Scaling follows the backlog. A burst of 500 messages produces 20 pods within
  about a minute, regardless of CPU.
- Per-worker tuning is a handful of variables in one module call, reviewed in
  the same pull request as the worker.
- Least-privilege: the scaler can only read queue depth, and only for queues
  that have a `ScaledObject`.

Bad / to watch:

- **Another cluster component.** KEDA's operator and metrics API server must be
  healthy; if the metrics server is down, every KEDA-managed HPA loses its
  metric and stays at its current size. Mitigated by running 2 replicas of each
  and by the `fallback` setting.
- **One external metrics provider per cluster.** KEDA registers the
  `v1beta1.external.metrics.k8s.io` APIService. It cannot coexist with another
  adapter (e.g. prometheus-adapter) serving external metrics. Prometheus-based
  scaling has to go through KEDA's `prometheus` scaler instead.
- **Approximate numbers.** SQS queue attributes are approximate. Fine for
  scaling, not for billing or alerting on exact counts.
- **Scale-down interrupts work.** A removed pod gets SIGTERM while it may hold
  a message. Workers must stop receiving on SIGTERM, finish within
  `terminationGracePeriodSeconds`, and be idempotent, because an unfinished
  message reappears after the visibility timeout. The example worker shows
  the pattern, and the visibility timeout is set to twice the maximum
  processing time.
- **Pods are not nodes.** KEDA adds pods; if the node group is full they stay
  Pending. A node autoscaler (Cluster Autoscaler or Karpenter) is required in a
  real cluster and is out of scope for this repo.
