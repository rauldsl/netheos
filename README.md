<p align="center">
  <img src="https://raw.githubusercontent.com/rauldsl/netheos/main/docs/screenshots/netheos-logo.png" alt="Netheos" width="160"/>
</p>

# Netheos

**Real-time Kubernetes observability with eBPF network capture, interactive topology UI, and an embedded AI Assistant — running entirely inside your cluster.**

[![OLM](https://img.shields.io/badge/OLM-v0.1.0-blue)](https://operatorhub.io/operator/netheos)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/netheos)](https://artifacthub.io/packages/helm/netheos/netheos)
[![License](https://img.shields.io/badge/license-Apache%202.0-green)](https://github.com/rauldsl/netheos/blob/main/LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.27%2B-326CE5)](https://kubernetes.io)

---

## Helm Repository

```bash
helm repo add netheos https://rauldsl.github.io/netheos
helm repo update
helm install netheos netheos/netheos -n netheos-system --create-namespace
```

| Chart | Version | App Version |
|-------|---------|-------------|
| netheos | 0.1.0 | 0.1.0 |

---

## Screenshots

| Dashboard | Container Topology |
|---|---|
| ![Dashboard](https://raw.githubusercontent.com/rauldsl/netheos/main/docs/screenshots/netheos-mock-main-dashboard.png) | ![Topology](https://raw.githubusercontent.com/rauldsl/netheos/main/docs/screenshots/netheos-container-topology.png) |

| Infrastructure Topology | AI Assistant |
|---|---|
| ![Infra](https://raw.githubusercontent.com/rauldsl/netheos/main/docs/screenshots/netheos-infra-topology.png) | ![AI](https://raw.githubusercontent.com/rauldsl/netheos/main/docs/screenshots/netheos-ai-chat.png) |

| Load Balancers | Firewall |
|---|---|
| ![LB](https://raw.githubusercontent.com/rauldsl/netheos/main/docs/screenshots/netheos-loadbalancer-topology.png) | ![Firewall](https://raw.githubusercontent.com/rauldsl/netheos/main/docs/screenshots/netheos-firewall-view.png) |

---

## Features

- **eBPF-based capture** — Zero-instrumentation packet capture at kernel level, no code changes required
- **In-cluster AI Assistant** — Llama 3.2 8B via Ollama, or plug in OpenAI / Anthropic / Azure
- **Interactive topology** — Live namespace/pod/service graph with animated flow edges
- **Infrastructure view** — K8s nodes, CNI plugin, pod CIDRs, cross-namespace flows
- **Firewall monitoring** — iptables/nftables drops captured in real time
- **Alert rules** — `NetheosAlert` CRD for metric threshold rules with webhook support
- **Scheduled insights** — `NetheosInsight` CRD for cron-based AI queries
- **Multi-cluster federation** — Federate multiple clusters into a single dashboard
- **Prometheus integration** — ServiceMonitor included out of the box
- **Privacy first** — All data and AI inference run entirely inside your cluster

---

## Quick Start (Helm)

```bash
helm repo add netheos https://rauldsl.github.io/netheos
helm repo update
helm install netheos netheos/netheos -n netheos-system --create-namespace
```

Access the UI:

```bash
kubectl port-forward -n netheos-system svc/netheos-webui 8080:8080
# → http://localhost:8080
```

**Custom values** (AI provider, service type, etc.):

```bash
helm install netheos netheos/netheos \
  -n netheos-system --create-namespace \
  --set netheos.aiAssistant.provider=openai \
  --set netheos.aiAssistant.model=gpt-4o \
  --set netheos.aiAssistant.apiKeySecret.name=openai-credentials \
  --set netheos.aiAssistant.apiKeySecret.key=api-key \
  --set netheos.webUI.serviceType=LoadBalancer
```

---

## Quick Start (OLM / OperatorHub)

```bash
# 1. Install via OLM subscription
kubectl apply -f https://raw.githubusercontent.com/rauldsl/netheos/main/deploy/olm/subscription.yaml

# 2. Deploy the full stack with one CR
kubectl apply -f - <<EOF
apiVersion: netheos.netheos-io.io/v1alpha1
kind: NetheosConfig
metadata:
  name: cluster
spec:
  aiAssistant:
    provider: ollama
    model: "llama3.2:8b"
  webUI:
    serviceType: ClusterIP
EOF

# 3. Wait for all pods
kubectl get pods -n netheos-system -w

# 4. Open the UI
kubectl port-forward -n netheos-system svc/netheos-webui 8080:8080
# → http://localhost:8080
```

---

## CRDs

| CRD | Scope | Description |
|-----|-------|-------------|
| `NetheosConfig` | Cluster | Top-level CR — installs the full Netheos stack |
| `NetheosAlert` | Namespace | Metric threshold alert rule |
| `NetheosInsight` | Namespace | Scheduled natural-language AI query |
| `NetheosService` | Namespace | Service-level observability and custom thresholds |

---

## Architecture

```
Browser
  │  SSE /ws  →  netheos-webui (nginx:8080)
  │               └─ proxy → netheos-aggregator:9091
  │  AI chat  →  netheos-aggregator /api/llm → Ollama / OpenAI
  │
netheos-aggregator (Deployment)
  │  ClusterSnapshot every 800ms from K8s API + eBPF flows
  │  Exposes /metrics for Prometheus
  │
netheos-agent (DaemonSet — every node)
  │  eBPF probes: L3/L4 flows, DNS, firewall drops
  └─ gRPC → netheos-aggregator:9090
  │
netheos-operator (Deployment)
  └─ Reconciles NetheosConfig → deploys all of the above
```

---

## AI Assistant configuration

```yaml
# Bundled Ollama (default)
aiAssistant:
  provider: ollama
  model: "llama3.2:8b"

# OpenAI
aiAssistant:
  provider: openai
  model: gpt-4o
  apiKeySecret:
    name: openai-credentials
    key: api-key

# Anthropic
aiAssistant:
  provider: anthropic
  model: claude-sonnet-4-6
  apiKeySecret:
    name: anthropic-credentials
    key: api-key

# Disable AI
aiAssistant:
  provider: none
```

---

## Requirements

| Component | Minimum |
|-----------|---------|
| Kubernetes | 1.27+ |
| Helm | 3.10+ |
| CPU (operator) | 100m |
| Memory (operator) | 128Mi |
| CPU (Ollama, optional) | 2 cores |
| Memory (Ollama, optional) | 8Gi |

---

## Links

- [GitHub](https://github.com/rauldsl/netheos)
- [OperatorHub](https://operatorhub.io/operator/netheos)
- [Artifact Hub](https://artifacthub.io/packages/helm/netheos/netheos)
- [Contributing](https://github.com/rauldsl/netheos/blob/main/CONTRIBUTING.md)
- [License — Apache 2.0](https://github.com/rauldsl/netheos/blob/main/LICENSE)
