# GraphRAG and Kotaemon Kubernetes Deployment using Kustomize

A lightweight implementation for spinning up the **Kotaemon UI** front-end with the **GraphRAG** back-end (and Neo4j) in the same Kubernetes namespace using Kustomize.

---

## Overview

This guide provides instructions to deploy:
*   **Kotaemon UI:** The user interface for interacting with the RAG system.
*   **GraphRAG API:** The backend service providing RAG functionalities.
*   **Neo4j:** The graph database used by GraphRAG.

The deployment is managed using Kustomize, with overlays for different environments (e.g., local development, production).

---

## Directory Structure

```text
kotaemon-graphrag/
├── base/                           # Common Kubernetes resources
│   ├── kustomization.yaml
│   ├── kotaemon-deploy.yaml
│   ├── kotaemon-svc.yaml
│   ├── graphrag-deploy.yaml
│   ├── graphrag-svc.yaml
│   └── neo4j.yaml
├── overlays/
│   ├── local/                      # Configuration for local development
│   │   ├── kustomization.yaml
│   │   └── ingress.yaml
│   └── production/                 # Configuration for production
│       ├── kustomization.yaml
│       └── ingress.yaml
├── local-deployment.sh             # Script for easy local setup
└── (optional) step-ca/             # For internal CA, remove if using public ACME CA
```

---

## Prerequisites

Ensure you have the following tools installed and configured:

| Tool           | Minimum Version  | Notes                               |
|----------------|------------------|-------------------------------------|
| Kubernetes     | 1.25             | Tested on 1.28                      |
| `kubectl`      | Matching cluster |                                     |
| `kustomize`    | 5.x              | Built-in to `kubectl` ≥ 1.14        |
| `cert-manager` | ≥ 1.14           | Deployed cluster-wide (for HTTPS)   |
| (optional) `step-ca` | 0.27         | Alternative for internal CA         |

---

## Configuration: Secrets

You **must** create the following Kubernetes Secrets in the `graphrag-kotaemon-ui` namespace before deployment.

### 1. OpenAI API Key Secret

This secret provides API keys for both Kotaemon UI and GraphRAG.

*   **Secret Name:** `openai-api-key-secret`
*   **Key in Secret:** `key`
*   **Value:** Your OpenAI API key.

This single key value will be used for:
*   `OPENAI_API_KEY`: For Kotaemon UI (direct LLM calls, optional).
*   `GRAPHRAG_API_KEY`: For GraphRAG (mandatory authentication token).
*   GraphRAG can also use this secret for other `GRAPHRAG_*` environment variables like `GRAPHRAG_EMBEDDING_MODEL` to override defaults if you add them to the secret.

**Create the secret:**
```bash
kubectl -n graphrag-kotaemon-ui create secret generic openai-api-key-secret \
  --from-literal=key='YOUR_OPENAI_API_KEY_VALUE'
```

### 2. Neo4j Credentials Secret

This secret provides the authentication string for the Neo4j database.

*   **Secret Name:** `neo4j-credentials-secret`
*   **Key in Secret:** `auth`
*   **Value:** Neo4j authentication string in the format `neo4j/YOUR_NEO4J_PASSWORD`.

**Create the secret:**
```bash
kubectl -n graphrag-kotaemon-ui create secret generic neo4j-credentials-secret \
  --from-literal=auth='neo4j/YOUR_NEO4J_PASSWORD'
```
**Note:** The `local-deployment.sh` script can help automate the creation of these secrets.

---

## Deployment

### Local Development Deployment

This is the recommended way to get started quickly. The `local` overlay configures Ingress for services to be accessible via `localhost` using path-based routing and plain HTTP.

#### Option 1: Using the `local-deployment.sh` Script (Recommended One-Click)

The `local-deployment.sh` script automates the entire local deployment process.

1.  **Make the script executable:**
    ```bash
    chmod +x local-deployment.sh
    ```

2.  **Run the script:**
    ```bash
    ./local-deployment.sh
    ```

