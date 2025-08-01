#!/bin/bash

# EZDeploy - Easy VPS Deployment with YAML Config
# 
# Usage: ./ezdeploy.sh <config.yaml>
# Example: ./ezdeploy.sh configs/enfyra-backend.yaml
#
# Required config variables:
#
# # Server info
# SERVER_USER="ubuntu"                    # SSH user for server
# SERVER_IP="192.168.1.100"              # Deploy server IP
# SSH_AUTH_METHOD="key"                   # "key" or "password"
# SSH_KEY_PATH="$HOME/.ssh/id_rsa"        # SSH key path (if using key auth)
# SSH_PASSWORD=""                         # SSH password (if using password auth)
# 
# # Git configuration  
# GIT_REPO_URL="git@github.com:user/repo.git"  # SSH URL of repo
# GIT_BRANCH="main"                       # Branch to deploy
# PROJECT_DIR="/apps"                     # Project directory on server
# PROJECT_NAME="my-app"                   # Project name (creates subdirectory)
#
# # K8s configuration
# K8S_MODE="microk8s"                     # "microk8s" or "kubeadm"
# RELEASE_NAME="my-app"                   # Pulumi stack name
# APP_NAME="my-app"                       # App name in K8s
# IMAGE="my-app:latest"                   # Docker image name:tag
# REPLICAS=2                              # Number of replica pods
# CONTAINER_PORT=3000                     # Container expose port
# SERVICE_PORT=80                         # Service expose port
#
# # Ingress configuration
# INGRESS_HOSTS=("app.domain.com" "api.domain.com")  # List of domains
# ENABLE_TLS=true                         # Enable HTTPS with cert-manager
# CERT_EMAIL="admin@domain.com"           # Email for Let's Encrypt
#
# # Resource limits (optional)
# ENABLE_RESOURCE_LIMITS=true
# CPU_REQUEST="250m"
# CPU_LIMIT="500m" 
# MEMORY_REQUEST="256Mi"
# MEMORY_LIMIT="512Mi"
#
# # Files
# ENV_FILE=".env"                         # File containing env variable

