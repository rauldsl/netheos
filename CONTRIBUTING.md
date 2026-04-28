# Contributing to Netheos

All contributions are welcome — bug reports, feature requests, documentation improvements, and code.

## Reporting issues

Open an issue at https://github.com/rauldsl/netheos/issues with:
- Kubernetes version and distribution (kind, minikube, EKS, OpenShift…)
- Netheos version (`kubectl get netheosconfig cluster -o jsonpath='{.status}'`)
- Relevant pod logs (`kubectl logs -n netheos-system -l app=netheos-operator`)

## Pull requests

1. Fork the repo and create a branch: `git checkout -b feat/my-feature`
2. Make your changes and run `make fmt vet test`
3. Open a PR — describe what changed and why

## Local development setup

```bash
git clone https://github.com/rauldsl/netheos.git
cd netheos
./hack/dev.sh up        # build → load → deploy to kind
make port-forward       # http://localhost:8080
```

See [INSTALL.md](INSTALL.md) for full options.

## Code structure

```
api/v1alpha1/          CRD type definitions
controllers/           Reconcilers (NetheosConfig, Alert, Insight, Service)
cmd/aggregator/        Aggregator binary (K8s API + SSE + AI proxy)
cmd/agent/             eBPF agent binary
webui/src/             React frontend
bundle/                OLM bundle (CSV + CRDs)
config/                Kustomize manifests
hack/                  Dev scripts
```

## License

By contributing you agree your contributions are licensed under Apache 2.0.