3.  **What the script does:**
    *   Prompts for required secrets (OpenAI API key and Neo4j password).
    *   Creates the necessary Kubernetes secrets automatically.
    *   Applies the local Kubernetes configuration using `kustomize build overlays/local | kubectl apply -f -`.
    *   Provides access URLs (e.g., `http://localhost:3031/rag-ui`, `http://localhost:3031/graphrag`) and guides on port-forwarding to your Ingress controller.

4.  **Prerequisites for the script:**
    *   `kubectl` installed and configured to point to a Kubernetes cluster.
    *   Access to a Kubernetes cluster (local or remote).

#### Option 2: Manual Deployment Steps

If you prefer to deploy manually or understand the steps involved:

1.  **Ensure secrets are created** (as described in the "Configuration: Secrets" section).
2.  **Deploy using the local overlay:**
    ```bash
    kustomize build overlays/local | kubectl apply -f -
    ```
    This command builds the Kubernetes manifests using the `local` overlay and applies them to your cluster.

#### Option 3: Running the Deployment Script from GitHub URL

You can run the `local-deployment.sh` script directly from GitHub without cloning the repository:

```bash
bash <(curl -s https://raw.githubusercontent.com/microsoft/graphrag/main/k8s/kotaemon-graphrag/local-deployment.sh)
```
*(Note: Ensure the URL points to the correct script location if it differs.)*

### Production Deployment

The `overlays/production` directory contains a sample Kustomize configuration for a production-like environment. This typically includes:
*   Proper Ingress configuration with TLS (HTTPS).
*   Host-based routing.
*   References to `cert-manager` for certificate issuance.

To deploy to production (after customizing `overlays/production/kustomization.yaml` and `overlays/production/ingress.yaml` for your domain and TLS setup):
```bash
kustomize build overlays/production | kubectl apply -f -
```

---

## Accessing the Services

### Accessing via Ingress (Local Development)

When using the `local` overlay (either via the script or manual deployment), services are exposed via an Ingress controller.

1.  **Port-forward to your Ingress controller:**
    You need to forward a local port (e.g., 3031) to your Ingress controller's HTTP service (usually port 80) in Kubernetes. The exact command depends on your Ingress controller's namespace and service name.
    Example:
    ```bash
    # Replace <ingress-namespace> and <ingress-service-name> with your Ingress controller's details
    kubectl -n <ingress-namespace> port-forward svc/<ingress-service-name> 3031:80
    ```
    The `local-deployment.sh` script provides guidance on this step.

2.  **Access the services:**
    *   **Kotaemon UI:** `http://localhost:3031/rag-ui`
    *   **GraphRAG API:** `http://localhost:3031/graphrag`

### Accessing via Direct Port-Forwarding (Alternative/Debugging)

For debugging or if you prefer to bypass Ingress for a specific service, you can port-forward directly to the service pods.

*   **Kotaemon UI:**
    ```bash
    kubectl -n graphrag-kotaemon-ui port-forward svc/kotaemon-ui 7860:80 &
    # Access at: http://localhost:7860
    curl -I http://localhost:7860
    ```

*   **GraphRAG API:**
    ```bash
    kubectl -n graphrag-kotaemon-ui port-forward svc/graphrag-server 20213:20213 &
    # Access at: http://localhost:20213
    curl -s http://localhost:20213/healthz   # Expect HTTP 200 or 401
    ```

*   **Neo4j:**
    ```bash
    kubectl -n graphrag-kotaemon-ui port-forward svc/neo4j 7474:7474 7687:7687 &
    # Access Neo4j Browser at: http://localhost:7474
    # Bolt endpoint: neo4j://localhost:7687
    ```

---

## Post-Deployment Steps

### Indexing Your Corpus with GraphRAG

After GraphRAG is running, you need to initialize it and index your data.

1.  **Access the GraphRAG pod:**
    ```bash
    kubectl -n graphrag-kotaemon-ui exec -it $(kubectl -n graphrag-kotaemon-ui get pod -l app=graphrag-server -o jsonpath='{.items[0].metadata.name}') -- bash
    ```

