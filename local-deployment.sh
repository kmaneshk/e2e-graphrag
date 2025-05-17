#!/bin/bash
# local-deployment.sh - Automated local deployment script for GraphRAG application
# This script handles:
# 1. Prompting for deployment method (Kubernetes or Docker Compose)
# 2. For Kubernetes:
#    a. Prompting for required secrets (OpenAI API key and Neo4j password)
#    b. Creating necessary Kubernetes secrets
#    c. Applying the local Kubernetes configuration using Kustomize
# 3. For Docker Compose:
#    a. Starting services using docker-compose

set -e  # Exit immediately if a command exits with a non-zero status

# Text formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Constants (some are Kubernetes-specific)
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

# Function to handle secret creation (Kubernetes specific)
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

print_message "Starting GraphRAG local deployment..." "$GREEN"

print_message "Choose your deployment method:" "$YELLOW"
echo "1. Kubernetes"
echo "2. Docker Compose"
read -p "Enter your choice (1 or 2): " deployment_choice

if [[ "$deployment_choice" == "1" ]]; then
    print_message "Proceeding with Kubernetes deployment..." "$GREEN"

    # Check if kubectl is installed
    if ! command_exists kubectl; then
        error_exit "kubectl is not installed. Please install kubectl and try again."
    fi

    # Check if Kubernetes cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error_exit "Cannot connect to Kubernetes cluster. Please check your kubeconfig and try again."
    fi

    print_message "Kubernetes checks passed." "$GREEN"

    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_message "Creating namespace $NAMESPACE..." "$YELLOW"
        kubectl create namespace "$NAMESPACE" || error_exit "Failed to create namespace $NAMESPACE"
        print_message "Namespace $NAMESPACE created successfully." "$GREEN"
    else
        print_message "Namespace $NAMESPACE already exists." "$YELLOW"
    fi

    # Prompt for OpenAI API key
    print_message "Prompting for OpenAI API Key..." "$YELLOW"
    read -s -p "Enter your OpenAI API Key: " openai_api_key
    echo # Newline after silent input
    if [[ -z "$openai_api_key" ]]; then
        error_exit "OpenAI API Key cannot be empty."
    fi
    create_or_update_secret "$OPENAI_SECRET_NAME" "key" "$openai_api_key" "OpenAI API key"

    # Prompt for Neo4j password
    print_message "Prompting for Neo4j Password..." "$YELLOW"
    read -s -p "Enter your Neo4j Password: " neo4j_password
    echo # Newline after silent input
    if [[ -z "$neo4j_password" ]]; then
        error_exit "Neo4j Password cannot be empty."
    fi
    neo4j_auth="neo4j/$neo4j_password"
    create_or_update_secret "$NEO4J_SECRET_NAME" "auth" "$neo4j_auth" "Neo4j credentials"

    # Apply the local Kubernetes configuration using Kustomize
    print_message "Applying local Kubernetes deployment using Kustomize..." "$YELLOW"
    if [ -d "k8s/overlays/local" ]; then
        kubectl apply -k k8s/overlays/local || error_exit "Failed to apply Kustomize configuration from k8s/overlays/local"
    else
        error_exit "Kustomize directory k8s/overlays/local not found. Ensure you are in the project root."
    fi
    
    print_message "Local Kubernetes deployment applied successfully!" "$GREEN"
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
    
    print_message "\nKubernetes deployment process complete!" "$GREEN"

