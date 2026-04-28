# Netheos Architecture

## Overview

Netheos is a Kubernetes-native observability platform composed of 4 workloads:

```
Browser
  │  GET /            → netheos-webui (nginx:8080)
  │  SSE /ws          → proxy → netheos-aggregator:9091  (ClusterSnapshot every 800ms)
  │  POST /api/llm    → proxy → netheos-aggregator:9091  (AI Assistant queries)
  │
netheos-aggregator (Deployment)
  │  Generates ClusterSnapshot every 800ms from live flows + K8s API
  │  Proxies AI queries → Ollama:11434/api/chat (or external LLM)
  │  Exposes /metrics for Prometheus
  │  Enforces RBAC via TokenReview + SubjectAccessReview
  │
netheos-operator (Deployment)
  │  Watches NetheosConfig CR
  │  Reconciles: Namespace → RBAC → DaemonSet → Ollama → Aggregator → WebUI
  │  Evaluates NetheosAlert threshold rules
  │  Runs NetheosInsight scheduled AI queries
  │  Tracks NetheosService health metrics
  │
netheos-agent (DaemonSet — every node)
  │  Attaches eBPF probes at kernel level (CAP_SYS_ADMIN)
  │  Captures L3/L4 flows, DNS queries, firewall drops
  └─ gRPC → netheos-aggregator:9090
```

## Component Detail

### netheos-operator

- Go binary built with controller-runtime
- Cluster-scoped controller for `NetheosConfig`
- Namespace-scoped controllers for `NetheosAlert`, `NetheosInsight`, `NetheosService`
- Least-privilege: only operator pod has cluster-admin-equivalent RBAC — all other pods get minimal roles

### netheos-agent

- Runs as a privileged DaemonSet (one pod per node)
- Attaches eBPF probes using CO-RE (Compile-Once Run-Everywhere)
- Streams captured flows to aggregator via gRPC
- Capabilities: `SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE`, `DAC_OVERRIDE`

### netheos-aggregator

- Receives gRPC flows from all agents
- Builds a `ClusterSnapshot` every 800ms:
  - Active pods and services from K8s API
  - Network flows grouped by namespace / service
  - Latency and retransmit metrics derived from flow data
- Proxies `/api/llm` queries to the configured LLM
- Enforces per-request RBAC via K8s `TokenReview` + `SubjectAccessReview`
- Exposes Prometheus metrics at `/metrics`

### netheos-webui

- React 18 + PatternFly 5
- Full-screen topology canvas (HTML5 Canvas, future: WebGL/Three.js)
- Real-time updates via SSE (`/ws`)
- AI chat panel (`/api/llm`)
- Served by nginx on port 8080
- nginx proxies `/api` and `/ws` to aggregator (same-origin)

## Data Flow

```
Node kernel
  ↓ eBPF hooks (kprobes / tracepoints)
netheos-agent
  ↓ gRPC (Flows proto)
netheos-aggregator
  ↓ K8s API Watch       ↓ SSE /ws        ↓ POST /api/llm
  ClusterSnapshot       Browser           Ollama / OpenAI
```

## CRD Reconciliation

```
NetheosConfig
  └─ creates/manages:
      ├── Namespace (netheos-system)
      ├── ServiceAccount (netheos-agent, netheos-aggregator)
      ├── ClusterRole / ClusterRoleBinding (agent, aggregator)
      ├── ClusterRole (netheos-viewer, netheos-editor, netheos-admin)
      ├── DaemonSet (netheos-agent)
      ├── Deployment (netheos-ollama)       ← only when provider=ollama
      ├── Service (netheos-ollama)          ← only when provider=ollama
      ├── Deployment (netheos-aggregator)
      ├── Service (netheos-aggregator)
      ├── Deployment (netheos-webui)
      └── Service (netheos-webui)

NetheosAlert      → aggregator reads CRs → evaluates metrics → sets .status.active
NetheosInsight    → aggregator reads CRs → runs cron queries → writes .status.lastResult
NetheosService    → aggregator reads CRs → tracks metrics   → writes .status.health
```

## Security Model

| Component | Privilege | Reason |
|-----------|-----------|--------|
| operator | ClusterRole (wide) | Must create cluster-scoped resources |
| agent | Privileged DaemonSet | eBPF needs kernel capabilities |
| aggregator | ClusterRole (read-only) | Reads all pods/services for topology |
| webui | No RBAC | Pure frontend — only talks to aggregator |
| ollama | No RBAC | Standalone inference server |

User authentication is fully delegated to Kubernetes:
- WebUI sends the user's bearer token to aggregator
- Aggregator calls `TokenReview` to validate
- Aggregator calls `SubjectAccessReview` per namespace to scope the response

No separate auth database or identity provider is required.

## Multi-Cluster Federation

Each remote cluster is represented by a kubeconfig stored in a K8s Secret.
The aggregator opens a watch connection to each remote API server and merges the topology into a single view.

```yaml
spec:
  multiCluster:
  - name: production
    kubeconfigSecret:
      name: prod-kubeconfig
      key: kubeconfig
    apiServer: https://prod-api.example.com:6443
```
