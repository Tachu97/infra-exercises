# Exercise 3 — hello-world REST service on minikube

A pre-built Go REST application served locally via a minikube Kubernetes cluster.  
After deployment the service is accessible at **`http://localhost:8080/hello-world`**.

## Prerequisites

The `deploy.sh` script checks for and **auto-installs** the following tools if they are missing:

| Tool | Purpose |
|------|---------|
| [Docker](https://www.docker.com/products/docker-desktop/) | Container runtime & image build |
| [minikube](https://minikube.sigs.k8s.io/) | Local Kubernetes cluster |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Kubernetes CLI |

> **macOS**: tools are installed via Homebrew (which is itself installed if absent).  
> **Linux**: tools are installed via `apt` / direct binary download.  
> **Docker Desktop** on macOS must be started manually before running the script.

---

## Quick start

```bash
# Clone / enter the repo
cd exercise3-k8s

# Make the script executable (first time only)
chmod +x deploy.sh

# Deploy everything
./deploy.sh
```

The script will:

1. Verify (and install) Docker, minikube, and kubectl  
2. Start a minikube cluster (`--driver=docker`)  
3. Build the Docker image **inside minikube's local Docker daemon** — no remote registry needed  
4. Apply the Kubernetes manifests (Namespace → Deployment → Service)  
5. Wait for the rollout to complete  
6. Start a `kubectl port-forward` so the service is reachable on `localhost:8080`  
7. Run a smoke-test and print the result  

Expected output after a successful deploy:

```
  Endpoint:  http://localhost:8080/hello-world
  Response:  {"message":"Hello World!"}
```

---

## Verify manually

```bash
curl http://localhost:8080/hello-world
# {"message":"Hello World!"}
```

---

## Other commands

```bash
# Check pod / service status
./deploy.sh --status

# Remove the deployment and stop the port-forward
./deploy.sh --clean
```

---

## Architecture

```
localhost:8080
     │
     │  kubectl port-forward
     ▼
 Service/hello-world (ClusterIP :8080)   ← namespace: hello-world
     │
     ├── Pod: hello-world-xxx-yyy  (replica 1)
     └── Pod: hello-world-xxx-zzz  (replica 2)
```

### Why minikube's local Docker daemon?

Running `eval $(minikube docker-env)` before `docker build` points the Docker CLI at minikube's **internal** Docker daemon. The image therefore lives inside the cluster without ever being pushed to a remote registry. The Deployment manifests use `imagePullPolicy: Never` to confirm this intent.

This approach:
- ✅ Zero cost (no registry fees or data transfer)
- ✅ No credentials required
- ✅ Fast iteration — rebuild and redeploy without a push/pull round-trip

---

## Project layout

```
exercise3-k8s/
├── app/
│   └── rest_1.0_linux_amd64   # Pre-built Go binary (linux/amd64)
├── k8s/
│   ├── namespace.yaml         # Isolated namespace
│   ├── deployment.yaml        # 2-replica Deployment with probes & resource limits
│   └── service.yaml           # ClusterIP Service
├── Dockerfile                 # Packages the binary into a debian-slim image
├── deploy.sh                  # One-shot automation script
└── README.md                  # This file
```
