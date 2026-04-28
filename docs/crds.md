# Netheos CRD Reference

All CRDs live in the `netheos.netheos-io.io/v1alpha1` API group.

---

## NetheosConfig (cluster-scoped)

The single top-level CR that installs and configures the entire Netheos stack.
Only one instance is needed per cluster (conventionally named `cluster`).

```yaml
apiVersion: netheos.netheos-io.io/v1alpha1
kind: NetheosConfig
metadata:
  name: cluster
spec:
  # Deployment namespace (default: netheos-system)
  namespace: netheos-system

  # AI Assistant — configures the LLM backend
  aiAssistant:
    provider: ollama          # ollama | openai | anthropic | azure | vllm | custom | none
    model: "llama3.2:8b"
    gpuEnabled: false
    resources:
      cpuRequest: "500m"
      cpuLimit: "2"
      memoryRequest: "4Gi"
      memoryLimit: "8Gi"
    # For non-Ollama providers:
    apiKeySecret:
      name: openai-credentials
      key: api-key
    # Custom system prompt (optional)
    systemPrompt: |
      You are the Netheos AI Assistant for Acme Corp.

  # eBPF agent DaemonSet
  agent:
    sampleRate: 1              # 1 = capture every packet (reduce for high-traffic nodes)
    dnsTracking: true
    firewallTracking: true
    image: ""                  # override default image
    nodeSelector: {}
    tolerations: []

  # Aggregator Deployment
  aggregator:
    replicas: 1
    retentionWindow: "1h"      # in-memory flow retention
    prometheusExport: true
    image: ""

  # WebUI Deployment
  webUI:
    serviceType: ClusterIP     # ClusterIP | NodePort | LoadBalancer
    nodePort: 0                # only when serviceType=NodePort
    image: ""
    ingress:
      enabled: false
      host: netheos.example.com
      tlsSecretName: netheos-tls
      ingressClassName: nginx

  # Kubernetes-native RBAC
  rbac:
    tenantLabelKey: "netheos.netheos-io.io/tenant"
    adminGroups: ["cluster-admins"]

  # Audit logging of all user queries
  audit: true

  # Multi-cluster federation (optional)
  multiCluster:
  - name: staging
    apiServer: https://staging-api.example.com:6443
    kubeconfigSecret:
      name: staging-kubeconfig
      key: kubeconfig

status:
  phase: Running
  agentDaemonSetReady: true
  aggregatorReady: true
  webUIReady: true
  ollamaReady: true
  observedGeneration: 1
```

### Built-in ClusterRoles created by the operator

| ClusterRole | Grants |
|---|---|
| `netheos-viewer` | Read-only access to all Netheos CRDs |
| `netheos-editor` | Create/update alerts, insights, service tracking |
| `netheos-admin` | Full control including NetheosConfig |

---

## NetheosAlert (namespace-scoped)

Defines a metric threshold rule. The aggregator evaluates these continuously
and sets `.status.active` when the condition is met.

```yaml
apiVersion: netheos.netheos-io.io/v1alpha1
kind: NetheosAlert
metadata:
  name: high-latency
  namespace: production
spec:
  # Prometheus metric name to evaluate
  metric: latency_p99_ms

  # Comparison operator: Gt | Lt | Gte | Lte | Eq
  operator: Gt

  # Threshold value
  threshold: 200

  # Duration the condition must hold before firing
  for: "2m"

  # Severity: info | warning | critical
  severity: warning

  # Pod/Service label selector to scope evaluation
  selector:
    app: api-gateway

  # Namespace scope (empty = all namespaces the user can access)
  namespaces: [production]

  # Optional webhook notification
  webhook:
    url: https://hooks.slack.com/services/XXX
    secretRef:
      name: slack-webhook-secret
      key: url

status:
  active: true
  lastFiredAt: "2026-04-16T12:00:00Z"
  message: "latency_p99_ms=312 > threshold=200 for app=api-gateway"
```

---

## NetheosInsight (namespace-scoped)

Schedules a recurring natural-language query to the AI Assistant.
Results surface in the dashboard and are stored in `.status.lastResult`.

```yaml
apiVersion: netheos.netheos-io.io/v1alpha1
kind: NetheosInsight
metadata:
  name: daily-network-summary
  namespace: default
spec:
  # Natural-language question sent to the AI Assistant
  query: "Summarize the network health of the production namespace."

  # Cron schedule (standard 5-field format)
  schedule: "0 9 * * *"   # every day at 9am UTC

  # Scope the AI context to these namespaces (empty = all accessible)
  namespaces: [production, staging]

  # How long to keep the last result
  ttl: "168h"   # 7 days

  # Pause without deleting
  suspend: false

status:
  lastScheduleTime: "2026-04-16T09:00:00Z"
  nextScheduleTime: "2026-04-17T09:00:00Z"
  lastResult: |
    The production namespace shows healthy east-west traffic. p99 latency
    for api-gateway is 45ms, well below the 200ms threshold. No TCP
    retransmit spikes in the last 24 hours.
```

---

## NetheosService (namespace-scoped)

Annotates an existing Kubernetes Service with observability metadata
and custom thresholds for topology display and alerting.

```yaml
apiVersion: netheos.netheos-io.io/v1alpha1
kind: NetheosService
metadata:
  name: frontend-tracking
  namespace: default
spec:
  # Name of the Kubernetes Service to track
  serviceRef: frontend

  # Namespace where the Service lives (defaults to CR namespace)
  namespace: default

  # Label shown in the topology UI
  displayName: "Frontend Service"

  # p99 latency (ms) above which service is flagged as degraded
  latencyThresholdMs: 150

  # TCP retransmit rate (%) above which an alert fires
  retransmitThresholdPct: 5.0

  # Free-form tags shown in topology
  tags: [critical, customer-facing, sla-99.9]

status:
  health: healthy      # healthy | degraded | unknown
  latencyP99Ms: 42.3
  retransmitPct: 0.1
  lastUpdated: "2026-04-16T12:05:00Z"
```