elif [[ "$deployment_choice" == "2" ]]; then
    print_message "Proceeding with Docker Compose deployment..." "$GREEN"

    DOCKER_COMPOSE_CMD=""
    # Check if docker-compose (v1) or docker compose (v2) is installed
    if command_exists docker-compose; then
        DOCKER_COMPOSE_CMD="docker-compose"
        print_message "Using 'docker-compose' (v1 syntax)." "$YELLOW"
    elif command_exists docker && docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
        print_message "Using 'docker compose' (v2 syntax)." "$YELLOW"
    else
        error_exit "Neither 'docker-compose' (v1) nor 'docker compose' (v2) command found. Please install Docker Compose."
    fi
    
    # Check if docker is running
    if ! command_exists docker || ! docker info >/dev/null 2>&1; then
         error_exit "Docker does not seem to be running. Please start Docker and try again."
    fi
    print_message "Docker checks passed." "$GREEN"

    # Prompt for OpenAI API key for Docker Compose
    print_message "Prompting for OpenAI API Key (for Docker Compose)..." "$YELLOW"
    read -s -p "Enter your OpenAI API Key: " dc_openai_api_key
    echo # Newline after silent input
    if [[ -z "$dc_openai_api_key" ]]; then
        error_exit "OpenAI API Key cannot be empty."
    fi

    # Prompt for Neo4j password for Docker Compose
    print_message "Prompting for Neo4j Password (for Docker Compose)..." "$YELLOW"
    read -s -p "Enter your Neo4j Password: " dc_neo4j_password
    echo # Newline after silent input
    if [[ -z "$dc_neo4j_password" ]]; then
        error_exit "Neo4j Password cannot be empty."
    fi
    dc_neo4j_auth="neo4j/$dc_neo4j_password"

    print_message "Deploying using Docker Compose..." "$YELLOW"
    if [ -f "docker-compose/docker-compose.yaml" ]; then
        original_dir=$(pwd)
        cd docker-compose || error_exit "Failed to change directory to docker-compose/"
        
        print_message "Attempting to start services with Docker Compose..." "$YELLOW"
        # Pass secrets as environment variables to docker compose
        # OPENAI_API_KEY will be used by kotaemon-ui
        # GRAPHRAG_API_KEY will be used by graphrag-server (using the same OpenAI key)
        # NEO4J_AUTH will be used by neo4j service
        # NEO4J_PASSWORD will be used by neo4j healthcheck
        # NEO4J_USER defaults to neo4j in the compose file, so not explicitly set here
        
        COMMAND_TO_RUN="OPENAI_API_KEY='$dc_openai_api_key' GRAPHRAG_API_KEY='$dc_openai_api_key' NEO4J_AUTH='$dc_neo4j_auth' NEO4J_PASSWORD='$dc_neo4j_password' $DOCKER_COMPOSE_CMD -f docker-compose.yaml up -d"
        print_message "Executing: $COMMAND_TO_RUN" "$YELLOW"

        if [[ "$DOCKER_COMPOSE_CMD" == "docker compose" ]]; then
            OPENAI_API_KEY="$dc_openai_api_key" \
            GRAPHRAG_API_KEY="$dc_openai_api_key" \
            NEO4J_AUTH="$dc_neo4j_auth" \
            NEO4J_PASSWORD="$dc_neo4j_password" \
            docker compose -f docker-compose.yaml up -d || error_exit "Failed to start services with Docker Compose. Check logs and ensure Docker is running."
        else
            OPENAI_API_KEY="$dc_openai_api_key" \
            GRAPHRAG_API_KEY="$dc_openai_api_key" \
            NEO4J_AUTH="$dc_neo4j_auth" \
            NEO4J_PASSWORD="$dc_neo4j_password" \
            docker-compose -f docker-compose.yaml up -d || error_exit "Failed to start services with Docker Compose. Check logs and ensure Docker is running."
        fi
        
        print_message "Docker Compose services started successfully in detached mode." "$GREEN"
        print_message "You can check the status with: ${BOLD}cd docker-compose && $DOCKER_COMPOSE_CMD ps${NC}" "$YELLOW"
        print_message "To view logs, use: ${BOLD}cd docker-compose && $DOCKER_COMPOSE_CMD logs -f${NC}" "$YELLOW"
        print_message "To stop services, use: ${BOLD}cd docker-compose && $DOCKER_COMPOSE_CMD down${NC}" "$YELLOW"
        print_message "Check your docker-compose/docker-compose.yaml for exposed ports and service access details." "$YELLOW"
        
        cd "$original_dir" || print_message "Warning: Failed to return to original directory $original_dir" "$RED"
        
        print_message "\nDocker Compose deployment process complete!" "$GREEN"
    else
        error_exit "docker-compose/docker-compose.yaml not found. Ensure you are in the project root and the file exists."
    fi

else
    error_exit "Invalid choice. Please enter 1 for Kubernetes or 2 for Docker Compose."
fi