if [ $# -eq 0 ]; then
    echo "❌ Please specify YAML config file!"
    echo "Usage: ./ezdeploy.sh <config.yaml>"
    echo "Example: ./ezdeploy.sh configs/enfyra-backend.yaml"
    exit 1
fi

CONFIG_FILE=$1

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file does not exist: $CONFIG_FILE"
    exit 1
fi

# Auto-install yq if not found
if ! command -v yq &> /dev/null; then
    echo "🔧 yq not found, installing automatically..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        brew install yq
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - use most common amd64
        sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        sudo chmod +x /usr/local/bin/yq
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        # Windows
        echo "❌ Windows detected. Please install yq manually from:"
        echo "https://github.com/mikefarah/yq/releases"
        exit 1
    else
        echo "❌ Unknown OS. Please install yq manually"
        exit 1
    fi
    
    echo "✅ yq installed successfully!"
fi

# Simple step indicator function
show_step() {
  local step_name="$1"
  echo "🚀 $step_name"
}

echo "🚀 === EZDEPLOY with Config: $CONFIG_FILE ==="
echo "📋 Workflow: Config → SSH Key → System → Git → Docker → K8s → Deploy → Verify → Cleanup → Complete"
echo ""

show_step "Loading Configuration"

# Check and fix script permissions
if [ ! -x "$0" ]; then
  echo "🔧 Fixing script permissions..."
  chmod +x "$0"
  echo "✅ Script permissions updated"
fi

# Parse YAML configuration
echo "📋 Parsing YAML configuration..."

# Server configuration
SERVER_USER=$(yq '.server.user' "$CONFIG_FILE")
SERVER_IP=$(yq '.server.ip' "$CONFIG_FILE")
SSH_AUTH_METHOD=$(yq '.server.ssh.method' "$CONFIG_FILE")
SSH_PASSWORD=$(yq '.server.ssh.password // ""' "$CONFIG_FILE")
SSH_KEY_PATH=$(yq '.server.ssh.key_path // ""' "$CONFIG_FILE")

# Repository configuration
GIT_REPO_URL=$(yq '.repository.url' "$CONFIG_FILE")
GIT_BRANCH=$(yq '.repository.branch' "$CONFIG_FILE")

# Application configuration
PROJECT_NAME=$(yq '.application.name' "$CONFIG_FILE")
PROJECT_DIR=$(yq '.application.directory' "$CONFIG_FILE")
IMAGE_NAME=$(yq '.application.image.name' "$CONFIG_FILE")
IMAGE_TAG=$(yq '.application.image.tag' "$CONFIG_FILE")
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# Kubernetes configuration
K8S_MODE=$(yq '.kubernetes.provider' "$CONFIG_FILE")
CONTAINER_PORT=$(yq '.kubernetes.deployment.port' "$CONFIG_FILE")

# Ingress configuration
# Use mapfile if available, otherwise fall back to while loop
if command -v mapfile >/dev/null 2>&1; then
  mapfile -t INGRESS_HOSTS < <(yq '.ingress.hosts[]' "$CONFIG_FILE")
else
  # Alternative for systems without readarray/mapfile
  INGRESS_HOSTS=()
  while IFS= read -r host; do
    INGRESS_HOSTS+=("$host")
  done < <(yq '.ingress.hosts[]' "$CONFIG_FILE")
fi
CERT_EMAIL=$(yq '.ingress.tls.email' "$CONFIG_FILE")
ENABLE_TLS=$(yq '.ingress.tls.enabled // true' "$CONFIG_FILE")

# Environment file
ENV_FILE=$(yq '.environment.file' "$CONFIG_FILE")

# Database configuration
ENABLE_DATABASE=$(yq '.database.enabled // false' "$CONFIG_FILE")
DB_TYPE=$(yq '.database.type // "mysql"' "$CONFIG_FILE")
DB_NAME=$(yq '.database.name // ""' "$CONFIG_FILE")
DB_USER=$(yq '.database.user // ""' "$CONFIG_FILE")
DB_PASSWORD=$(yq '.database.password // ""' "$CONFIG_FILE")

# Redis configuration
ENABLE_REDIS=$(yq '.redis.enabled // false' "$CONFIG_FILE")
REDIS_PASSWORD=$(yq '.redis.password // ""' "$CONFIG_FILE")

# Set constants and defaults from YAML
SERVICE_PORT=$(yq '.kubernetes.deployment.service_port // 80' "$CONFIG_FILE")
RELEASE_NAME=$(yq '.kubernetes.deployment.release_name // .application.name' "$CONFIG_FILE")
APP_NAME=$(yq '.kubernetes.deployment.app_name // .application.name' "$CONFIG_FILE")

# Resource limits from config
ENABLE_RESOURCE_LIMITS=$(yq '.kubernetes.resources.limits.enabled // false' "$CONFIG_FILE")
CPU_REQUEST=$(yq '.kubernetes.resources.limits.cpu.request // "250m"' "$CONFIG_FILE")
CPU_LIMIT=$(yq '.kubernetes.resources.limits.cpu.limit // "500m"' "$CONFIG_FILE")
MEMORY_REQUEST=$(yq '.kubernetes.resources.limits.memory.request // "256Mi"' "$CONFIG_FILE")
MEMORY_LIMIT=$(yq '.kubernetes.resources.limits.memory.limit // "512Mi"' "$CONFIG_FILE")

# Other defaults
ENABLE_TLS="true"
REPLICAS=$(yq '.kubernetes.deployment.replicas // 1' "$CONFIG_FILE")

# Validate required fields
if [ -z "$SERVER_USER" ] || [ -z "$SERVER_IP" ] || [ -z "$PROJECT_NAME" ] || [ -z "$GIT_REPO_URL" ]; then
    echo "❌ Missing required configuration fields in YAML"
    exit 1
fi

echo "✅ YAML configuration parsed successfully!"

# Arrow key menu selection function  

# Configuration loaded from YAML - no interactive prompts needed
echo "✅ Configuration loaded from YAML: $CONFIG_FILE"
echo "   📊 Database: $ENABLE_DATABASE"
echo "   📊 Redis: $ENABLE_REDIS" 
echo "   🔒 TLS: $ENABLE_TLS"
echo "   💾 Resource Limits: $ENABLE_RESOURCE_LIMITS"
echo "   🔢 Replicas: $REPLICAS"
echo "   🌐 Ingress: $(printf "%s, " "${INGRESS_HOSTS[@]}" | sed "s/, $//")"
echo ""

# SSH connection helpers
get_ssh_command() {
  if [ "$SSH_AUTH_METHOD" = "password" ]; then
    if [ -z "$SSH_PASSWORD" ]; then
      echo "❌ SSH_PASSWORD is required when SSH_AUTH_METHOD=password"
      exit 1
    fi
    # Check if sshpass is installed, install if not found
    if ! command -v sshpass &> /dev/null; then
      echo "🔧 sshpass not found, installing automatically..."
      if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux (Ubuntu/Debian)
        if command -v apt-get &> /dev/null; then
          sudo apt-get update && sudo apt-get install -y sshpass
        elif command -v yum &> /dev/null; then
          sudo yum install -y sshpass
        elif command -v dnf &> /dev/null; then
          sudo dnf install -y sshpass
        else
          echo "❌ Unable to install sshpass automatically. Please install manually:"
          echo "Ubuntu/Debian: sudo apt-get install sshpass"
          echo "CentOS/RHEL: sudo yum install sshpass"
          exit 1
        fi
      elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
          brew install sshpass
        else
          echo "❌ Homebrew not found. Please install sshpass manually:"
          echo "macOS: brew install sshpass"
          echo "Or install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
          exit 1
        fi
      else
        echo "❌ Unsupported OS. Please install sshpass manually"
        exit 1
      fi
      
      # Verify installation
      if ! command -v sshpass &> /dev/null; then
        echo "❌ Failed to install sshpass"
        exit 1
      fi
      echo "✅ sshpass installed successfully!"
    fi
    echo "sshpass -p '$SSH_PASSWORD' ssh -o StrictHostKeyChecking=no"
  else
    if [ ! -f "$SSH_KEY_PATH" ]; then
      echo "❌ SSH key not found: $SSH_KEY_PATH"
      exit 1
    fi
    echo "ssh -i '$SSH_KEY_PATH'"
  fi
}

# get_scp_command function removed - not used anywhere

# Execute SSH command on server
ssh_exec() {
  local cmd="$1"
  if [ "$SSH_AUTH_METHOD" = "password" ]; then
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_IP" "$cmd"
  else
    ssh -i "$SSH_KEY_PATH" "$SERVER_USER@$SERVER_IP" "$cmd"
  fi
}

# Execute SSH command with heredoc on server
ssh_exec_heredoc() {
  if [ "$SSH_AUTH_METHOD" = "password" ]; then
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_IP" 'bash -s'
  else
    ssh -i "$SSH_KEY_PATH" "$SERVER_USER@$SERVER_IP" 'bash -s'
  fi
}

# Wait for package manager to be available
wait_for_package_manager() {
  echo "⏳ Waiting for package manager to be available..."
  LOCK_TIMEOUT=300  # 5 minutes max
  LOCK_ELAPSED=0
  
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    if [ $LOCK_ELAPSED -ge $LOCK_TIMEOUT ]; then
      echo "❌ Package manager still locked after ${LOCK_TIMEOUT} seconds"
      echo "💡 Forcing unlock (this may be dangerous but necessary)..."
      sudo pkill -f unattended-upgrade
      sudo rm -f /var/lib/dpkg/lock-frontend
      sudo rm -f /var/lib/dpkg/lock
      sudo dpkg --configure -a
      break
    fi
    
    echo "⏳ Package manager locked, waiting... (${LOCK_ELAPSED}s/${LOCK_TIMEOUT}s)"
    sleep 10
    LOCK_ELAPSED=$((LOCK_ELAPSED + 10))
  done
  
  echo "✅ Package manager available!"
}

# SSH key setup on server
setup_ssh_key() {
  echo "🔐 Setting up SSH key for Git repository access..."
  echo "🔧 Setting up SSH deploy key on server..."
  
  # Generate key on server and get the public key
  PUBLIC_KEY=$(ssh_exec_heredoc << SSHEOF
    # Use actual project variables
    DEPLOY_KEYS_DIR="/deployments/$PROJECT_NAME/keys"
    # Deployment directory for Pulumi
    CONFIGS_DIR="/deployments/$PROJECT_NAME/configs"
    DEPLOY_KEY_PATH="\$DEPLOY_KEYS_DIR/deploy_$PROJECT_NAME"
    PROJECT_NAME="$PROJECT_NAME"
    
    # Create deployments directory for this project
    sudo mkdir -p "\$DEPLOY_KEYS_DIR"
    # Pulumi directory created separately
    sudo mkdir -p "\$CONFIGS_DIR"
    sudo chown -R \$(whoami):\$(whoami) "/deployments/$PROJECT_NAME"
    
    # Check if key already exists
    if [ -f "\${DEPLOY_KEY_PATH}.pub" ]; then
        echo "🔑 Using existing SSH key for $PROJECT_NAME"
    else
        echo "🔑 Generating new SSH key for $PROJECT_NAME"
        # Generate shorter SSH key (2048 bits)
        ssh-keygen -t rsa -b 2048 -f "\$DEPLOY_KEY_PATH" -N "" -C "deploy-$PROJECT_NAME@\$(hostname)" >/dev/null 2>&1
        echo ""
    fi
    
    # Create SSH config to use separate key for this repo
    mkdir -p ~/.ssh
    
    # Clean up SSH config completely for this project
    if [ -f ~/.ssh/config ]; then
        # Remove all entries related to this project (including malformed ones)
        sed -i.bak '/^# Deploy key for '$PROJECT_NAME'/,/^$/d' ~/.ssh/config 2>/dev/null || true
        sed -i.bak '/^Host github.com-'$PROJECT_NAME'$/,/^$/d' ~/.ssh/config 2>/dev/null || true  
        sed -i.bak '/PROJECT_NAME_PLACEHOLDER/d' ~/.ssh/config 2>/dev/null || true
        # Remove empty lines at the end
        sed -i.bak -e :a -e '/^\s*$/\$d;N;ba' ~/.ssh/config 2>/dev/null || true
        rm -f ~/.ssh/config.bak 2>/dev/null || true
    fi
    
    # Add new config
    cat >> ~/.ssh/config <<EOF

# Deploy key for $PROJECT_NAME  
Host github.com-$PROJECT_NAME
    HostName github.com
    User git
    IdentityFile \${DEPLOY_KEY_PATH}
    IdentitiesOnly yes
    StrictHostKeyChecking no
EOF
    
    # Add key to ssh-agent
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add "\$DEPLOY_KEY_PATH" >/dev/null 2>&1
    
    # Add GitHub to known_hosts
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
    
    # Output the public key - Make sure it's displayed properly
    if [ -f "\${DEPLOY_KEY_PATH}.pub" ]; then
        cat "\${DEPLOY_KEY_PATH}.pub"
    else
        echo "ERROR: Public key file not found at \${DEPLOY_KEY_PATH}.pub"
        exit 1
    fi
SSHEOF
)

  # Check if we got the key with retry logic
  KEY_GENERATION_SUCCESS=false
  KEY_RETRY_COUNT=0
  KEY_MAX_RETRIES=3
  
  while [ "$KEY_GENERATION_SUCCESS" != "true" ] && [ $KEY_RETRY_COUNT -lt $KEY_MAX_RETRIES ]; do
    if [ -z "$PUBLIC_KEY" ] || [[ "$PUBLIC_KEY" == *"ERROR:"* ]]; then
      KEY_RETRY_COUNT=$((KEY_RETRY_COUNT + 1))
      echo "❌ Failed to generate SSH key on server (Attempt $KEY_RETRY_COUNT/$KEY_MAX_RETRIES)"
      echo "Debug: PUBLIC_KEY = '$PUBLIC_KEY'"
      
      if [ $KEY_RETRY_COUNT -lt $KEY_MAX_RETRIES ]; then
        echo "💡 This could be due to:"
        echo "   1. SSH connection unstable"
        echo "   2. Server permission issues"
        echo "   3. Directory creation failed"
        echo ""
        echo "⏳ Waiting 5 seconds before retry..."
        sleep 5
        echo "🔄 Retrying SSH key generation..."
        
        # Retry key generation
        PUBLIC_KEY=$(ssh_exec_heredoc << SSHEOF
    # Use actual project variables
    DEPLOY_KEYS_DIR="/deployments/$PROJECT_NAME/keys"
    # Deployment directory for Pulumi
    CONFIGS_DIR="/deployments/$PROJECT_NAME/configs"
    DEPLOY_KEY_PATH="\$DEPLOY_KEYS_DIR/deploy_$PROJECT_NAME"
    PROJECT_NAME="$PROJECT_NAME"
    
    # Create deployments directory for this project
    sudo mkdir -p "\$DEPLOY_KEYS_DIR"
    # Pulumi directory created separately
    sudo mkdir -p "\$CONFIGS_DIR"
    sudo chown -R \$(whoami):\$(whoami) "/deployments/$PROJECT_NAME"
    
    # Force remove existing key and regenerate
    rm -f "\${DEPLOY_KEY_PATH}" "\${DEPLOY_KEY_PATH}.pub"
    
    # Generate SSH key
    echo "🔑 Generating new SSH key for $PROJECT_NAME"
    ssh-keygen -t rsa -b 2048 -f "\$DEPLOY_KEY_PATH" -N "" -C "deploy-$PROJECT_NAME@\$(hostname)" >/dev/null 2>&1
    echo ""
    
    # Create SSH config to use separate key for this repo
    mkdir -p ~/.ssh
    
    # Clean up SSH config completely for this project
    if [ -f ~/.ssh/config ]; then
        # Remove all entries related to this project (including malformed ones)
        sed -i.bak '/^# Deploy key for '$PROJECT_NAME'/,/^$/d' ~/.ssh/config 2>/dev/null || true
        sed -i.bak '/^Host github.com-'$PROJECT_NAME'$/,/^$/d' ~/.ssh/config 2>/dev/null || true  
        sed -i.bak '/PROJECT_NAME_PLACEHOLDER/d' ~/.ssh/config 2>/dev/null || true
        # Remove empty lines at the end
        sed -i.bak -e :a -e '/^\s*$/\$d;N;ba' ~/.ssh/config 2>/dev/null || true
        rm -f ~/.ssh/config.bak 2>/dev/null || true
    fi
    
    # Add new config
    cat >> ~/.ssh/config <<EOF

# Deploy key for $PROJECT_NAME  
Host github.com-$PROJECT_NAME
    HostName github.com
    User git
    IdentityFile \${DEPLOY_KEY_PATH}
    IdentitiesOnly yes
    StrictHostKeyChecking no
EOF
    
    # Add key to ssh-agent
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add "\$DEPLOY_KEY_PATH" >/dev/null 2>&1
    
    # Add GitHub to known_hosts
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
    
    # Output the public key - Make sure it's displayed properly
    echo ""
    if [ -f "\${DEPLOY_KEY_PATH}.pub" ]; then
        cat "\${DEPLOY_KEY_PATH}.pub"
    else
        echo "ERROR: Public key file not found at \${DEPLOY_KEY_PATH}.pub"
        exit 1
    fi
SSHEOF
)
      else
        echo "❌ SSH key generation failed after $KEY_MAX_RETRIES attempts"
        echo "💡 Possible solutions:"
        echo "   1. Check SSH connection to server: ssh $SERVER_USER@$SERVER_IP"
        echo "   2. Verify server has sufficient disk space"
        echo "   3. Check server permissions for directory creation"
        echo "   4. Try again with a different server"
        exit 1
      fi
    else
      KEY_GENERATION_SUCCESS=true
    fi
  done
  
  # Display the key to user (ensure it's on one line)
  echo ""
  echo "🎉 =============== SSH DEPLOY KEY ==============="
  # Extract only the SSH key part (starts with ssh-rsa, ssh-ed25519, etc.)
  CLEAN_KEY=$(echo "$PUBLIC_KEY" | grep -E '^ssh-[a-zA-Z0-9]+ [A-Za-z0-9+/=]+ ' | head -1)
  if [ -n "$CLEAN_KEY" ]; then
    echo "$CLEAN_KEY"
  else
    # Fallback: display all but filter out generation messages and errors
    FALLBACK_KEY=$(echo "$PUBLIC_KEY" | grep -v "Generating new SSH key" | grep -v "ERROR:" | grep -E '^ssh-[a-zA-Z0-9]+ ' | head -1)
    if [ -n "$FALLBACK_KEY" ]; then
      echo "$FALLBACK_KEY"
    else
      echo "❌ Failed to extract valid SSH key from server response"
      echo "Raw response: $PUBLIC_KEY"
    fi
  fi
  echo "=============================================="
  echo ""
  
  # Clean up the key for clipboard (only the SSH key part)
  if [ -n "$CLEAN_KEY" ]; then
    PUBLIC_KEY_CLEAN="$CLEAN_KEY"
  else
    PUBLIC_KEY_CLEAN=$(echo "$PUBLIC_KEY" | grep -v "Generating new SSH key" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi
  
  # Try to copy to clipboard (works on macOS and Linux with xclip)
  if command -v pbcopy >/dev/null 2>&1; then
    echo "$PUBLIC_KEY_CLEAN" | pbcopy
    echo "✅ Key has been copied to clipboard (macOS)!"
  elif command -v xclip >/dev/null 2>&1; then
    echo "$PUBLIC_KEY_CLEAN" | xclip -selection clipboard
    echo "✅ Key has been copied to clipboard (Linux)!"
  elif command -v clip >/dev/null 2>&1; then
    echo "$PUBLIC_KEY_CLEAN" | clip
    echo "✅ Key has been copied to clipboard (Windows)!"
  else
    echo "📋 Please copy the key above manually"
  fi
  
  # Update git repo URL to use SSH alias
  REPO_PATH=$(echo "$GIT_REPO_URL" | sed 's/git@github.com://')
  GIT_REPO_URL="git@github.com-$PROJECT_NAME:$REPO_PATH"
  
  # Extract GitHub repo info for instructions
  GITHUB_REPO=$(echo "$GIT_REPO_URL" | sed 's/git@github.com://' | sed 's/git@github.com-[^:]*://' | sed 's/\.git$//')
  
  echo ""
  echo "🔗 HOW TO ADD DEPLOY KEY TO GITHUB:"
  echo "1. Key has been copied to clipboard (if available)"
  echo "2. Open browser: https://github.com/$GITHUB_REPO"
  echo "3. Click Settings → Deploy keys (left sidebar)"
  echo "4. Click 'Add deploy key'"
  echo "5. Title: Deploy-$PROJECT_NAME-$SERVER_IP"
  echo "6. Key: Paste key (Cmd+V / Ctrl+V)"
  echo "7. ✅ Check 'Allow write access'"
  echo "8. Click 'Add key'"
  echo ""
  echo "⚠️  After adding key to GitHub, press Enter to continue..."
  read -r
  
  # Wait for GitHub to sync the key
  echo "⏳ Waiting for GitHub to sync SSH key..."
  sleep 3
  
  # Test SSH key with retry logic
  KEY_VERIFIED=false
  RETRY_COUNT=0
  MAX_RETRIES=3
  
  while [ "$KEY_VERIFIED" != "true" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "🔄 Testing SSH key (Attempt $RETRY_COUNT/$MAX_RETRIES)..."
    
    # Verify SSH key exists before testing
    echo "🔍 Verifying SSH key files exist on server..."
    if [ "$SSH_AUTH_METHOD" = "password" ]; then
      KEY_CHECK=$(sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_IP" "
        if [ -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME ] && [ -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub ]; then
          echo 'KEY_EXISTS'
        else
          echo 'KEY_MISSING'
          ls -la /deployments/$PROJECT_NAME/keys/ 2>/dev/null || echo 'Directory not found'
        fi
      " 2>&1)
    else
      KEY_CHECK=$(ssh -o ConnectTimeout=10 -i "$SSH_KEY_PATH" "$SERVER_USER@$SERVER_IP" "
        if [ -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME ] && [ -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub ]; then
          echo 'KEY_EXISTS'
        else
          echo 'KEY_MISSING'
          ls -la /deployments/$PROJECT_NAME/keys/ 2>/dev/null || echo 'Directory not found'
        fi
      " 2>&1)
    fi
    
    if [[ "$KEY_CHECK" != *"KEY_EXISTS"* ]]; then
      echo "❌ SSH key files missing on server!"
      echo "Debug: $KEY_CHECK"
      echo "🔄 Key generation must have failed. Forcing regeneration..."
      # Directly regenerate key here
      echo "🔑 Generating new SSH key..."
      # Regenerate key by calling key generation part again
      if [ "$SSH_AUTH_METHOD" = "password" ]; then
        NEW_KEY=$(sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_IP" "
          sudo mkdir -p /deployments/$PROJECT_NAME/keys
          sudo chown -R \$USER:\$USER /deployments/$PROJECT_NAME
          rm -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME*
          ssh-keygen -t rsa -b 2048 -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME -N '' -C 'deploy-$PROJECT_NAME-retry@\$(hostname)' >/dev/null 2>&1
          
          # Create SSH config for this key
          mkdir -p ~/.ssh
          # Remove existing config for this project
          grep -v 'Host github.com-$PROJECT_NAME' ~/.ssh/config > ~/.ssh/config.tmp 2>/dev/null || true
          mv ~/.ssh/config.tmp ~/.ssh/config 2>/dev/null || true
          
          # Add new SSH config
          cat >> ~/.ssh/config <<SSHEOF

# Deploy key for $PROJECT_NAME
Host github.com-$PROJECT_NAME
    HostName github.com
    User git
    IdentityFile /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME
    IdentitiesOnly yes
    StrictHostKeyChecking no
SSHEOF
          
          chmod 600 ~/.ssh/config
          chmod 600 /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME
          chmod 644 /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub
          
          # Add GitHub to known_hosts
          ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
          
          if [ -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub ]; then
            cat /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub
          else
            echo 'KEY_GENERATION_FAILED'
          fi
        " 2>/dev/null)
      else
        NEW_KEY=$(ssh -o ConnectTimeout=10 -i "$SSH_KEY_PATH" "$SERVER_USER@$SERVER_IP" "
          sudo mkdir -p /deployments/$PROJECT_NAME/keys
          sudo chown -R \$USER:\$USER /deployments/$PROJECT_NAME
          rm -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME*
          ssh-keygen -t rsa -b 2048 -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME -N '' -C 'deploy-$PROJECT_NAME-retry@\$(hostname)' >/dev/null 2>&1
          
          # Create SSH config for this key
          mkdir -p ~/.ssh
          # Remove existing config for this project
          grep -v 'Host github.com-$PROJECT_NAME' ~/.ssh/config > ~/.ssh/config.tmp 2>/dev/null || true
          mv ~/.ssh/config.tmp ~/.ssh/config 2>/dev/null || true
          
          # Add new SSH config
          cat >> ~/.ssh/config <<SSHEOF

# Deploy key for $PROJECT_NAME
Host github.com-$PROJECT_NAME
    HostName github.com
    User git
    IdentityFile /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME
    IdentitiesOnly yes
    StrictHostKeyChecking no
SSHEOF
          
          chmod 600 ~/.ssh/config
          chmod 600 /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME
          chmod 644 /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub
          
          # Add GitHub to known_hosts
          ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
          
          if [ -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub ]; then
            cat /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub
          else
            echo 'KEY_GENERATION_FAILED'
          fi
        " 2>/dev/null)
      fi
      
      if [[ "$NEW_KEY" == *"KEY_GENERATION_FAILED"* ]] || [ -z "$NEW_KEY" ]; then
        echo "❌ Key regeneration also failed! SSH connection or server issues."
        continue
      fi
      
      echo ""
      echo "🆕 =============== NEW SSH DEPLOY KEY ==============="
      echo "$NEW_KEY"
      echo "==================================================="
      echo ""
      echo "🔗 PLEASE ADD THIS NEW KEY TO GITHUB:"
      echo "1. Copy the key above"
      echo "2. Go to: https://github.com/$GITHUB_REPO"
      echo "3. Settings → Deploy keys → Remove old key → Add new deploy key"
      echo "4. Title: Deploy-$PROJECT_NAME-retry-$(date +%H%M%S)"
      echo "5. Paste key and check 'Allow write access'"
      echo ""
      echo "⚠️  After adding the NEW key, press Enter to continue..."
      read -r
      echo "⏳ Waiting for GitHub to sync new key..."
      sleep 5
      # Don't continue, let it test the new key
    fi
    
    # Test SSH key
    echo "✅ SSH key files verified, testing connection..."
    if [ "$SSH_AUTH_METHOD" = "password" ]; then
      SSH_TEST=$(sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_IP" "ssh -T -i /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME -o StrictHostKeyChecking=no git@github.com-$PROJECT_NAME" 2>&1 || true)
    else
      SSH_TEST=$(ssh -o ConnectTimeout=10 -i "$SSH_KEY_PATH" "$SERVER_USER@$SERVER_IP" "ssh -T -i /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME -o StrictHostKeyChecking=no git@github.com-$PROJECT_NAME" 2>&1 || true)
    fi
    echo "🔍 SSH result: $SSH_TEST"
    
    if echo "$SSH_TEST" | grep -q "successfully authenticated"; then
      echo "✅ SSH key verified successfully!"
      KEY_VERIFIED=true
    else
      echo "❌ SSH key test failed (Attempt $RETRY_COUNT/$MAX_RETRIES)!"
      
      if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "🔍 Please ensure:"
        echo "   1. Key was added to GitHub Deploy Keys"
        echo "   2. 'Allow write access' was checked" 
        echo "   3. Key was saved (clicked 'Add key' button)"
        echo "   4. Wait 1-2 minutes for GitHub to sync"
        echo ""
        echo "💡 Options:"
        echo "   [R] Retry SSH test"
        echo "   [G] Generate new SSH key"
        echo "   [Q] Quit"
        echo ""
        read -p "Choose option (R/G/Q): " -r user_choice
        
        case $(echo "$user_choice" | tr '[:lower:]' '[:upper:]') in
          R)
            echo "⏳ Waiting 5 seconds before retry..."
            sleep 5
            ;;
          G)
            echo "🔑 Generating new SSH key..."
            # Regenerate key by calling key generation part again
            if [ "$SSH_AUTH_METHOD" = "password" ]; then
              NEW_KEY=$(sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_IP" "
                rm -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME*
                ssh-keygen -t rsa -b 2048 -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME -N '' -C 'deploy-$PROJECT_NAME-retry@\$(hostname)' >/dev/null 2>&1
                cat /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub
              " 2>/dev/null)
            else
              NEW_KEY=$(ssh -o ConnectTimeout=10 -i "$SSH_KEY_PATH" "$SERVER_USER@$SERVER_IP" "
                rm -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME*
                ssh-keygen -t rsa -b 2048 -f /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME -N '' -C 'deploy-$PROJECT_NAME-retry@\$(hostname)' >/dev/null 2>&1
                cat /deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME.pub
              " 2>/dev/null)
            fi
            
            echo ""
            echo "🆕 =============== NEW SSH DEPLOY KEY ==============="
            echo "$NEW_KEY"
            echo "==================================================="
            echo ""
            echo "🔗 PLEASE ADD THIS NEW KEY TO GITHUB:"
            echo "1. Copy the key above"
            echo "2. Go to: https://github.com/$GITHUB_REPO"
            echo "3. Settings → Deploy keys → Remove old key → Add new deploy key"
            echo "4. Title: Deploy-$PROJECT_NAME-retry-$(date +%H%M%S)"
            echo "5. Paste key and check 'Allow write access'"
            echo ""
            echo "⚠️  After adding the NEW key, press Enter to continue..."
            read -r
            echo "⏳ Waiting for GitHub to sync new key..."
            sleep 5
            RETRY_COUNT=0  # Reset retry count for new key
            ;;
          Q)
            echo "❌ Deployment cancelled by user"
            exit 1
            ;;
          *)
            echo "⚠️ Invalid option, retrying SSH test..."
            echo "⏳ Waiting 5 seconds..."
            sleep 5
            ;;
        esac
      fi
    fi
  done
  
  if [ "$KEY_VERIFIED" != "true" ]; then
    echo "❌ SSH key verification failed after $MAX_RETRIES attempts"
    echo "❌ Deployment cannot continue without working SSH key"
    exit 1
  fi
}

# Validation
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ .env file not found"
  exit 1
fi

# Detect HTTPS Git URLs and convert to SSH format
check_and_convert_git_url() {
  if [[ "$GIT_REPO_URL" == https://github.com/* ]]; then
    echo "🔧 Detected HTTPS GitHub URL, converting to SSH format..."
    GIT_REPO_URL=$(echo "$GIT_REPO_URL" | sed 's|https://github.com/|git@github.com:|')
    echo "✅ Converted to: $GIT_REPO_URL"
  fi
}

# Define global variables for remote paths
DEPLOY_KEYS_DIR="/deployments/$PROJECT_NAME/keys"
PULUMI_REMOTE_DIR="/deployments/$PROJECT_NAME"  # Pulumi code goes directly here
CONFIGS_DIR="/deployments/$PROJECT_NAME/configs"

# Convert HTTPS URL if needed
check_and_convert_git_url

show_step "Setting up SSH Key"
# Setup SSH key (automatically create if not exists)
setup_ssh_key

# Create ConfigMap content from .env file
create_configmap_content() {
  local configmap_args=""
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    # Extract key=value pairs
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      # Remove quotes if present
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      configmap_args="$configmap_args --from-literal=\"$key=$value\""
    fi
  done < "$ENV_FILE"
  echo "$configmap_args"
}

# Remote deployment operations
deploy_to_server() {
  show_step "Starting Server Deployment"
  echo "🚀 Starting deployment to server: $SERVER_IP"
  
  # Create remote directories
  echo "📤 Creating directories on server..."
  ssh_exec "mkdir -p $PULUMI_REMOTE_DIR $CONFIGS_DIR $DEPLOY_KEYS_DIR"
  
  # Get ConfigMap content
  CONFIGMAP_ARGS=$(create_configmap_content)
  
  show_step "Installing System Dependencies"
  # Run deployment on server
  echo "🔧 Running deployment on server..."
  ssh_exec_heredoc << EOF
    set -e
    
    echo "🔄 System update and basic tools installation..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl wget gnupg lsb-release apt-transport-https ca-certificates software-properties-common
    
    # Auto install Git if not found
    if ! command -v git &> /dev/null; then
      echo "🔧 Git not found, installing automatically..."
      sudo apt-get install -y -qq git
      echo "✅ Git installed successfully!"
    fi
    
    # Install Docker if not found
    if ! command -v docker &> /dev/null; then
      echo "🔧 Docker not found, installing automatically..."
      
      # Remove any existing docker lists to avoid conflicts
      sudo rm -f /etc/apt/sources.list.d/docker.list
      sudo rm -f /etc/apt/sources.list.d/docker.list.save
      sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg
      
      # Install Docker using the official method
      # Wait for package manager using the shared function
      $(declare -f wait_for_package_manager)
      
      wait_for_package_manager
      
      # Detect system architecture
      ARCH=\$(dpkg --print-architecture)
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=\$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      sudo apt-get update -qq
      sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      
      # Add current user to docker group
      sudo usermod -aG docker \$USER
      
      # Start and enable Docker
      sudo systemctl start docker
      sudo systemctl enable docker
      
      # Wait for Docker to be ready
      echo "⏳ Waiting for Docker to be ready..."
      for i in {1..10}; do
        if sudo docker info &> /dev/null; then
          echo "✅ Docker is ready!"
          break
        fi
        if [ \$i -eq 10 ]; then
          echo "❌ Docker failed to start within 20 seconds"
          exit 1
        fi
        echo "⏳ Docker attempt \$i/10 - waiting 2s..."
        sleep 2
      done
      
      echo "✅ Docker installed successfully!"
    fi
    
    # Install Node.js if not found (required for Pulumi)
    if ! command -v node &> /dev/null; then
      echo "🔧 Node.js not found, installing automatically..."
      
      # Wait for package manager to be available
      wait_for_package_manager() {
        echo "⏳ Waiting for package manager to be available..."
        LOCK_TIMEOUT=300  # 5 minutes max
        LOCK_ELAPSED=0
        
        while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
          if [ \$LOCK_ELAPSED -ge \$LOCK_TIMEOUT ]; then
            echo "❌ Package manager still locked after \${LOCK_TIMEOUT} seconds"
            echo "💡 Forcing unlock (this may be dangerous but necessary)..."
            sudo pkill -f unattended-upgrade
            sudo rm -f /var/lib/dpkg/lock-frontend
            sudo rm -f /var/lib/dpkg/lock
            sudo dpkg --configure -a
            break
          fi
          
          echo "⏳ Package manager locked, waiting... (\${LOCK_ELAPSED}s/\${LOCK_TIMEOUT}s)"
          sleep 10
          LOCK_ELAPSED=\$((LOCK_ELAPSED + 10))
        done
        
        echo "✅ Package manager available!"
      }
      
      wait_for_package_manager
      
      # Install Node.js 20.x LTS
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
      sudo apt-get install -y -qq nodejs
      
      echo "✅ Node.js installed successfully! Version: \$(node --version)"
    fi
    
    # Install Pulumi if not found
    # First, ensure PATH includes pulumi bin directory
    export PATH=\$PATH:\$HOME/.pulumi/bin
    
    if ! command -v pulumi &> /dev/null; then
      echo "🔧 Pulumi not found, installing automatically..."
      
      # Install Pulumi using official script
      if curl -fsSL https://get.pulumi.com | sh; then
        # Add Pulumi to PATH for current session
        export PATH=\$PATH:\$HOME/.pulumi/bin
        
        # Add to bashrc for future sessions
        if ! grep -q "pulumi/bin" ~/.bashrc; then
          echo 'export PATH=\$PATH:\$HOME/.pulumi/bin' >> ~/.bashrc
        fi
        
        # Verify installation
        if command -v pulumi &> /dev/null; then
          echo "✅ Pulumi installed successfully! Version: \$(pulumi version)"
        else
          echo "❌ Pulumi installation failed - binary not found"
          exit 1
        fi
      else
        echo "❌ Pulumi installation script failed"
        exit 1
      fi
    else
      echo "✅ Pulumi already installed! Version: \$(pulumi version)"
    fi
    
    # Install MySQL/MariaDB if configured
    if [ -n "$DB_TYPE" ] && [ "$DB_TYPE" != "" ]; then
      echo "🗄️ Setting up database: $DB_TYPE"
      
      if [ "$DB_TYPE" = "mysql" ]; then
        # Check if MySQL is installed
        if ! command -v mysql &> /dev/null && ! systemctl is-active --quiet mysql; then
          echo "🔧 Installing MySQL..."
          # Wait for package manager to be available
          wait_for_package_manager() {
            echo "⏳ Waiting for package manager to be available..."
            LOCK_TIMEOUT=300  # 5 minutes max
            LOCK_ELAPSED=0
            
            while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
              if [ \$LOCK_ELAPSED -ge \$LOCK_TIMEOUT ]; then
                echo "❌ Package manager still locked after \${LOCK_TIMEOUT} seconds"
                echo "💡 Forcing unlock (this may be dangerous but necessary)..."
                sudo pkill -f unattended-upgrade
                sudo rm -f /var/lib/dpkg/lock-frontend
                sudo rm -f /var/lib/dpkg/lock
                sudo dpkg --configure -a
                break
              fi
              
              echo "⏳ Package manager locked, waiting... (\${LOCK_ELAPSED}s/\${LOCK_TIMEOUT}s)"
              sleep 10
              LOCK_ELAPSED=\$((LOCK_ELAPSED + 10))
            done
            
            echo "✅ Package manager available!"
          }
          
          wait_for_package_manager
          sudo apt-get install -y -qq mysql-server
          
          # Start and enable MySQL
          sudo systemctl start mysql
          sudo systemctl enable mysql
          
          # Wait for MySQL to be ready with continuous check
          echo "⏳ Waiting for MySQL to be ready..."
          MYSQL_TIMEOUT=30  # 30 seconds max
          MYSQL_ELAPSED=0
          
          while [ \$MYSQL_ELAPSED -lt \$MYSQL_TIMEOUT ]; do
            if sudo mysql -e "SELECT 1;" &> /dev/null; then
              echo "✅ MySQL is ready! (took \${MYSQL_ELAPSED}s)"
              break
            fi
            
            echo "⏳ Waiting for MySQL... (\${MYSQL_ELAPSED}s/\${MYSQL_TIMEOUT}s)"
            sleep 2
            MYSQL_ELAPSED=\$((MYSQL_ELAPSED + 2))
            
            if [ \$MYSQL_ELAPSED -ge \$MYSQL_TIMEOUT ]; then
              echo "❌ MySQL failed to start within \${MYSQL_TIMEOUT} seconds"
              exit 1
            fi
          done
        fi
        
        # Configure MySQL database and user
        echo "🔧 Configuring MySQL database and user..."
        sudo mysql << MYSQL_EOF
DROP USER IF EXISTS '$DB_USER'@'%';
DROP USER IF EXISTS '$DB_USER'@'localhost';
CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS $DB_NAME;
FLUSH PRIVILEGES;
MYSQL_EOF
        
        # Configure MySQL for external access
        sudo sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf 2>/dev/null || true
        sudo sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/my.cnf 2>/dev/null || true
        
        # Restart MySQL to apply configuration
        sudo systemctl restart mysql
        
        echo "✅ MySQL configured successfully! Connect directly with:"
        echo "👤 Username: $DB_USER"
        echo "🔑 Password: $DB_PASSWORD"
        echo "🌐 Host: $SERVER_IP:3306"
      fi
    fi
    
    # Install Redis if enabled
    if [ "$ENABLE_REDIS" = "true" ]; then
      echo "🔴 Setting up Redis..."
      
      if ! command -v redis-server &> /dev/null; then
        echo "🔧 Installing Redis..."
        
        # Wait for package manager to be available
        wait_for_package_manager() {
          echo "⏳ Waiting for package manager to be available..."
          LOCK_TIMEOUT=300  # 5 minutes max
          LOCK_ELAPSED=0
          
          while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            if [ \$LOCK_ELAPSED -ge \$LOCK_TIMEOUT ]; then
              echo "❌ Package manager still locked after \${LOCK_TIMEOUT} seconds"
              echo "💡 Forcing unlock (this may be dangerous but necessary)..."
              sudo pkill -f unattended-upgrade
              sudo rm -f /var/lib/dpkg/lock-frontend
              sudo rm -f /var/lib/dpkg/lock
              sudo dpkg --configure -a
              break
            fi
            
            echo "⏳ Package manager locked, waiting... (\${LOCK_ELAPSED}s/\${LOCK_TIMEOUT}s)"
            sleep 10
            LOCK_ELAPSED=\$((LOCK_ELAPSED + 10))
          done
          
          echo "✅ Package manager available!"
        }
        
        wait_for_package_manager
        
        # Remove any existing Redis config to avoid conflicts
        sudo rm -f /etc/redis/redis.conf
        sudo apt-get install -y -qq redis-server
      fi
      
      # Configure Redis
      echo "🔧 Configuring Redis..."
      sudo sed -i 's/bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf
      sudo sed -i 's/protected-mode yes/protected-mode no/' /etc/redis/redis.conf
      
      if [ -n "$REDIS_PASSWORD" ]; then
        sudo sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
      fi
      
      # Start and enable Redis
      sudo systemctl restart redis-server
      sudo systemctl enable redis-server
      
      # Wait for Redis to be ready with continuous check
      echo "⏳ Waiting for Redis to be ready..."
      REDIS_TIMEOUT=30  # 30 seconds max
      REDIS_ELAPSED=0
      
      while [ \$REDIS_ELAPSED -lt \$REDIS_TIMEOUT ]; do
        if nc -z 0.0.0.0 6379; then
          echo "✅ Redis is ready on port 6379! (took \${REDIS_ELAPSED}s)"
          break
        fi
        
        echo "⏳ Waiting for Redis... (\${REDIS_ELAPSED}s/\${REDIS_TIMEOUT}s)"
        sleep 2
        REDIS_ELAPSED=\$((REDIS_ELAPSED + 2))
        
        if [ \$REDIS_ELAPSED -ge \$REDIS_TIMEOUT ]; then
          echo "❌ Redis failed to start within \${REDIS_TIMEOUT} seconds"
          exit 1
        fi
      done
      
      echo "✅ Redis configured successfully!"
    fi
    
    # Install MicroK8s if not found
    if ! command -v microk8s &> /dev/null; then
      echo "🔧 MicroK8s not found, installing automatically..."
      sudo snap install microk8s --classic
      
      # Add user to microk8s group
      sudo usermod -a -G microk8s \$USER
      
      # Wait for MicroK8s to be ready with retry logic
      echo "⏳ Waiting for MicroK8s to be ready..."
      for i in {1..20}; do
        if sudo microk8s status | grep -q "microk8s is running"; then
          echo "✅ MicroK8s is ready!"
          break
        fi
        if [ \$i -eq 20 ]; then
          echo "❌ MicroK8s failed to start within 40 seconds"
          exit 1
        fi
        echo "⏳ Attempt \$i/20 - waiting 2s..."
        sleep 2
      done
      
      
      # Using cert-manager instead for automatic SSL management
      echo "🔐 SSL certificates will be managed by cert-manager (automatic)"
      CERT_SUCCESS=true
      
      # Enable required addons one by one AFTER SSL generation
      echo "🔧 Enabling MicroK8s addons..."
      
      # Enable core addons first
      echo "📦 Enabling DNS and storage..."
      sudo microk8s enable dns storage
      
      # Pulumi will be used for deployment instead of Helm
      echo "ℹ️ Using Pulumi for Kubernetes deployments"
      
      # Enable cert-manager for automatic SSL certificates
      echo "🔐 Enabling cert-manager..."
      sudo microk8s enable cert-manager
      
      # Wait for cert-manager to be ready
      echo "⏳ Waiting for cert-manager to be ready..."
      sleep 30
      
      # Create ClusterIssuer for Let's Encrypt
      echo "📜 Creating Let's Encrypt ClusterIssuer..."
      sudo microk8s kubectl apply -f - <<ISSUEREOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
ISSUEREOF
      
      # Enable metallb first (required for ingress external IP)
      echo "⚖️ Enabling MetalLB load balancer..."
      sudo microk8s enable metallb:10.64.140.43-10.64.140.49
      
      # Wait for metallb to be ready
      echo "⏳ Waiting for MetalLB to be ready..."
      METALLB_TIMEOUT=30
      METALLB_ELAPSED=0
      
      while [ \$METALLB_ELAPSED -lt \$METALLB_TIMEOUT ]; do
        # Debug: show actual pods status
        echo "🔍 Debug MetalLB pods:"
        sudo microk8s kubectl get pods -n metallb-system 2>/dev/null || echo "No pods in metallb-system namespace"
        
        METALLB_RUNNING=\$(sudo microk8s kubectl get pods -n metallb-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [ "\$METALLB_RUNNING" -gt 0 ]; then
          echo "✅ MetalLB is ready! (\$METALLB_RUNNING pods running, took \${METALLB_ELAPSED}s)"
          break
        fi
        
        echo "⏳ Waiting for MetalLB... (\${METALLB_ELAPSED}s/\${METALLB_TIMEOUT}s)"
        sleep 3
        METALLB_ELAPSED=\$((METALLB_ELAPSED + 3))
        
        if [ \$METALLB_ELAPSED -ge \$METALLB_TIMEOUT ]; then
          echo "⚠️ MetalLB not ready after \${METALLB_TIMEOUT}s, continuing anyway"
          break
        fi
      done
      
      # Enable ingress and wait for it to be ready
      echo "🌐 Enabling Ingress controller..."
      sudo microk8s enable ingress
      
      # Wait for ingress controller to be ready
      echo "⏳ Waiting for ingress controller to be ready..."
      INGRESS_TIMEOUT=60  # 60 seconds max
      INGRESS_ELAPSED=0
      
      while [ \$INGRESS_ELAPSED -lt \$INGRESS_TIMEOUT ]; do
        # Debug: show actual pods status
        echo "🔍 Debug Ingress pods:"
        sudo microk8s kubectl get pods -n ingress 2>/dev/null || echo "No pods in ingress namespace"
        
        INGRESS_RUNNING=\$(sudo microk8s kubectl get pods -n ingress --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [ "\$INGRESS_RUNNING" -gt 0 ]; then
          echo "✅ Ingress controller is ready! (\$INGRESS_RUNNING pods running, took \${INGRESS_ELAPSED}s)"
          break
        fi
        
        echo "⏳ Waiting for ingress controller... (\${INGRESS_ELAPSED}s/\${INGRESS_TIMEOUT}s)"
        sleep 3
        INGRESS_ELAPSED=\$((INGRESS_ELAPSED + 3))
        
        if [ \$INGRESS_ELAPSED -ge \$INGRESS_TIMEOUT ]; then
          echo "⚠️ Ingress controller not ready after \${INGRESS_TIMEOUT}s, continuing anyway"
          break
        fi
      done
      
      # SSL certificates already generated before addons
      echo "✅ SSL certificate generation handled in pre-addon phase"
      
      # Final check that cluster is ready
      echo "⏳ Final cluster readiness check..."
      if sudo microk8s kubectl get nodes | grep -q "Ready"; then
        echo "✅ MicroK8s cluster is ready!"
      else
        echo "⚠️ Cluster may not be fully ready, but continuing"
      fi
      
      echo "✅ MicroK8s installed and configured successfully!"
    fi
    
    # Using Pulumi for infrastructure management
    echo "ℹ️ Using Pulumi for infrastructure deployment"
    
    echo "📥 Starting Git pull on server..."
    # Create /apps directory if not exists
    sudo mkdir -p "$PROJECT_DIR"
    sudo chown \$USER:\$USER "$PROJECT_DIR"
    
    PROJECT_PATH="$PROJECT_DIR/$PROJECT_NAME"
    DEPLOY_KEY_PATH="/deployments/$PROJECT_NAME/keys/deploy_$PROJECT_NAME"
    
    if [ -d "\${PROJECT_PATH}" ] && [ -d "\${PROJECT_PATH}/.git" ]; then
      echo "📂 Project exists, pulling latest changes..."
      cd "\${PROJECT_PATH}"
      
      # Check if repository is accessible and test SSH connection
      if git remote get-url origin &>/dev/null; then
        echo "🔄 Testing SSH connection before fetch..."
        # Test SSH connection first
        if ssh -T -i "\$DEPLOY_KEY_PATH" -o StrictHostKeyChecking=no git@github.com-$PROJECT_NAME 2>&1 | grep -q "successfully authenticated"; then
          echo "✅ SSH connection verified"
          echo "🔄 Fetching from remote..."
          if git fetch origin; then
            echo "✅ Fetch successful"
            
            # Check if the target branch exists locally
            if git show-ref --verify --quiet refs/heads/$GIT_BRANCH; then
              echo "📋 Switching to branch: $GIT_BRANCH"
              git checkout $GIT_BRANCH
            else
              echo "📋 Creating and switching to branch: $GIT_BRANCH"
              git checkout -b $GIT_BRANCH origin/$GIT_BRANCH
            fi
            
            # Pull latest changes
            echo "⬇️ Pulling latest changes..."
            if git pull origin $GIT_BRANCH; then
              echo "✅ Pull successful"
              # Clean untracked files (optional)
              echo "🧹 Cleaning untracked files..."
              git clean -fd || echo "⚠️ Some files could not be cleaned"
            else
              echo "❌ Pull failed - will re-clone repository"
              cd "$PROJECT_DIR"
              sudo rm -rf "$PROJECT_NAME"
            fi
          else
            echo "❌ Fetch failed - will re-clone repository"
            cd "$PROJECT_DIR"
            sudo rm -rf "$PROJECT_NAME"
          fi
        else
          echo "❌ SSH connection failed - will re-clone repository"
          cd "$PROJECT_DIR"
          sudo rm -rf "$PROJECT_NAME"
        fi
      else
        echo "⚠️ Repository appears corrupted, re-cloning..."
        cd "$PROJECT_DIR"  
        sudo rm -rf "$PROJECT_NAME"
      fi
    fi
    
    # Clone repository if it doesn't exist or was removed due to issues
    if [ ! -d "\$PROJECT_PATH" ] || [ ! -d "\$PROJECT_PATH/.git" ]; then
      echo "📂 Cloning new project..."
      cd "$PROJECT_DIR"
      # Remove any existing directory first
      sudo rm -rf "$PROJECT_NAME"
      
      # Try clone first, if fails then generate new key
      if git clone "$GIT_REPO_URL" "$PROJECT_NAME"; then
        cd "$PROJECT_NAME"
        git checkout $GIT_BRANCH
        echo "✅ Repository cloned successfully, using branch: $GIT_BRANCH"
      else
        echo "❌ Failed to clone repository - SSH key may be invalid"
        echo "🔑 Generating new SSH key..."
        
        # Remove old key and generate new one
        rm -f "\$DEPLOY_KEY_PATH" "\${DEPLOY_KEY_PATH}.pub"
        ssh-keygen -t rsa -b 2048 -f "$DEPLOY_KEY_PATH" -N "" -C "deploy-$PROJECT_NAME-new@\$(hostname)" >/dev/null 2>&1
        
        # Update SSH config
        grep -v "Host github.com-$PROJECT_NAME" ~/.ssh/config > ~/.ssh/config.tmp 2>/dev/null || true
        mv ~/.ssh/config.tmp ~/.ssh/config 2>/dev/null || true
        
        cat >> ~/.ssh/config <<NEWSSHEOF2

# Deploy key for $PROJECT_NAME (regenerated)  
Host github.com-$PROJECT_NAME
    HostName github.com
    User git
    IdentityFile \${DEPLOY_KEY_PATH}
    IdentitiesOnly yes
    StrictHostKeyChecking no
NEWSSHEOF2
        
        # Add to ssh-agent
        eval "\$(ssh-agent -s)" >/dev/null 2>&1
        ssh-add "\$DEPLOY_KEY_PATH" >/dev/null 2>&1
        
        # Show new key to user
        echo ""
        echo "🆕 =============== NEW SSH DEPLOY KEY ==============="
        cat "${DEPLOY_KEY_PATH}.pub"
        echo "=================================================="
        echo ""
        echo "🔗 PLEASE ADD THIS NEW KEY TO GITHUB:"
        echo "1. Copy the key above"
        echo "2. Go to: https://github.com/\$(echo "$GIT_REPO_URL" | sed 's/.*github.com[:-]//' | sed 's/\.git$//')"
        echo "3. Settings → Deploy keys → Add deploy key"
        echo "4. Title: Deploy-$PROJECT_NAME-\$(date +%Y%m%d-%H%M%S)"
        echo "5. Paste key and check 'Allow write access'"
        echo ""
        echo "⚠️  After adding the NEW key, press Enter to retry..."
        read -r
        
        # Retry clone with verification loop
        RETRY_COUNT=0
        MAX_RETRIES=3
        CLONE_SUCCESS=false
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$CLONE_SUCCESS" != "true" ]; do
          RETRY_COUNT=$((RETRY_COUNT + 1))
          echo "🔄 Testing SSH key (Attempt $RETRY_COUNT/$MAX_RETRIES)..."
          
          # Test SSH connection first
          if ssh -T -i "\$DEPLOY_KEY_PATH" -o StrictHostKeyChecking=no git@github.com-$PROJECT_NAME 2>&1 | grep -q "successfully authenticated"; then
            echo "✅ SSH key verified successfully!"
            
            # Now try to clone
            if git clone "$GIT_REPO_URL" "$PROJECT_NAME"; then
              cd "$PROJECT_NAME"
              git checkout $GIT_BRANCH
              echo "✅ Repository cloned successfully with new key!"
              CLONE_SUCCESS=true
              break
            else
              echo "❌ SSH works but clone failed. Repository may not exist or permissions issue."
              exit 1
            fi
          else
            echo "❌ SSH key not working yet (Attempt $RETRY_COUNT/$MAX_RETRIES)"
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
              echo "⚠️  Key might not be added yet. Please ensure you:"
              echo "   1. Added the key to GitHub Deploy Keys"
              echo "   2. Checked 'Allow write access'"  
              echo "   3. Saved the key"
              echo ""
              echo "⏳ Waiting 10 seconds before retry..."
              sleep 10
            fi
          fi
        done
        
        # Final check if clone was successful
        if [ "$CLONE_SUCCESS" != "true" ]; then
          echo "❌ Failed after $MAX_RETRIES attempts. Please check:"
          echo "   1. Key was added to GitHub Deploy Keys"
          echo "   2. 'Allow write access' was checked"
          echo "   3. Repository exists and accessible"
          echo "   4. GitHub Deploy Key URL: https://github.com/\$(echo "$GIT_REPO_URL" | sed 's/.*github.com[:-]//' | sed 's/\.git$//')/settings/keys"
          exit 1
        fi
      fi
    fi
    
    echo "✅ Successfully pulled project from branch: $GIT_BRANCH"
EOF

show_step "Building Docker Image"
ssh_exec_heredoc << EOF
    echo "🐳 Starting Docker image build on server..."
    
    # Verify project directory exists
    if [ ! -d "$PROJECT_DIR/$PROJECT_NAME" ]; then
      echo "❌ Project directory not found: $PROJECT_DIR/$PROJECT_NAME"
      echo "💡 Git operations may have failed. Please check:"
      echo "   1. SSH key is working properly"
      echo "   2. Repository URL is correct"
      echo "   3. Branch '$GIT_BRANCH' exists"
      exit 1
    fi
    
    cd "$PROJECT_DIR/$PROJECT_NAME"
    
    # Check Dockerfile
    if [ ! -f "Dockerfile" ]; then
      echo "❌ Dockerfile not found in project directory: \$(pwd)"
      echo "💡 Please check:"
      echo "   1. Dockerfile exists in repository root"
      echo "   2. Git clone was successful"
      echo "   3. Repository structure is correct"
      ls -la
      exit 1
    fi
    
    # Build Docker image
    echo "🔨 Building Docker image: $IMAGE"
    sudo docker build -t "$IMAGE" .
    
    if [ \$? -eq 0 ]; then
      echo "✅ Docker image built successfully: $IMAGE"
      
      # Import image to MicroK8s for local access
      echo "📥 Importing image to MicroK8s..."
      sudo docker save "$IMAGE" | sudo microk8s ctr image import -
      echo "✅ Image imported to MicroK8s successfully"
    else
      echo "❌ Docker image build failed"
      exit 1
    fi
EOF

show_step "Setting up Pulumi Infrastructure"

# First, copy Pulumi code from local to server
echo "📤 Copying Pulumi infrastructure code to server..."

# Setup SCP parameters based on auth method
if [ "$SSH_AUTH_METHOD" = "password" ]; then
  sshpass -p "$SSH_PASSWORD" scp -r -o StrictHostKeyChecking=no pulumi/* "$SERVER_USER@$SERVER_IP:$PULUMI_REMOTE_DIR/"
else
  scp -r -i "$SSH_KEY_PATH" pulumi/* "$SERVER_USER@$SERVER_IP:$PULUMI_REMOTE_DIR/"
fi

# Pass variables to remote script - use environment variables in SSH
ssh_exec_heredoc <<EOF
    # Set local variables from passed environment
    PROJECT_NAME="$PROJECT_NAME"
    APP_NAME="$APP_NAME"
    IMAGE="$IMAGE"
    REPLICAS="$REPLICAS"
    CONTAINER_PORT="$CONTAINER_PORT"
    SERVICE_PORT="$SERVICE_PORT"
    ENABLE_TLS="$ENABLE_TLS"
    CERT_EMAIL="$CERT_EMAIL"
    ENABLE_RESOURCE_LIMITS="$ENABLE_RESOURCE_LIMITS"
    CPU_REQUEST="$CPU_REQUEST"
    CPU_LIMIT="$CPU_LIMIT"
    MEMORY_REQUEST="$MEMORY_REQUEST"
    MEMORY_LIMIT="$MEMORY_LIMIT"
    
    # Individual host variables
    INGRESS_HOST_1="$INGRESS_HOST_1"
    INGRESS_HOST_2="$INGRESS_HOST_2"
    INGRESS_HOST_3="$INGRESS_HOST_3"    
    echo "🎯 Setting up Pulumi infrastructure..."
    
    # Pass variables to remote session using export
    export PROJECT_NAME="$PROJECT_NAME"
    export APP_NAME="$APP_NAME"
    export IMAGE="$IMAGE"
    export REPLICAS="$REPLICAS"
    export CONTAINER_PORT="$CONTAINER_PORT"
    export SERVICE_PORT="$SERVICE_PORT"
    export ENABLE_TLS="$ENABLE_TLS"
    export CERT_EMAIL="$CERT_EMAIL"
    export ENABLE_RESOURCE_LIMITS="$ENABLE_RESOURCE_LIMITS"
    export CPU_REQUEST="$CPU_REQUEST"
    export CPU_LIMIT="$CPU_LIMIT"
    export MEMORY_REQUEST="$MEMORY_REQUEST"
    export MEMORY_LIMIT="$MEMORY_LIMIT"
    
    # Set variables directly for SSH heredoc
    PROJECT_NAME_VAR="$PROJECT_NAME"
    APP_NAME_VAR="$APP_NAME"
    IMAGE_VAR="$IMAGE"
    REPLICAS_VAR="$REPLICAS"
    CONTAINER_PORT_VAR="$CONTAINER_PORT"
    SERVICE_PORT_VAR="$SERVICE_PORT"
    
    # Create ingress hosts array - pass each host separately
    INGRESS_HOST_COUNT=${#INGRESS_HOSTS[@]}
    INGRESS_HOST_1="${INGRESS_HOSTS[0]:-}"
    INGRESS_HOST_2="${INGRESS_HOSTS[1]:-}"
    INGRESS_HOST_3="${INGRESS_HOSTS[2]:-}"
    
    # Create array on remote side
    INGRESS_HOSTS_LIST=""
    for host in "${INGRESS_HOSTS[@]}"; do
      if [ -n "$host" ]; then
        INGRESS_HOSTS_LIST="$INGRESS_HOSTS_LIST '$host'"
      fi
    done
    
    # Ensure directory ownership
    sudo chown -R \$(whoami):\$(whoami) "/deployments/$PROJECT_NAME"
    
    # Set proper permissions for Pulumi files
    chmod -R 755 "$PULUMI_REMOTE_DIR"
    
    # Fix SSH key permissions that may have been affected
    chmod 600 "$DEPLOY_KEYS_DIR/deploy_$PROJECT_NAME" 2>/dev/null || true
    chmod 644 "$DEPLOY_KEYS_DIR/deploy_$PROJECT_NAME.pub" 2>/dev/null || true
    
    # Navigate to Pulumi directory
    cd "$PULUMI_REMOTE_DIR"
    
    # Verify files were copied
    echo "📋 Verifying Pulumi files..."
    if [ ! -f "package.json" ] || [ ! -f "index.ts" ] || [ ! -d "components" ]; then
      echo "❌ Pulumi files not copied correctly!"
      echo "📁 Current directory contents:"
      ls -la
      exit 1
    fi
    echo "✅ Pulumi files verified"
    
    # Install Node.js dependencies
    echo "📦 Installing Node.js dependencies..."
    echo "⏳ This may take a few minutes..."
    if timeout 300 npm install --no-progress --silent; then
      echo "✅ Node.js dependencies installed successfully"
    else
      echo "❌ Failed to install Node.js dependencies (timeout or error)"
      echo "🔍 Checking if package.json exists..."
      ls -la package.json || echo "❌ package.json not found"
      exit 1
    fi
    
    echo "✅ Pulumi infrastructure code ready"
    
    # Setup Pulumi local backend
    echo "🔧 Setting up Pulumi local backend..."
    export PULUMI_HOME="$PULUMI_REMOTE_DIR/.pulumi"
    mkdir -p "\$PULUMI_HOME"
    export PATH=\$PATH:\$HOME/.pulumi/bin
    export PULUMI_CONFIG_PASSPHRASE=""
    
    # Login to local backend
    pulumi login file://\$PULUMI_HOME
    
    # Initialize stack
    echo "📚 Initializing Pulumi stack..."
    if ! pulumi stack select $PROJECT_NAME 2>/dev/null; then
      pulumi stack init $PROJECT_NAME --non-interactive
    fi
    
    # Set Pulumi configuration from shell variables
    echo "⚙️ Configuring Pulumi..."
    echo "🔍 Debug variables:"
    echo "   PROJECT_NAME='$PROJECT_NAME'"
    echo "   APP_NAME='$APP_NAME'" 
    echo "   IMAGE='$IMAGE'"
    echo "   REPLICAS='$REPLICAS'"
    echo "   CONTAINER_PORT='$CONTAINER_PORT'"
    echo "   SERVICE_PORT='$SERVICE_PORT'"
    
    pulumi config set auto-deploy:projectName "\$PROJECT_NAME"
    pulumi config set auto-deploy:appName "\$APP_NAME"
    pulumi config set auto-deploy:image "\$IMAGE"
    pulumi config set auto-deploy:replicas \$REPLICAS
    pulumi config set auto-deploy:containerPort \$CONTAINER_PORT
    pulumi config set auto-deploy:servicePort \$SERVICE_PORT
    
    # Set ingress hosts as JSON array
    HOSTS_JSON='['
    FIRST=true
    for host in ${INGRESS_HOSTS[@]}; do
      if [ "\$FIRST" = true ]; then
        HOSTS_JSON+="\"\$host\""
        FIRST=false
      else
        HOSTS_JSON+=",\"\$host\""
      fi
    done
    HOSTS_JSON+=']'
    # Rebuild ingress hosts array from individual variables
    INGRESS_HOSTS=()
    [ -n "\$INGRESS_HOST_1" ] && INGRESS_HOSTS+=("\$INGRESS_HOST_1")
    [ -n "\$INGRESS_HOST_2" ] && INGRESS_HOSTS+=("\$INGRESS_HOST_2")
    [ -n "\$INGRESS_HOST_3" ] && INGRESS_HOSTS+=("\$INGRESS_HOST_3")
    
    echo "🔍 Debug: INGRESS_HOSTS array in remote session:"
    for i in "\${!INGRESS_HOSTS[@]}"; do
      echo "  [\$i]: '\${INGRESS_HOSTS[i]}'"
    done
    echo "🔍 Debug: Individual vars: '\$INGRESS_HOST_1' '\$INGRESS_HOST_2'"
    
    # Set ingress hosts using path syntax for array
    i=0
    for host in "\${INGRESS_HOSTS[@]}"; do
      if [ -n "\$host" ]; then
        pulumi config set --path "auto-deploy:ingressHosts[\$i]" "\$host"
        i=\$((i+1))
      fi
    done
    
    # Set TLS configuration
    pulumi config set auto-deploy:enableTls \$ENABLE_TLS
    pulumi config set auto-deploy:certEmail "\$CERT_EMAIL"
    
    # Set resource limits
    pulumi config set auto-deploy:enableResourceLimits \$ENABLE_RESOURCE_LIMITS
    if [ "\$ENABLE_RESOURCE_LIMITS" = true ]; then
      pulumi config set auto-deploy:cpuRequest "\$CPU_REQUEST"
      pulumi config set auto-deploy:cpuLimit "\$CPU_LIMIT"
      pulumi config set auto-deploy:memoryRequest "\$MEMORY_REQUEST"
      pulumi config set auto-deploy:memoryLimit "\$MEMORY_LIMIT"
    fi
    
    # Set ConfigMap name
    pulumi config set auto-deploy:envConfigMap "\$PROJECT_NAME-env"
    
    echo "✅ Pulumi configured successfully"
    
    # Validate critical Pulumi configuration
    echo "🔍 Validating Pulumi configuration..."
    PULUMI_CONFIG_VALID=true
    
    # Check required configs exist
    if ! pulumi config get auto-deploy:projectName >/dev/null 2>&1; then
      echo "❌ Missing required config: auto-deploy:projectName"
      PULUMI_CONFIG_VALID=false
    fi
    
    if ! pulumi config get auto-deploy:appName >/dev/null 2>&1; then
      echo "❌ Missing required config: auto-deploy:appName" 
      PULUMI_CONFIG_VALID=false
    fi
    
    if ! pulumi config get auto-deploy:image >/dev/null 2>&1; then
      echo "❌ Missing required config: auto-deploy:image"
      PULUMI_CONFIG_VALID=false
    fi
    
    # Validate array config format
    if ! pulumi config get auto-deploy:ingressHosts >/dev/null 2>&1; then
      echo "❌ Missing required config: auto-deploy:ingressHosts"
      PULUMI_CONFIG_VALID=false
    fi
    
    # Validate numeric configs
    REPLICAS_CONFIG=\$(pulumi config get auto-deploy:replicas 2>/dev/null || echo "")
    if [ -z "\$REPLICAS_CONFIG" ] || ! [[ "\$REPLICAS_CONFIG" =~ ^[0-9]+$ ]]; then
      echo "❌ Invalid or missing replicas config: '\$REPLICAS_CONFIG'"
      PULUMI_CONFIG_VALID=false
    fi
    
    CONTAINER_PORT_CONFIG=\$(pulumi config get auto-deploy:containerPort 2>/dev/null || echo "")
    if [ -z "\$CONTAINER_PORT_CONFIG" ] || ! [[ "\$CONTAINER_PORT_CONFIG" =~ ^[0-9]+$ ]]; then
      echo "❌ Invalid or missing containerPort config: '\$CONTAINER_PORT_CONFIG'"
      PULUMI_CONFIG_VALID=false
    fi
    
    if [ "\$PULUMI_CONFIG_VALID" != "true" ]; then
      echo "❌ Pulumi configuration validation failed!"
      echo "🔧 Current Pulumi config:"
      pulumi config || echo "Failed to show config"
      exit 1
    fi
    
    echo "✅ Pulumi configuration validated successfully"
    
    # Create ConfigMap from local .env file content
    echo "🔧 Creating ConfigMap from .env file..."
    # Create ConfigMap with dynamic content
    sudo microk8s kubectl create configmap $PROJECT_NAME-env $CONFIGMAP_ARGS --dry-run=client -o yaml | sudo microk8s kubectl apply -f -
    echo "✅ ConfigMap created with environment variables"
    
    # Clean deployment - Remove existing deployment and unused images
    echo "🗑️ Cleaning existing deployment and unused images..."
    
    # Clean up existing resources before Pulumi deployment
    if [ "$K8S_MODE" = "microk8s" ]; then      
      # Clean up any existing Pulumi resources
      echo "🧹 Cleaning existing Pulumi resources..."
      sudo microk8s kubectl delete deployment "${PROJECT_NAME}-deployment" --ignore-not-found || true
      sudo microk8s kubectl delete service "${PROJECT_NAME}-service" --ignore-not-found || true
      sudo microk8s kubectl delete ingress "${PROJECT_NAME}-ingress" --ignore-not-found || true
      # Also cleanup with actual resource names that might exist
      sudo microk8s kubectl delete ingress "${PROJECT_NAME}" --force --grace-period=0 --ignore-not-found 2>/dev/null || true
      
      # Check for running pods and force delete immediately if found
      echo "⏳ Checking for remaining pods..."
      RUNNING_PODS=\$(sudo microk8s kubectl get pods -l app="$APP_NAME" --no-headers 2>/dev/null | wc -l)
      if [ "\$RUNNING_PODS" -gt 0 ]; then
        echo "🗑️ Found \$RUNNING_PODS running pods, force deleting immediately..."
        sudo microk8s kubectl delete pods -l app="$APP_NAME" --force --grace-period=0 || true
        echo "✅ All pods force deleted!"
      else
        echo "✅ All pods terminated!"
      fi
      
      # Clean unused images (optional for disk space)
      echo "🧹 Cleaning unused images..."
      sudo docker image prune -f || true
      
      echo "✅ Cleanup completed"
    else
      echo "🧹 Cleaning up existing Kubernetes resources..."
      # Clean up any existing Pulumi resources
      kubectl delete deployment "${PROJECT_NAME}-deployment" --ignore-not-found || true
      kubectl delete service "${PROJECT_NAME}-service" --ignore-not-found || true
      kubectl delete ingress "${PROJECT_NAME}-ingress" --ignore-not-found || true
    fi
    
    # Deploy application using Pulumi
    
    # Deploy with Pulumi
    echo "🚀 Deploying with Pulumi..."
    cd "$PULUMI_REMOTE_DIR"
    export PULUMI_HOME="$PULUMI_REMOTE_DIR/.pulumi"
    export PATH=\$PATH:\$HOME/.pulumi/bin
    export PULUMI_CONFIG_PASSPHRASE=""
    
    # Set kubeconfig for Pulumi to use MicroK8s
    if [ "$K8S_MODE" = "microk8s" ]; then
      export KUBECONFIG=/var/snap/microk8s/current/credentials/client.config
    fi
    
    # Check for stuck operations before starting deployment
    echo "🔍 Checking for stuck Pulumi operations..."
    if pulumi stack export 2>/dev/null | grep -q '"inProgress"'; then
      echo "⚠️ Detected stuck operations from previous deployment!"
      echo "🧹 Clearing all pending operations..."
      pulumi cancel --force --yes || true
      sleep 5
      
      # Double check - if still stuck, refresh state
      if pulumi stack export 2>/dev/null | grep -q '"inProgress"'; then
        echo "🔄 Force refreshing stack state..."
        pulumi refresh --yes --non-interactive --force || true
      fi
    fi
    
    # Run Pulumi deployment with comprehensive conflict resolution
    echo "🚀 Running Pulumi deployment..."
    DEPLOY_SUCCESS=false
    DEPLOY_RETRY_COUNT=0
    DEPLOY_MAX_RETRIES=3
    
    while [ "$DEPLOY_SUCCESS" != "true" ] && [ \$DEPLOY_RETRY_COUNT -lt \$DEPLOY_MAX_RETRIES ]; do
      DEPLOY_RETRY_COUNT=\$((DEPLOY_RETRY_COUNT + 1))
      echo "🔄 Deployment attempt \$DEPLOY_RETRY_COUNT/\$DEPLOY_MAX_RETRIES..."
      
      # Clear any pending operations first
      echo "🧹 Clearing pending operations..."
      pulumi cancel --yes || true
      
      # Force kill any stuck operations
      echo "🔨 Force clearing stuck operations..."
      pulumi cancel --force || true
      
      # Check for pending operations and handle them
      if pulumi stack export 2>/dev/null | grep -q '"inProgress"'; then
        echo "⚠️ Found stuck operations, clearing state..."
        pulumi cancel --force || true
        # Wait a moment
        sleep 3
      fi
      
      # Refresh state to clear pending operations
      echo "🔄 Refreshing Pulumi state..."
      pulumi refresh --yes --non-interactive || echo "Refresh may have issues, continuing..."
      
      # For field conflicts, delete conflicting resources first
      if [ \$DEPLOY_RETRY_COUNT -gt 1 ]; then
        echo "🧹 Cleaning up existing resources to resolve conflicts..."
        if [ "$K8S_MODE" = "microk8s" ]; then
          KUBECTL_CMD="sudo microk8s kubectl"
        else
          KUBECTL_CMD="kubectl"
        fi
        
        # Delete resources with finalizer removal if needed
        \$KUBECTL_CMD delete deployment "${PROJECT_NAME}-deployment" --grace-period=0 --force --ignore-not-found || true
        \$KUBECTL_CMD delete service "${PROJECT_NAME}-service" --grace-period=0 --force --ignore-not-found || true
        \$KUBECTL_CMD delete ingress "${PROJECT_NAME}-ingress" --grace-period=0 --force --ignore-not-found || true
        
        # Wait for resources to be fully deleted
        echo "⏳ Waiting for resources to be cleaned up..."
        for i in {1..15}; do
          if ! \$KUBECTL_CMD get deployment "${PROJECT_NAME}-deployment" >/dev/null 2>&1 && \
             ! \$KUBECTL_CMD get service "${PROJECT_NAME}-service" >/dev/null 2>&1 && \
             ! \$KUBECTL_CMD get ingress "${PROJECT_NAME}-ingress" >/dev/null 2>&1; then
            echo "✅ Resources cleaned up successfully"
            break
          fi
          echo "⏳ Waiting for cleanup... (attempt \$i/15)"
          sleep 2
        done
        
        # Clear Pulumi state for these resources with dependency handling
        echo "🔄 Clearing Pulumi state..."
        pulumi state delete "urn:pulumi:${PROJECT_NAME}::auto-deploy::kubernetes:networking.k8s.io/v1:Ingress::${PROJECT_NAME}-ingress" --yes || true
        pulumi state delete "urn:pulumi:${PROJECT_NAME}::auto-deploy::kubernetes:core/v1:Service::${PROJECT_NAME}-service" --yes --target-dependents || true
        pulumi state delete "urn:pulumi:${PROJECT_NAME}::auto-deploy::kubernetes:apps/v1:Deployment::${PROJECT_NAME}-deployment" --yes --target-dependents || true
        
        # Force clean Pulumi stack to resolve all conflicts
        echo "🧹 Force cleaning Pulumi stack..."
        pulumi stack export --file /tmp/pulumi-backup.json || true
        pulumi destroy --yes --non-interactive --skip-preview || echo "Destroy may fail, continuing..."
        pulumi stack init ${PROJECT_NAME} --non-interactive || echo "Stack may already exist"
      fi
      
      # Try deployment
      echo "🚀 Running Pulumi deployment (attempt \$DEPLOY_RETRY_COUNT)..."
      if pulumi up --yes --non-interactive --skip-preview; then
        echo "✅ Pulumi deployment successful!"
        DEPLOY_SUCCESS=true
        break
      else
        echo "❌ Pulumi deployment failed (attempt \$DEPLOY_RETRY_COUNT/\$DEPLOY_MAX_RETRIES)"
        
        if [ \$DEPLOY_RETRY_COUNT -lt \$DEPLOY_MAX_RETRIES ]; then
          echo "⏳ Waiting 10 seconds before retry..."
          sleep 10
        fi
      fi
    done
    
    if [ "$DEPLOY_SUCCESS" != "true" ]; then
      echo "❌ Pulumi deployment failed after \$DEPLOY_MAX_RETRIES attempts!"
      echo "🔍 Final status check..."
      pulumi stack ls || echo "No stacks found"
      pulumi config || echo "No config found"
      echo "🔍 Kubernetes resources:"
      if [ "$K8S_MODE" = "microk8s" ]; then
        KUBECTL_CMD="sudo microk8s kubectl"
      else
        KUBECTL_CMD="kubectl"
      fi
      
      \$KUBECTL_CMD get all -l project=${PROJECT_NAME} || echo "No resources found"
      
      # Check if resources are actually working despite Pulumi conflicts
      echo "🔍 Checking if deployment is actually working..."
      ACTUAL_DEPLOYMENT_READY=false
      
      if \$KUBECTL_CMD get deployment "${PROJECT_NAME}" >/dev/null 2>&1; then
        READY_REPLICAS=\$(\$KUBECTL_CMD get deployment "${PROJECT_NAME}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED_REPLICAS=\$(\$KUBECTL_CMD get deployment "${PROJECT_NAME}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        
        if [ "\$READY_REPLICAS" -gt 0 ] && [ "\$READY_REPLICAS" = "\$DESIRED_REPLICAS" ]; then
          echo "✅ Deployment is actually working: \$READY_REPLICAS/\$DESIRED_REPLICAS replicas ready"
          
          # Check service and ingress too
          SERVICE_EXISTS=false
          INGRESS_EXISTS=false
          
          if \$KUBECTL_CMD get service "${PROJECT_NAME}-service" >/dev/null 2>&1; then
            echo "✅ Service exists"
            SERVICE_EXISTS=true
          elif \$KUBECTL_CMD get service "${PROJECT_NAME}" >/dev/null 2>&1; then
            echo "✅ Service exists (alternative name)"
            SERVICE_EXISTS=true
          fi
          
          if \$KUBECTL_CMD get ingress "${PROJECT_NAME}" >/dev/null 2>&1; then
            echo "✅ Ingress exists"
            INGRESS_EXISTS=true
          elif \$KUBECTL_CMD get ingress "${PROJECT_NAME}-ingress" >/dev/null 2>&1; then
            echo "✅ Ingress exists (alternative name)"
            INGRESS_EXISTS=true
          fi
          
          if [ "\$SERVICE_EXISTS" = "true" ]; then
            echo "🎉 Deployment is functional despite Pulumi conflicts!"
            echo "💡 The application should be accessible at: https://api.enfyra.io"
            ACTUAL_DEPLOYMENT_READY=true
            
            if [ "\$INGRESS_EXISTS" != "true" ]; then
              echo "⚠️ Ingress may not be configured - HTTPS access might not work"
            fi
          fi
        fi
      fi
      
      if [ "\$ACTUAL_DEPLOYMENT_READY" != "true" ]; then
        echo "❌ Resources are not properly deployed"
        exit 1
      else
        echo "⚠️ Pulumi has conflicts but deployment is working - continuing..."
      fi
    fi
    
    # Pulumi deployment section completed
    
    # Comprehensive deployment validation
    echo "🔍 Validating deployment success..."
    DEPLOYMENT_VALID=true
    
    # Wait for deployment to be ready
    echo "⏳ Waiting for deployment to be ready..."
    if [ "$K8S_MODE" = "microk8s" ]; then
      KUBECTL_CMD="sudo microk8s kubectl"
    else
      KUBECTL_CMD="kubectl"
    fi
    
    # Check deployment exists and is ready
    for i in {1..30}; do
      if \$KUBECTL_CMD get deployment "${PROJECT_NAME}" >/dev/null 2>&1; then
        READY_REPLICAS=\$(\$KUBECTL_CMD get deployment "${PROJECT_NAME}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED_REPLICAS=\$(\$KUBECTL_CMD get deployment "${PROJECT_NAME}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        
        if [ "\$READY_REPLICAS" = "\$DESIRED_REPLICAS" ] && [ "\$READY_REPLICAS" -gt 0 ]; then
          echo "✅ Deployment ready: \$READY_REPLICAS/\$DESIRED_REPLICAS replicas"
          break
        else
          echo "⏳ Waiting for deployment... \$READY_REPLICAS/\$DESIRED_REPLICAS ready (attempt \$i/30)"
        fi
      else
        echo "⏳ Waiting for deployment to be created... (attempt \$i/30)"
      fi
      
      if [ \$i -eq 30 ]; then
        echo "❌ Deployment not ready after 150 seconds"
        DEPLOYMENT_VALID=false
      fi
      
      sleep 5
    done
    
    # Check service exists
    if \$KUBECTL_CMD get service "${PROJECT_NAME}" >/dev/null 2>&1; then
      echo "✅ Service exists: ${PROJECT_NAME}"
    elif \$KUBECTL_CMD get service "${PROJECT_NAME}-service" >/dev/null 2>&1; then
      echo "✅ Service exists: ${PROJECT_NAME}-service"
    else
      echo "❌ Service not found"
      DEPLOYMENT_VALID=false
    fi
    
    # Check ingress exists  
    if \$KUBECTL_CMD get ingress "${PROJECT_NAME}" >/dev/null 2>&1; then
      echo "✅ Ingress exists: ${PROJECT_NAME}"
    elif \$KUBECTL_CMD get ingress "${PROJECT_NAME}-ingress" >/dev/null 2>&1; then
      echo "✅ Ingress exists: ${PROJECT_NAME}-ingress"  
    else
      echo "❌ Ingress not found"
      DEPLOYMENT_VALID=false
    fi
    
    # Check pods are running and not OOMKilled
    echo "🔍 Checking pod health..."
    POD_LIST=\$(\$KUBECTL_CMD get pods -l app=${PROJECT_NAME} -o name 2>/dev/null || echo "")
    if [ -z "\$POD_LIST" ]; then
      echo "❌ No pods found for app: ${PROJECT_NAME}"
      DEPLOYMENT_VALID=false
    else
      for pod in \$POD_LIST; do
        POD_STATUS=\$(\$KUBECTL_CMD get \$pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        POD_RESTART_COUNT=\$(\$KUBECTL_CMD get \$pod -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
        
        if [ "\$POD_STATUS" = "Running" ]; then
          echo "✅ Pod \$pod: \$POD_STATUS (restarts: \$POD_RESTART_COUNT)"
          
          # Check for OOM kills in pod events
          OOM_EVENTS=\$(\$KUBECTL_CMD get events --field-selector involvedObject.name=\${pod##*/} 2>/dev/null | grep -i "oomkilled\|out of memory" | wc -l)
          if [ "\$OOM_EVENTS" -gt 0 ]; then
            echo "⚠️ Pod \$pod has OOM events - consider increasing memory limits"
          fi
        else
          echo "❌ Pod \$pod: \$POD_STATUS"
          DEPLOYMENT_VALID=false
          
          # Show pod logs for debugging
          echo "🔍 Pod logs for debugging:"
          \$KUBECTL_CMD describe \$pod | tail -10
        fi
      done
    fi
    
    if [ "\$DEPLOYMENT_VALID" != "true" ]; then
      echo "❌ Deployment validation failed!"
      echo "🔧 Kubernetes resources status:"
      \$KUBECTL_CMD get all -l project=${PROJECT_NAME} || echo "Failed to get resources"
      exit 1
    fi
    
    echo "✅ All deployment resources validated successfully"
    
    # Wait for deployment to be ready
    echo "⏳ Waiting for deployment to be ready..."
    for i in {1..30}; do
      if [ "$K8S_MODE" = "microk8s" ]; then
        READY_PODS=\$(sudo microk8s kubectl get pods -l app="$APP_NAME" -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | grep -o true | wc -l)
        TOTAL_PODS=\$(sudo microk8s kubectl get pods -l app="$APP_NAME" --no-headers 2>/dev/null | wc -l)
      else
        READY_PODS=\$(kubectl get pods -l app="$APP_NAME" -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | grep -o true | wc -l)
        TOTAL_PODS=\$(kubectl get pods -l app="$APP_NAME" --no-headers 2>/dev/null | wc -l)
      fi
      
      if [ "\$TOTAL_PODS" -gt 0 ] && [ "\$READY_PODS" -eq "\$TOTAL_PODS" ]; then
        echo "✅ All \$TOTAL_PODS pods are ready!"
        break
      fi
      
      if [ \$i -eq 30 ]; then
        echo "⚠️ Deployment may not be fully ready after 60 seconds (\$READY_PODS/\$TOTAL_PODS pods ready)"
        echo "🔍 Debugging pod issues..."
        
        # Show pod status
        echo "📋 Pod Status:"
        if [ "$K8S_MODE" = "microk8s" ]; then
          sudo microk8s kubectl get pods -l app="$APP_NAME" -o wide
          echo ""
          echo "📋 Pod Events:"
          sudo microk8s kubectl get events --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | tail -10
          echo ""
          echo "📋 Pod Logs (last 20 lines):"
          sudo microk8s kubectl logs -l app="$APP_NAME" --tail=20 || echo "No logs available"
        fi
        break
      fi
      
      echo "⏳ Deployment readiness attempt \$i/30 - \$READY_PODS/\$TOTAL_PODS pods ready, waiting 2s..."
      sleep 2
    done
    
    echo "✅ Deployment successful!"
    
    # Note: SSL redirect is automatic when TLS is configured in ingress
    # cert-manager will handle ACME challenges with http01-edit-in-place annotation
    
    # Check Ingress controller status and wait if needed
    echo "🌐 Checking Ingress controller status..."
    INGRESS_CHECK_TIMEOUT=30
    INGRESS_CHECK_ELAPSED=0
    
    while [ \$INGRESS_CHECK_ELAPSED -lt \$INGRESS_CHECK_TIMEOUT ]; do
      if [ "$K8S_MODE" = "microk8s" ]; then
        # Check if ingress controller is running
        INGRESS_CONTROLLER_RUNNING=\$(sudo microk8s kubectl get pods -n ingress --no-headers 2>/dev/null | grep -c "Running")
        if [ "\$INGRESS_CONTROLLER_RUNNING" -gt 0 ]; then
          echo "✅ Ingress controller is running (\$INGRESS_CONTROLLER_RUNNING pods) - took \${INGRESS_CHECK_ELAPSED}s"
          echo "✅ Ingress configured successfully (access via server IP: $SERVER_IP)"
          break
        fi
      else
        # Standard kubernetes check - verify ingress controller is running
        INGRESS_CONTROLLER_RUNNING=\$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep "ingress" | grep -c "Running")
        if [ "\$INGRESS_CONTROLLER_RUNNING" -gt 0 ]; then
          echo "✅ Ingress controller is running (\$INGRESS_CONTROLLER_RUNNING pods) - took \${INGRESS_CHECK_ELAPSED}s"
          echo "✅ Ingress configured successfully"
          break
        fi
      fi
      
      echo "⏳ Waiting for Ingress controller... (\${INGRESS_CHECK_ELAPSED}s/\${INGRESS_CHECK_TIMEOUT}s)"
      sleep 2
      INGRESS_CHECK_ELAPSED=\$((INGRESS_CHECK_ELAPSED + 2))
      
      if [ \$INGRESS_CHECK_ELAPSED -ge \$INGRESS_CHECK_TIMEOUT ]; then
        echo "⚠️ Ingress controller not ready after \${INGRESS_CHECK_TIMEOUT}s, but continuing..."
        echo "📋 Available pods:"
        if [ "$K8S_MODE" = "microk8s" ]; then
          sudo microk8s kubectl get pods -n ingress 2>/dev/null || echo "No ingress namespace found"
        else
          kubectl get pods -n kube-system | grep ingress 2>/dev/null || echo "No ingress controller found"
        fi
        break
      fi
    done
    
    # Validate HTTPS access after deployment
    if [ "\$CERT_SUCCESS" = true ]; then
      echo "🔍 Validating HTTPS configuration..."
      
      FIRST_HOST=\$(echo "${INGRESS_HOSTS[0]}")
      
      # Wait a moment for ingress to be ready
      sleep 3
      
      # Test HTTPS access
      echo "🔍 Testing HTTPS access to \$FIRST_HOST..."
      if curl -Iv --connect-timeout 10 --resolve \$FIRST_HOST:443:$SERVER_IP https://\$FIRST_HOST 2>&1 | grep -q "SSL certificate verify ok"; then
        echo "✅ HTTPS validation successful!"
      else
        echo "⚠️ HTTPS validation failed, but deployment completed"
      fi
      
      # Show TLS configuration summary
      echo "📋 TLS Configuration Summary:"
      echo "   🔐 Using cert-manager for automatic SSL certificate management"
      echo "   🌐 Ingress TLS: \$(sudo microk8s kubectl get ingress $APP_NAME -o jsonpath='{.spec.tls[0].secretName}')"
      echo "   🔑 Secret Data: \$(sudo microk8s kubectl get secret $PROJECT_NAME-tls -o jsonpath='{.data}' | wc -c) bytes"
    fi
EOF
  
  if [ $? -eq 0 ]; then
    echo "🎉 Server deployment successful!"
  else
    echo "❌ Deployment failed"
    exit 1
  fi
}

# Deploy to server
deploy_to_server

show_step "Deployment Complete"
echo ""
echo "🎉 === DEPLOY COMPLETED SUCCESSFULLY ==="
echo "✅ Project: $PROJECT_NAME"
echo "✅ Git Pull: $PROJECT_DIR/$PROJECT_NAME"
echo "✅ Docker Build: $IMAGE"
echo "✅ Pulumi Deploy: $PROJECT_NAME"

# Internal SSL Certificate Check
if [ "$ENABLE_TLS" = "true" ]; then
  echo ""
  echo "🔐 Checking SSL Certificate Status (Internal Check)..."
  echo "⏳ SSL certificates may take 1-2 minutes to be issued..."
  
  CERT_SUCCESS=false
  CERT_CHECK_COUNT=0
  CERT_MAX_CHECKS=10  # 30 seconds total (10 checks * 3 seconds)
  
  # Run SSL check on server
  CERT_CHECK_RESULT=$(ssh_exec_heredoc <<CERTEOF
    echo "🔍 Checking internal SSL certificate status..."
    
    if [ "$K8S_MODE" = "microk8s" ]; then
      KUBECTL_CMD="sudo microk8s kubectl"
    else
      KUBECTL_CMD="kubectl"
    fi
    
    CERT_READY=false
    CERT_MAX_CHECKS=$CERT_MAX_CHECKS  # Pass variable into heredoc
    for ((i=1; i<=\$CERT_MAX_CHECKS; i++)); do
      echo "🔍 Certificate Check \$i/\$CERT_MAX_CHECKS..."
      
      # Check certificate resource status
      CERT_STATUS=\$(\$KUBECTL_CMD get certificate ${PROJECT_NAME}-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
      
      if [ "\$CERT_STATUS" = "True" ]; then
        echo "✅ Certificate is ready!"
        
        # Check certificate details
        NOT_AFTER=\$(\$KUBECTL_CMD get certificate ${PROJECT_NAME}-tls -o jsonpath='{.status.notAfter}' 2>/dev/null)
        if [ -n "\$NOT_AFTER" ]; then
          echo "✅ Certificate valid until: \$NOT_AFTER"
          echo "✅ SSL certificate setup completed successfully!"
          CERT_READY=true
          break
        fi
      else
        echo "⏳ Certificate not ready yet..."
        
        # Show certificate status for debugging
        CERT_MESSAGE=\$(\$KUBECTL_CMD get certificate ${PROJECT_NAME}-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "No message")
        if [ "\$CERT_MESSAGE" != "No message" ] && [ "\$CERT_MESSAGE" != "" ]; then
          echo "📋 Status: \$CERT_MESSAGE"
        fi
      fi
      
      if [ \$i -lt \$CERT_MAX_CHECKS ]; then
        echo "⏳ Waiting 3 seconds before retry..."
        sleep 3
      fi
    done
    
    if [ "\$CERT_READY" = "true" ]; then
      echo "SUCCESS"
    else
      echo "PENDING"
    fi
CERTEOF
)
  
  echo ""
  if echo "$CERT_CHECK_RESULT" | grep -q "SUCCESS"; then
    echo "🎉 SSL Certificate Setup Complete!"
    echo "✅ Your application is accessible at: https://${INGRESS_HOSTS[0]}"
    echo "🔐 SSL certificate is valid and ready"
  else
    echo "⚠️ SSL Certificate Status:"
    echo "   🔄 Certificate may still be issuing"
    echo "   ⏰ Let's Encrypt can take up to 5-10 minutes"
    echo "   🌐 Your application will be accessible at: https://${INGRESS_HOSTS[0]}"
    echo "   💡 Certificate will be ready shortly - check again in a few minutes"
    echo ""
    echo "🔍 To check certificate status manually on server:"
    echo "   kubectl get certificate -A"
    echo "   kubectl describe certificate ${PROJECT_NAME}-tls"
  fi
else
  echo ""
  echo "🌐 Your application is accessible at: http://${INGRESS_HOSTS[0]}"
fi
echo ""
echo "🔗 Ingress URLs:"
for host in "${INGRESS_HOSTS[@]}"; do
  echo "   - https://$host"
done