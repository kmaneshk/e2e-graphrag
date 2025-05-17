#!/bin/bash
# Script to build Docker image for GraphRAG server from a specific GitHub release tag
# This script uses Git submodules to maintain a reference to the GraphRAG repository
# and builds the image using a custom Dockerfile in external/graphrag/

# Make this script executable
chmod +x "$0"

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
REPO_URL="https://github.com/microsoft/graphrag.git"
IMAGE_NAME="graphrag-server"
DEFAULT_TAG="v2.2.1"
SUBMODULE_DIR="external/graphrag"
CUSTOM_DOCKERFILE="./graphrag-dockerfile"

# Determine the Git tag to use (from argument or default)
GIT_TAG=${1:-$DEFAULT_TAG}

echo "Building GraphRAG server Docker image from tag: ${GIT_TAG}"

# Check if the custom Dockerfile exists
if [ ! -f "${CUSTOM_DOCKERFILE}" ]; then
  echo "Error: Custom Dockerfile not found at ${CUSTOM_DOCKERFILE}"
  echo "Please ensure the Dockerfile exists before running this script."
  exit 1
fi

# Check if the submodule directory exists but is not a git repository
if [ -d "${SUBMODULE_DIR}" ] && [ ! -d "${SUBMODULE_DIR}/.git" ] && [ ! -f "${SUBMODULE_DIR}/.git" ]; then
  echo "Directory ${SUBMODULE_DIR} exists but is not a git repository."
  echo "Initializing it as a submodule..."
  
  # Initialize the submodule
  git submodule add "${REPO_URL}" "${SUBMODULE_DIR}" || {
    echo "Error: Failed to add submodule. Trying alternative approach..."
    
    # If submodule add fails (e.g., if this directory is not a git repo),
    # fall back to a simple clone
    rm -rf "${SUBMODULE_DIR}/.git" 2>/dev/null  # Keep the Dockerfile
    git clone --depth 1 --branch "${GIT_TAG}" "${REPO_URL}" "${SUBMODULE_DIR}.tmp" || {
      echo "Error: Failed to clone repository. Please check your internet connection and the tag name."
      exit 1
    }
    
    # Move the cloned repository contents to the submodule directory, preserving our Dockerfile
    cp -a "${SUBMODULE_DIR}.tmp/." "${SUBMODULE_DIR}/"
    rm -rf "${SUBMODULE_DIR}.tmp"
  }
fi

# If the submodule already exists as a git repository, update it to the specified tag
if [ -d "${SUBMODULE_DIR}/.git" ] || [ -f "${SUBMODULE_DIR}/.git" ]; then
  echo "Updating submodule to tag ${GIT_TAG}..."
  
  cd "${SUBMODULE_DIR}"
  git fetch --tags
  git checkout "${GIT_TAG}" || {
    echo "Error: Failed to checkout tag ${GIT_TAG}. It might not exist."
    exit 1
  }
  cd ..
else
  # If the directory doesn't exist at all, add it as a submodule
  echo "Adding GraphRAG as a submodule at tag ${GIT_TAG}..."
  git submodule add "${REPO_URL}" "${SUBMODULE_DIR}" || {
    echo "Error: Failed to add submodule. Trying alternative approach..."
    
    # If submodule add fails (e.g., if this directory is not a git repo),
    # fall back to a simple clone
    git clone --depth 1 --branch "${GIT_TAG}" "${REPO_URL}" "${SUBMODULE_DIR}" || {
      echo "Error: Failed to clone repository. Please check your internet connection and the tag name."
      exit 1
    }
  }
  
  cd "${SUBMODULE_DIR}"
  git checkout "${GIT_TAG}" || {
    echo "Error: Failed to checkout tag ${GIT_TAG}. It might not exist."
    exit 1
  }
  cd ..
  
  # The custom Dockerfile is now at the root, no need to copy it into the submodule.
fi

# Create a build context directory
BUILD_CONTEXT="build-context"
rm -rf "${BUILD_CONTEXT}"
mkdir -p "${BUILD_CONTEXT}"

# Copy the GraphRAG source code to the build context
echo "Copying GraphRAG source code to build context..."
cp -r "${SUBMODULE_DIR}"/* "${BUILD_CONTEXT}/"

# Ensure our custom Dockerfile is in the build context
echo "Using custom Dockerfile for the build..."
cp "${CUSTOM_DOCKERFILE}" "${BUILD_CONTEXT}/Dockerfile"

# Build the Docker image
echo "Building Docker image: ${IMAGE_NAME}:${GIT_TAG}..."
cd "${BUILD_CONTEXT}"
docker build -t "${IMAGE_NAME}:${GIT_TAG}" .
cd ..

# Clean up the build context
rm -rf "${BUILD_CONTEXT}"

# If we get here, the build was successful
echo "Successfully built Docker image: ${IMAGE_NAME}:${GIT_TAG}"
echo "You can now use this image in your Kubernetes deployment by updating the image field in k8s/base/graphrag-deploy.yaml"

# Print instructions for future updates
cat << EOF

SUBMODULE MANAGEMENT INSTRUCTIONS
---------------------------------
The GraphRAG repository has been added as a submodule in the '${SUBMODULE_DIR}' directory.

To update the submodule to a new tag in the future:
  cd ${SUBMODULE_DIR}
  git fetch --tags
  git checkout <new-tag>
  cd ..
  git add ${SUBMODULE_DIR}
  git commit -m "Update GraphRAG submodule to <new-tag>"

When cloning this repository with submodules:
  git clone --recurse-submodules <this-repo-url>

To rebuild the Docker image with a different tag:
  ./build-graphrag-image.sh <tag-name>

DOCKERFILE CUSTOMIZATION
-----------------------
The Dockerfile at ./graphrag-dockerfile is a template that supports both Node.js and Python
applications. Before building the image for the first time, you should:

1. Examine the GraphRAG repository structure to determine if it's Node.js or Python based
2. Edit the Dockerfile to uncomment the appropriate sections
3. Adjust any paths, commands, or environment variables as needed
EOF