2.  **Inside the GraphRAG pod:**
    *   Initialize GraphRAG (if not already done, and assuming `/workspace` is your data directory):
        ```bash
        graphrag init --root /workspace
        ```
    *   Ensure your `GRAPHRAG_API_KEY` is available to the indexing process. If you set it in the `openai-api-key-secret` and referenced it in the deployment, it should be available as an environment variable. If not, you might need to set it in `/workspace/.env`:
        ```bash
        # Example: echo "GRAPHRAG_API_KEY=YOUR_API_KEY_VALUE" >> /workspace/.env
        # Or, ensure the secret is correctly mounted and used by the GraphRAG deployment for the indexing process.
        ```
    *   Run the indexing process:
        ```bash
        graphrag index --root /workspace --verbose
        ```

**Note:** For persistent storage of indexed data and configurations, ensure the `/workspace` directory in the GraphRAG pod is backed by a PersistentVolumeClaim (PVC). See the "Neo4j Persistence" section for an example of PVC configuration, which can be adapted for GraphRAG's workspace.

---

## Advanced Configuration

### Neo4j Persistence

By default, Neo4j uses an `emptyDir` volume, meaning data is lost when the pod restarts. For persistent storage, modify `base/neo4j.yaml` to use a PersistentVolumeClaim (PVC).

Replace the `emptyDir` volume for `data` with a `volumeClaimTemplates` in the StatefulSet spec:

```yaml
# In base/neo4j.yaml, within the StatefulSet spec for Neo4j:
# ...
# spec:
#   serviceName: "neo4j"
#   replicas: 1
#   selector:
#     matchLabels:
#       app: neo4j
#   template:
#     # ...
#   volumeClaimTemplates:
#   - metadata:
#       name: data
#     spec:
#       accessModes: ["ReadWriteOnce"]
#       storageClassName: "your-storage-class" # Optional: specify if needed
#       resources:
#         requests:
#           storage: 10Gi
# ...
```
And ensure the volumeMount for `/data` uses this PVC.

### Optional Internal CA (step-ca)

If you prefer an internal Public Key Infrastructure (PKI) instead of a public CA like Let's Encrypt, you can use `step-ca`.

1.  Keep the `step-ca/` folder in your project.
2.  Generate root and provisioner keys. Load them into Kubernetes secrets:
    *   `step-ca-certs` (Secret)
    *   `step-ca-pass` (Secret)
3.  Set the `PROVISIONER_KID` environment variable in `step-ca/issuer.yaml`.
4.  Uncomment the `../../step-ca` line in your overlay's `kustomization.yaml` (e.g., `overlays/production/kustomization.yaml`) to include the step-ca resources.

---

## Best Practices & Security (House-keeping & Hardening)

Consider implementing the following for a more robust and secure deployment:

*   **`securityContext`:**
    *   Run containers as non-root users (`runAsNonRoot: true`).
    *   Use a read-only root filesystem (`readOnlyRootFilesystem: true`) where possible.
    *   Drop unnecessary capabilities (e.g., `CAP_NET_RAW`).
*   **`NetworkPolicy`:** Implement network policies to restrict traffic flow, e.g., allow only Kotaemon UI → GraphRAG API → Neo4j.
*   **Autoscaling:** Configure Horizontal Pod Autoscaler (`HPA`) or KEDA for handling load spikes.
*   **`PodDisruptionBudget`:** Define PDBs to ensure service availability during voluntary disruptions (e.g., node drains).
*   **Resource Requests and Limits:** Set appropriate CPU and memory requests and limits for all deployments.
*   **Regular Updates:** Keep container images and all dependencies updated.

---

## Teardown

To remove all resources deployed in the `graphrag-kotaemon-ui` namespace:

```bash
kubectl delete ns graphrag-kotaemon-ui
```

If you created PersistentVolumeClaims (PVCs) and PersistentVolumes (PVs) that are not automatically cleaned up by the namespace deletion (depending on their reclaim policy), you might need to delete them manually.
```bash
# Example: List PVCs in the namespace (before deleting it)
# kubectl -n graphrag-kotaemon-ui get pvc

# Example: Delete a specific PVC
# kubectl -n graphrag-kotaemon-ui delete pvc <pvc-name>
```

---
