# Kotaemon + GraphRAG Kubernetes Deployment (Kustomize)

A lightweight reference for spinning up the **Kotaemon UI** front‑end with the **GraphRAG** back‑end (and Neo4j) in the same Kubernetes namespace using Kustomize.  

---

## Directory layout

```text
kotaemon-graphrag/
├── base/
│   ├── kustomization.yaml
│   ├── kotaemon-deploy.yaml
│   ├── kotaemon-svc.yaml
│   ├── graphrag-deploy.yaml
│   ├── graphrag-svc.yaml
│   └── neo4j.yaml
├── overlays/
│   └── production/
│       ├── kustomization.yaml
│       └── ingress.yaml
└── (optional) step-ca/         # remove if you use a public ACME CA
```

---

## 1  Prerequisites

| Tool | Minimum version | Notes |
|------|-----------------|-------|
| Kubernetes | 1.25 | Tested on 1.28 |
| kubectl | matching cluster | |
| kustomize | 5.x | Built‑in to Roo Code tasks |
| cert‑manager | ≥ 1.14 | Deployed cluster‑wide |
| (optional) step‑ca | 0.27 | Internal CA alternative |

---

## 2  Secrets & config you **must** supply

| Secret (`openai-api-key-secret` with key `key`) provides: | Used by     | Purpose                        |
|-----------------------------------------------------------|-------------|--------------------------------|
| `OPENAI_API_KEY`                                          | Kotaemon UI | Direct LLM calls (optional)    |
| `GRAPHRAG_API_KEY`                                        | GraphRAG    | Mandatory authentication token |
| Extra knobs (`GRAPHRAG_EMBEDDING_MODEL`, etc.)            | GraphRAG    | Override defaults              |

| Secret (`neo4j-credentials-secret` with key `auth`) provides: | Used by  | Purpose  |
|-------------------------------------------------------------|----------|----------|
| Neo4j auth string (`neo4j/your-password`)                   | Neo4j SS | DB login |

Create them with:

```bash
kubectl -n graphrag-kotaemon-ui create secret generic openai-api-key-secret --from-literal=key='<your-openai-api-key-value>'

kubectl -n graphrag-kotaemon-ui create secret generic neo4j-credentials-secret --from-literal=auth='neo4j/<your-neo4j-password>'
```

The `openai-api-key-secret` provides the necessary API key for both `OPENAI_API_KEY` (used by Kotaemon UI) and `GRAPHRAG_API_KEY` (used by GraphRAG).

The `neo4j-credentials-secret` provides the authentication string for Neo4j, which must have the format `neo4j/password` with the `neo4j/` prefix.

Patch the relevant Deployments to reference the secrets.

---

## 3  Local Deployment

### 3.1  Manual Deployment

For local development, a `local` overlay is provided. This overlay configures Ingress for the services to be accessible via `localhost` (e.g., on port 3031 after port-forwarding to your Ingress controller) using path-based routing and plain HTTP.

```bash
# Deploy using the local overlay
kustomize build overlays/local | kubectl apply -f -
```

This sets up Ingress rules for:
- RAG UI at path: `/rag-ui`
- GraphRAG server at path: `/graphrag`

To access these, you'll typically port-forward a local port (e.g., 3031) to your Ingress controller's HTTP service (port 80) in Kubernetes.
Example: `kubectl -n <ingress-namespace> port-forward svc/<ingress-service-name> 3031:80`
Once forwarded, access them at `http://localhost:3031/rag-ui` and `http://localhost:3031/graphrag`.

The local overlay uses the same base resources but with simplified Ingress configuration:
- No TLS certificates (plain HTTP)
- Path-based routing on `localhost` (requires port-forwarding to your Ingress controller)
- Same service configuration as production

### 3.2  One-Click Local Deployment

For a simplified deployment experience, you can use the provided `local-deployment.sh` script which automates the entire local deployment process:

1. **Make the script executable:**
   ```bash
   chmod +x local-deployment.sh
   ```

2. **Run the script:**
   ```bash
   ./local-deployment.sh
   ```

3. **What the script does:**
   - Prompts for required secrets (OpenAI API key and Neo4j password)
   - Creates necessary Kubernetes secrets automatically
   - Applies the local Kubernetes configuration using Kustomize
   - Provides updated access URLs (e.g., `http://localhost:3031/rag-ui`, `http://localhost:3031/graphrag`) and guides on port-forwarding to your Ingress controller to enable access on a custom port like 3031.

4. **Prerequisites:**
   - `kubectl` installed and configured to point to a Kubernetes cluster
   - Access to a Kubernetes cluster (local or remote)

### 3.3  Running from GitHub URL

You can also run the script directly from GitHub without cloning the repository:

```bash
bash <(curl -s https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPOSITORY/main/local-deployment.sh)
```

This command downloads the script from the GitHub repository and executes it immediately. Replace `YOUR_USERNAME`, `YOUR_REPOSITORY`, and `main` with your actual GitHub username, repository name, and branch name.

---

## 4  Optional internal CA (step‑ca)

If you prefer an internal PKI, keep the `step-ca/` folder and:

1. Generate root & provisioner keys, load them into:
   * `step-ca-certs` (secret)
   * `step-ca-pass` (secret)
2. Set `PROVISIONER_KID` in `step-ca/issuer.yaml`.
3. _Uncomment_ the `../../step-ca` line in the overlay.

---

## 6  Access UI

**Note:** The primary way to access services for local development (when using the `local` overlay and `local-deployment.sh` script) is via the Ingress controller, typically at `http://localhost:3031` (e.g., `http://localhost:3031/rag-ui` and `http://localhost:3031/graphrag`) after you've set up port-forwarding from your local machine (e.g., port 3031) to the Ingress controller service in Kubernetes (port 80). The `local-deployment.sh` script provides guidance on this.

The commands below demonstrate direct port-forwarding to individual services, which bypasses the Ingress. This can be useful for debugging or if you prefer not to use Ingress for a specific service.

```bash
# UI
kubectl -n graphrag-kotaemon-ui port-forward svc/kotaemon-ui 7860:80 &
curl -I http://localhost:7860

# RAG
kubectl -n graphrag-kotaemon-ui port-forward svc/graphrag-server 20213:20213 &
curl -s http://localhost:20213/healthz   # expect 200 or 401
```

---

## 7  Indexing your corpus

```bash
# inside the graphrag pod
graphrag init --root /workspace
vim /workspace/.env         # add GRAPHRAG_API_KEY
graphrag index --root /workspace
```

Mount a PVC at `/workspace` for persistent storage.

---

## 8  Neo4j persistence

Swap the `emptyDir` in `base/neo4j.yaml` for:

```yaml
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 10Gi
```

---

## 9  House‑keeping & hardening

* `securityContext`: `runAsNonRoot`, `readOnlyRootFilesystem`, drop `CAP_NET_RAW`.
* `NetworkPolicy`: allow only UI → GraphRAG → Neo4j.
* `HPA` or `KEDA` for load spikes.
* `PodDisruptionBudget` to survive node drains.

---

### One‑liner teardown

```bash
kubectl delete ns graphrag-kotaemon-ui
```

---
