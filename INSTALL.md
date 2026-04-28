# Netheos — Installation Guide

> **Container runtime:** Podman
> **WebUI access:** http://localhost:8080
>
> **Cluster name:** The examples below use `netheos-dev` as the kind cluster name.
> Replace it with your own name by setting `CLUSTER_NAME=<your-cluster>` or passing it as an argument.

---

## Prerequisites

| Tool | Min Version | Install |
|------|-------------|---------|
| Go | 1.22 | https://go.dev/dl |
| Podman | 4.x | https://podman.io |
| kind | 0.22+ | `brew install kind` |
| kubectl | 1.27+ | `brew install kubectl` |
| kustomize | 5.x | `brew install kustomize` |
| podman-compose | 1.x | `pip3 install podman-compose` |
| Node.js | 20+ | https://nodejs.org (for WebUI dev only) |

---

## Option 1 — One-command local deploy (kind cluster)

This is the **recommended path** for local development.
It builds all images, loads them into your kind cluster, and deploys the operator.

```bash
# Clone the repo
git clone https://github.com/netheos-io/netheos.git
cd netheos-v2

# Full deploy: build → load → deploy
./hack/dev.sh up

# In a separate terminal — open the UI
make port-forward
# → http://localhost:8080
```

Then apply the `NetheosConfig` CR to install the full stack:

```bash
kubectl apply -f config/samples/netheos_v1alpha1_netheosconfig.yaml
```

---

## Option 2 — Step by step

### Step 1 — Create the kind cluster (if not already running)

```bash
# Replace netheos-dev with your preferred cluster name
kind create cluster --name netheos-dev
```

### Step 2 — Build images with Podman

```bash
make podman-build
```

### Step 3 — Load images into the kind cluster

```bash
# Uses CLUSTER_NAME (default: netheos-dev) — override with: make kind-load CLUSTER_NAME=<your-cluster>
make kind-load
```

### Step 4 — Deploy the operator

```bash
make deploy
```

This applies:
- CRDs (`config/crd/`)
- RBAC (`config/rbac/`)
- Operator deployment (`config/manager/`)

### Step 5 — Install the Netheos stack (via CR)

```bash
kubectl apply -f config/samples/netheos_v1alpha1_netheosconfig.yaml
```

Wait for all pods to be ready:

```bash
kubectl get pods -n netheos-system -w
```

Expected pods:

```
netheos-operator      1/1  Running
netheos-aggregator    1/1  Running
netheos-agent-xxxxx   1/1  Running  (one per node)
netheos-webui         1/1  Running
netheos-ollama        1/1  Running  (if provider=ollama)
```

### Step 6 — Access the UI

```bash
make port-forward
```

Open: **http://localhost:8080**

---

## Option 3 — Local dev without Kubernetes (podman-compose)

Runs only the aggregator + WebUI locally (no eBPF, mock data):

```bash
podman-compose up --build
```

Open: **http://localhost:8080**

To include Ollama:

```bash
podman-compose --profile ollama up --build
```

---

## Option 4 — Helm (production clusters)

```bash
helm repo add netheos https://netheos-io.github.io/netheos
helm repo update

helm install netheos netheos/netheos \
  --namespace netheos-system \
  --create-namespace \
  --set netheosConfig.aiAssistant.provider=ollama \
  --set netheosConfig.aiAssistant.model=llama3.2:8b
```

---

## Option 5 — OLM / OperatorHub

```bash
# Install via OLM subscription
kubectl apply -f deploy/olm/subscription.yaml

# Create the NetheosConfig CR
kubectl apply -f config/samples/netheos_v1alpha1_netheosconfig.yaml
```

---

## AI Assistant configuration

### Bundled Ollama (default — no config needed)

```yaml
spec:
  aiAssistant:
    provider: ollama
    model: "llama3.2:8b"
```

### External providers

```yaml
# OpenAI
spec:
  aiAssistant:
    provider: openai
    model: gpt-4o
    apiKeySecret:
      name: openai-credentials
      key: api-key
```

```yaml
# Anthropic
spec:
  aiAssistant:
    provider: anthropic
    model: claude-sonnet-4-6
    apiKeySecret:
      name: anthropic-credentials
      key: api-key
```

```yaml
# Disable AI entirely
spec:
  aiAssistant:
    provider: none
```

---

## Makefile reference

```
make podman-build   Build all 4 images with podman
make kind-load      Build + load images into kind cluster (CLUSTER_NAME, default: netheos-dev)
make deploy         Apply CRDs + RBAC + operator to current cluster
make deploy-sample  Apply the default NetheosConfig CR
make full-deploy    Build → load → deploy → apply CR (complete)
make port-forward   Forward netheos-webui → http://localhost:8080
make undeploy       Remove operator + CRDs from cluster
make test           Run go tests
make bundle         Generate OLM bundle
```

---

## hack/dev.sh reference

```
./hack/dev.sh up            Full workflow: build → load → deploy
./hack/dev.sh down          Remove Netheos from the cluster
./hack/dev.sh build         Build all images with podman
./hack/dev.sh load          Load images into kind cluster (CLUSTER_NAME)
./hack/dev.sh deploy        Apply kustomize manifests + NetheosConfig CR
./hack/dev.sh port-forward  Forward WebUI → http://localhost:8080
./hack/dev.sh logs [svc]    Tail logs (operator|aggregator|webui|agent)
./hack/dev.sh status        Show pods, services, NetheosConfig status
./hack/dev.sh reset         Full teardown + rebuild + redeploy
./hack/dev.sh compose-up    Start local stack with podman-compose
./hack/dev.sh compose-down  Stop podman-compose stack
```

---

## Verifying the install

```bash
# Check operator is running
kubectl get pods -n netheos-system

# Check NetheosConfig status
kubectl get netheosconfig cluster -o yaml

# Check alert rules
kubectl get netheosalerts -A

# Check insights
kubectl get netheosinsights -A

# Check service tracking
kubectl get netheosservices -A
```

---

## Uninstall

```bash
# Remove the CR (triggers stack cleanup)
kubectl delete netheosconfig cluster

# Remove the operator and CRDs
make undeploy

# Or via dev script
./hack/dev.sh down
```

---

## Troubleshooting

### Images not found in cluster

```bash
# Verify images are present in kind node (replace netheos-dev with your cluster name)
docker exec netheos-dev-control-plane crictl images | grep netheos
```

### Operator pod in CrashLoopBackOff

```bash
kubectl logs -n netheos-system -l app=netheos-operator --previous
```

### WebUI unreachable at localhost:8080

```bash
# Check port-forward is running
kubectl get svc -n netheos-system
# Check WebUI pod is ready
kubectl get pods -n netheos-system -l app=netheos-webui
```

### Ollama pull stuck

Ollama pulls the model on first start (~4 GB for llama3.2:8b). Monitor progress:

```bash
kubectl logs -n netheos-system -l app=netheos-ollama -f
```

To skip Ollama, change the provider:

```yaml
spec:
  aiAssistant:
    provider: none
```

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
