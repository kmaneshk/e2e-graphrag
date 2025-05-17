#!/bin/bash
# local-deployment.sh - Automated local deployment script for GraphRAG application
# This script handles:
# 1. Prompting for required secrets (OpenAI API key and Neo4j password)
# 2. Creating necessary Kubernetes secrets
# 3. Applying the local Kubernetes configuration using Kustomize

set -e  # Exit immediately if a command exits with a non-zero status

# Text formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Constants
NAMESPACE="graphrag-kotaemon-ui"
OPENAI_SECRET_NAME="openai-api-key-secret"
NEO4J_SECRET_NAME="neo4j-credentials-secret"

# Function to print formatted messages
print_message() {
    echo -e "${BOLD}${2:-$NC}$1${NC}"
}

# Function to print error messages and exit
error_exit() {
    print_message "ERROR: $1" "$RED"
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if kubectl is installed
if ! command_exists kubectl; then
    error_exit "kubectl is not installed. Please install kubectl and try again."
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info >/dev/null 2>&1; then
    error_exit "Cannot connect to Kubernetes cluster. Please check your kubeconfig and try again."
fi

print_message "Starting GraphRAG local deployment..." "$GREEN"

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    print_message "Creating namespace $NAMESPACE..." "$YELLOW"
    kubectl create namespace "$NAMESPACE" || error_exit "Failed to create namespace $NAMESPACE"
    print_message "Namespace $NAMESPACE created successfully." "$GREEN"
else
    print_message "Namespace $NAMESPACE already exists." "$YELLOW"
fi

# Function to handle secret creation
create_or_update_secret() {
    local secret_name=$1
    local secret_key=$2
    local secret_value=$3
    local description=$4

    # Check if secret already exists
    if kubectl -n "$NAMESPACE" get secret "$secret_name" >/dev/null 2>&1; then
        print_message "Secret $secret_name already exists." "$YELLOW"
        read -p "Do you want to overwrite it? (y/n): " overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            print_message "Skipping $description secret creation." "$YELLOW"
            return
        fi
        
        # Delete existing secret
        kubectl -n "$NAMESPACE" delete secret "$secret_name" >/dev/null 2>&1 || error_exit "Failed to delete existing secret $secret_name"
    fi

    print_message "Creating $description secret..." "$YELLOW"
    
    # Create secret using kubectl create secret with --dry-run and apply
    kubectl -n "$NAMESPACE" create secret generic "$secret_name" \
        --from-literal="$secret_key=$secret_value" \
        --dry-run=client -o yaml | kubectl apply -f - || error_exit "Failed to create secret $secret_name"
    
    print_message "Secret $secret_name created successfully." "$GREEN"
}

# Prompt for OpenAI API key
print_message "Prompting for OpenAI API Key..." "$YELLOW"
read -p "Enter your OpenAI API Key: " openai_api_key

if [[ -z "$openai_api_key" ]]; then
    error_exit "OpenAI API Key cannot be empty."
fi

# Create OpenAI API key secret
create_or_update_secret "$OPENAI_SECRET_NAME" "key" "$openai_api_key" "OpenAI API key"

# Prompt for Neo4j password
print_message "Prompting for Neo4j Password..." "$YELLOW"
read -p "Enter your Neo4j Password: " neo4j_password

if [[ -z "$neo4j_password" ]]; then
    error_exit "Neo4j Password cannot be empty."
fi

# Create Neo4j credentials secret
neo4j_auth="neo4j/$neo4j_password"
create_or_update_secret "$NEO4J_SECRET_NAME" "auth" "$neo4j_auth" "Neo4j credentials"

# Apply the local Kubernetes configuration using Kustomize
print_message "Applying local deployment using Kustomize..." "$YELLOW"
kubectl apply -k overlays/local || error_exit "Failed to apply Kustomize configuration"

print_message "Local deployment applied successfully!" "$GREEN"
print_message "The GraphRAG application should now be deploying to your Kubernetes cluster." "$GREEN"
print_message "\nTo access the application via your Ingress on port 3031, you'll need to port-forward" "$YELLOW"
print_message "to your Ingress controller service. Run the following in a SEPARATE terminal:" "$YELLOW"
print_message "  1. Find your Ingress controller service. Common names/namespaces:" "$NC"
print_message "     - Service: 'ingress-nginx-controller', Namespace: 'ingress-nginx'" "$NC"
print_message "     - Service: 'nginx-ingress-controller', Namespace: 'kube-system' (older setups)" "$NC"
print_message "     You can list services with: kubectl get svc --all-namespaces | grep ingress" "$NC"
print_message "  2. Port-forward. Example for 'ingress-nginx-controller' in 'ingress-nginx' namespace:" "$NC"
print_message "     ${BOLD}kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 3031:80 &${NC}" "$YELLOW"
print_message "     (Adjust namespace and service name if different. The '&' runs it in the background.)" "$NC"

print_message "\nOnce port-forwarding to the Ingress controller is active, you can access:" "$GREEN"
print_message "- RAG UI at: http://localhost:3031/rag-ui" "$GREEN"
print_message "- GraphRAG server at: http://localhost:3031/graphrag" "$GREEN"

# Print command to check deployment status
print_message "\nTo check the status of your application pods, run:" "$YELLOW"
echo "kubectl -n $NAMESPACE get pods"

# Print command to port-forward services directly (alternative to Ingress)
print_message "\nAlternatively, to access services directly (bypassing Ingress), run in separate terminals:" "$YELLOW"
echo "kubectl -n $NAMESPACE port-forward svc/kotaemon-ui 7860:80 &  # Access RAG UI at http://localhost:7860"
echo "kubectl -n $NAMESPACE port-forward svc/graphrag-server 20213:20213 & # Access GraphRAG at http://localhost:20213"

print_message "\nDeployment complete!" "$GREEN"