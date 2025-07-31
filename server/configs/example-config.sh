#!/bin/bash
# =============================================================================
# 🚀 VPS Auto Deploy - Example Configuration File
# =============================================================================
# Copy this file and rename it to your project name (e.g., my-app-config.sh)
# Fill in all required values below
# Usage: ./deploy-app.sh configs/my-app-config.sh

# =============================================================================
# 🖥️ SERVER CONFIGURATION
# =============================================================================

# SSH user for server (usually 'ubuntu', 'root', or custom user)
SERVER_USER="ubuntu"

# Deploy server IP address (your VPS public IP)
SERVER_IP="192.168.1.100"

# SSH authentication method: "key" or "password"
SSH_AUTH_METHOD="key"

# SSH key path (if using key auth) - leave empty if using password
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

# SSH password (if using password auth) - leave empty if using key
SSH_PASSWORD=""

# =============================================================================
# 📁 GIT CONFIGURATION
# =============================================================================

# GitHub repository URL (HTTPS or SSH format)
# Examples: "https://github.com/username/my-app" or "git@github.com:username/my-app.git"
GIT_REPO_URL="https://github.com/username/my-app"

# Git branch to deploy (usually "main" or "master")
GIT_BRANCH="main"

# Project directory on server (where source code will be stored)
PROJECT_DIR="/apps"

# Project name (creates subdirectory: /apps/PROJECT_NAME)
# Use lowercase with hyphens (e.g., "my-app", "api-backend")
PROJECT_NAME="my-app"

# =============================================================================
# 📦 APPLICATION CONFIGURATION
# =============================================================================

# Application configuration
RELEASE_NAME="my-app"
APP_NAME="my-app"
IMAGE="my-app:latest"

# Port that your application listens on inside the container
# Examples: 3000 (Node.js), 8080 (Java), 5000 (Python Flask), 80 (Nginx)
CONTAINER_PORT=3000

# Port that the Kubernetes service will expose
# Usually 80 for HTTP traffic
SERVICE_PORT=80

# =============================================================================
# 🌐 INGRESS & HTTPS CONFIGURATION
# =============================================================================

# List of domains for your application
# Examples: ("app.domain.com") or ("api.domain.com" "www.api.domain.com")  
INGRESS_HOSTS=("app.domain.com" "www.app.domain.com")

# Email for Let's Encrypt certificate notifications
# Use a valid email address you monitor
CERT_EMAIL="admin@domain.com"

# =============================================================================
# 📊 RESOURCE LIMITS (Used when enabled in interactive menu)
# =============================================================================

# Resource limits - these values are used when you select "Enable resource limits"
# in the interactive menu. Adjust based on your application needs.
CPU_REQUEST="250m"      # Minimum CPU (250m = 0.25 CPU cores)
CPU_LIMIT="500m"        # Maximum CPU (500m = 0.5 CPU cores)
MEMORY_REQUEST="256Mi"  # Minimum memory
MEMORY_LIMIT="512Mi"    # Maximum memory

# =============================================================================
# 📄 FILES
# =============================================================================

# Environment file containing your app's environment variables
# This file should exist in the same directory as this config
ENV_FILE=".env"

# Usage: ./deploy-app.sh configs/my-app-config.sh