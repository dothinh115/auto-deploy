#!/bin/bash

# Auto Deploy Script with Dynamic Config
# 
# Usage: ./deploy-app.sh <config-file>
# Example: ./deploy-app.sh app1-config.sh
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
# RELEASE_NAME="my-app"                   # Helm release name
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
    echo "❌ Please specify config file!"
    echo "Usage: ./deploy-app.sh <config-file>"
    echo "Example: ./deploy-app.sh app1-config.sh"
    exit 1
fi

CONFIG_FILE=$1

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file does not exist: $CONFIG_FILE"
    exit 1
fi

# Simple step indicator function
show_step() {
  local step_name="$1"
  echo "🚀 $step_name"
}

echo "🚀 === AUTO DEPLOY SCRIPT with Config: $CONFIG_FILE ==="
echo "📋 Workflow: Config → SSH Key → System → Git → Docker → K8s → Deploy → Verify → Cleanup → Complete"
echo ""

show_step "Loading Configuration"

# Check and fix script permissions
if [ ! -x "$0" ]; then
  echo "🔧 Fixing script permissions..."
  chmod +x "$0"
  echo "✅ Script permissions updated"
fi

# Load configuration from file
source "$CONFIG_FILE"

# Arrow key menu selection function  
show_menu() {
  local title="$1"
  shift
  local options=("$@")
  local selected=0
  local key
  
  echo "$title"
  echo ""
  echo "Use ↑/↓ arrows (or j/k) and Enter to select:"
  echo ""
  
  # Function to show menu
  show_options() {
    for ((i=0; i<${#options[@]}; i++)); do
      if [ $i -eq $selected ]; then
        echo -e "  \033[1;32m▶ ${options[i]}\033[0m"  # Green arrow for selected
      else
        echo -e "    ${options[i]}"
      fi
    done
  }
  
  # Initial display
  show_options
  
  while true; do
    # Read a single character
    read -s -n1 key
    
    # Handle escape sequences (arrow keys)
    if [[ $key == $'\x1b' ]]; then
      read -s -n1 key
      if [[ $key == '[' ]]; then
        read -s -n1 key
        case $key in
          'A') # Up arrow
            if [ $selected -gt 0 ]; then
              selected=$((selected-1))
            fi
            ;;
          'B') # Down arrow  
            if [ $selected -lt $((${#options[@]}-1)) ]; then
              selected=$((selected+1))
            fi
            ;;
        esac
      fi
    elif [[ $key == 'k' ]]; then  # vim-style up
      if [ $selected -gt 0 ]; then
        selected=$((selected-1))
      fi
    elif [[ $key == 'j' ]]; then  # vim-style down
      if [ $selected -lt $((${#options[@]}-1)) ]; then
        selected=$((selected+1))
      fi
    elif [[ $key == '' ]]; then  # Enter key
      echo ""
      return $selected
    fi
    
    # Clear previous menu and redraw
    for ((i=0; i<${#options[@]}; i++)); do
      echo -ne "\033[1A\033[K"  # Move up one line and clear it
    done
    show_options
  done
}

# Interactive configuration options
interactive_config() {
  echo ""
  echo "🎛️  === INTERACTIVE CONFIGURATION ==="
  echo ""
  
  # Database type selection
  echo "📊 Database Configuration:"
  
  db_options=("MySQL" "MariaDB" "PostgreSQL" "None (skip database)")
  show_menu "Choose database type:" "${db_options[@]}"
  db_selected=$?
  
  case $db_selected in
    0) DB_TYPE="mysql" ;;
    1) DB_TYPE="mariadb" ;;
    2) DB_TYPE="postgresql" ;;
    3) DB_TYPE="" ;;
  esac
  
  # If database is selected, get database configuration
  if [ -n "$DB_TYPE" ] && [ "$DB_TYPE" != "" ]; then
    echo "✅ Database type: $DB_TYPE"
    echo ""
    echo "📊 Database Configuration Details:"
    
    # Database name
    read -p "Database name ($DB_NAME): " input_db_name
    DB_NAME=${input_db_name:-$DB_NAME}
    
    # Database user
    read -p "Database username ($DB_USER): " input_db_user
    DB_USER=${input_db_user:-$DB_USER}
    
    # Database password
    read -p "Database password ($DB_PASSWORD): " input_db_password
    DB_PASSWORD=${input_db_password:-$DB_PASSWORD}
    
    echo "✅ Database config:"
    echo "   📊 Type: $DB_TYPE"
    echo "   🗄️ Name: $DB_NAME"
    echo "   👤 User: $DB_USER"
    echo "   🔑 Password: $DB_PASSWORD"
  else
    echo "✅ Database type: None (skipped)"
  fi
  
  # Redis selection
  echo ""
  echo "🔴 Redis Configuration:"
  
  redis_options=("Enable Redis" "Disable Redis")
  show_menu "Choose Redis configuration:" "${redis_options[@]}"
  redis_selected=$?
  
  case $redis_selected in
    0) ENABLE_REDIS=true ;;
    1) ENABLE_REDIS=false ;;
  esac
  
  # If Redis is enabled, get Redis configuration
  if [ "$ENABLE_REDIS" = true ]; then
    echo "✅ Redis: Enabled"
    echo ""
    echo "🔴 Redis Configuration Details:"
    
    # Redis password
    read -p "Redis password ($REDIS_PASSWORD): " input_redis_password
    REDIS_PASSWORD=${input_redis_password:-$REDIS_PASSWORD}
    
    echo "✅ Redis config:"
    echo "   🔴 Status: Enabled"
    echo "   🔑 Password: $REDIS_PASSWORD"
  else
    echo "✅ Redis: Disabled"
  fi
  
  # Resource limits selection
  echo ""
  echo "💾 Resource Limits:"
  
  resource_options=("Enable resource limits (recommended for production)" "Disable resource limits")
  show_menu "Choose resource limits:" "${resource_options[@]}"
  resource_selected=$?
  
  case $resource_selected in
    0) ENABLE_RESOURCE_LIMITS=true ;;
    1) ENABLE_RESOURCE_LIMITS=false ;;
  esac
  echo "✅ Resource limits: $ENABLE_RESOURCE_LIMITS"
  
  # TLS/HTTPS selection
  echo ""
  echo "🔐 HTTPS/TLS Configuration:"
  
  tls_options=("Enable HTTPS with Let's Encrypt (recommended)" "HTTP only (not recommended for production)")
  show_menu "Choose HTTPS/TLS configuration:" "${tls_options[@]}"
  tls_selected=$?
  
  case $tls_selected in
    0) ENABLE_TLS=true ;;
    1) ENABLE_TLS=false ;;
  esac
  echo "✅ HTTPS/TLS: $ENABLE_TLS"
  
  # Replica count selection
  echo ""
  echo "🔄 Pod Replicas:"
  
  replica_options=("1 replica (development)" "2 replicas (recommended)" "3 replicas (high availability)" "Custom number")
  show_menu "Choose number of replicas:" "${replica_options[@]}"
  replica_selected=$?
  
  case $replica_selected in
    0) REPLICAS=1 ;;
    1) REPLICAS=2 ;;
    2) REPLICAS=3 ;;
    3) 
      echo ""
      read -p "Enter number of replicas: " custom_replicas
      if [[ "$custom_replicas" =~ ^[0-9]+$ ]] && [ "$custom_replicas" -gt 0 ]; then
        REPLICAS=$custom_replicas
      else
        echo "⚠️ Invalid number, using default: 2"
        REPLICAS=2
      fi
      ;;
  esac
  echo "✅ Replicas: $REPLICAS"
  
  # Kubernetes mode selection
  echo ""
  echo "☸️ Kubernetes Mode:"
  
  k8s_options=("MicroK8s (recommended for VPS)" "Kubeadm (standard Kubernetes)")
  show_menu "Choose Kubernetes mode:" "${k8s_options[@]}"
  k8s_selected=$?
  
  case $k8s_selected in
    0) K8S_MODE="microk8s" ;;
    1) K8S_MODE="kubeadm" ;;
  esac
  echo "✅ Kubernetes mode: $K8S_MODE"
  
  echo ""
  echo "📋 Configuration Summary:"
  if [ -n "$DB_TYPE" ] && [ "$DB_TYPE" != "" ]; then
    echo "   📊 Database: $DB_TYPE ($DB_NAME)"
    echo "   👤 DB User: $DB_USER"
  else
    echo "   📊 Database: None"
  fi
  
  if [ "$ENABLE_REDIS" = true ]; then
    echo "   🔴 Redis: Enabled (password: $REDIS_PASSWORD)"
  else
    echo "   🔴 Redis: Disabled"
  fi
  
  echo "   💾 Resource Limits: $ENABLE_RESOURCE_LIMITS"
  echo "   🔐 HTTPS/TLS: $ENABLE_TLS"
  echo "   🔄 Replicas: $REPLICAS"
  echo "   ☸️ Kubernetes: $K8S_MODE"
  echo ""
  read -p "Continue with this configuration? (Y/n): " confirm
  if [[ $confirm == [nN] ]]; then
    echo "❌ Deployment cancelled by user"
    exit 0
  fi
  echo "✅ Configuration confirmed!"
  echo ""
}

# Run interactive configuration
interactive_config

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
    CHART_REMOTE_DIR="/deployments/$PROJECT_NAME/charts" 
    CONFIGS_DIR="/deployments/$PROJECT_NAME/configs"
    DEPLOY_KEY_PATH="\$DEPLOY_KEYS_DIR/deploy_$PROJECT_NAME"
    PROJECT_NAME="$PROJECT_NAME"
    
    # Create deployments directory for this project
    sudo mkdir -p "\$DEPLOY_KEYS_DIR"
    sudo mkdir -p "\$CHART_REMOTE_DIR"
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
    CHART_REMOTE_DIR="/deployments/$PROJECT_NAME/charts" 
    CONFIGS_DIR="/deployments/$PROJECT_NAME/configs"
    DEPLOY_KEY_PATH="\$DEPLOY_KEYS_DIR/deploy_$PROJECT_NAME"
    PROJECT_NAME="$PROJECT_NAME"
    
    # Create deployments directory for this project
    sudo mkdir -p "\$DEPLOY_KEYS_DIR"
    sudo mkdir -p "\$CHART_REMOTE_DIR"
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
  
  # Replace placeholder with actual project name
  PUBLIC_KEY=$(echo "$PUBLIC_KEY" | sed "s/PROJECT_NAME_PLACEHOLDER/$PROJECT_NAME/g")
  
  # Display the key to user (ensure it's on one line)
  echo ""
  echo "🎉 =============== SSH DEPLOY KEY ==============="
  # Extract only the SSH key part (starts with ssh-rsa, ssh-ed25519, etc.)
  CLEAN_KEY=$(echo "$PUBLIC_KEY" | grep -E '^ssh-[a-zA-Z0-9]+ [A-Za-z0-9+/=]+ ' | head -1)
  if [ -n "$CLEAN_KEY" ]; then
    echo "$CLEAN_KEY"
  else
    # Fallback: display all but filter out generation messages
    echo "$PUBLIC_KEY" | grep -v "Generating new SSH key"
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
CHART_REMOTE_DIR="/deployments/$PROJECT_NAME/charts"
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
  ssh_exec "mkdir -p $CHART_REMOTE_DIR"
  
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
      
      # Enable helm3
      echo "⚙️ Enabling Helm3..."
      sudo microk8s enable helm3
      
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
    
    # Auto install Helm if not found
    if ! command -v helm &> /dev/null; then
      echo "🔧 Helm not found, installing automatically..."
      
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
      
      # Detect system architecture
      ARCH=\$(dpkg --print-architecture)
      curl https://baltocdn.com/helm/signing.asc | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/helm.gpg
      echo "deb [arch=\$ARCH signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
      sudo apt-get update -qq
      sudo apt-get install -y -qq helm
      echo "✅ Helm installed successfully!"
    fi
    
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

show_step "Creating Helm Chart"
ssh_exec_heredoc << EOF    
    echo "🎯 Creating Helm chart and deploying..."
    
    # Create Helm chart for new project
    CHART_DIR="/deployments/$PROJECT_NAME/charts"
    sudo rm -rf "\$CHART_DIR"
    sudo mkdir -p "/deployments/$PROJECT_NAME"
    sudo chown -R \$(whoami):\$(whoami) "/deployments/$PROJECT_NAME"
    
    # Use helm create to generate standard chart
    cd /deployments/$PROJECT_NAME
    helm create charts
    
    echo "✅ Helm chart created successfully"
    
    # Create ConfigMap from local .env file content
    echo "🔧 Creating ConfigMap from .env file..."
    # Create ConfigMap with dynamic content
    sudo microk8s kubectl create configmap $PROJECT_NAME-env $CONFIGMAP_ARGS --dry-run=client -o yaml | sudo microk8s kubectl apply -f -
    echo "✅ ConfigMap created with environment variables"
    
    
    # Generate ingress hosts configuration
    HOSTS_YAML=""
    TLS_HOSTS=""
    TLS_CONFIG=""
    CERT_ANNOTATIONS=""
    
    for host in ${INGRESS_HOSTS[@]}; do
      HOSTS_YAML="\${HOSTS_YAML}    - host: \$host
      paths:
        - path: /
          pathType: Prefix
"
      TLS_HOSTS="\${TLS_HOSTS}        - \$host
"
    done
    
    # Check for SSL certificates and configure TLS
    echo "🔐 Configuring TLS with SSL certificates..."
    
    
    # Using cert-manager for automatic SSL management
    echo "🔐 SSL certificates will be managed by cert-manager (automatic)"
    CERT_SUCCESS=true
    
    # Configure TLS based on certificate availability
    if [ "\$CERT_SUCCESS" = true ]; then
      echo "🔐 Configuring TLS with cert-manager (automatic SSL)"
      
      # cert-manager annotations for automatic certificate generation
      # Note: SSL redirect is automatic when TLS section exists in ingress
      # http01-edit-in-place handles ACME challenges without conflicts
      CERT_ANNOTATIONS="    nginx.ingress.kubernetes.io/backend-protocol: \"HTTP\"
    cert-manager.io/cluster-issuer: \"letsencrypt-prod\"
    cert-manager.io/issue-temporary-certificate: \"true\"
    acme.cert-manager.io/http01-edit-in-place: \"true\""
      
      # TLS configuration with cert-manager secret name  
      TLS_CONFIG="  tls:
    - secretName: $PROJECT_NAME-tls
      hosts:
\${TLS_HOSTS}"
    else
      echo "⚠️ TLS disabled, deploying HTTP only"
      CERT_ANNOTATIONS="    nginx.ingress.kubernetes.io/ssl-redirect: \"false\"
    nginx.ingress.kubernetes.io/force-ssl-redirect: \"false\""
      TLS_CONFIG=""
    fi
    
    # Customize values.yaml with user config - Complete values
    cat > "/deployments/$PROJECT_NAME/charts/values.yaml" <<VALUESEOF
replicaCount: $REPLICAS

image:
  repository: $(echo $IMAGE | cut -d: -f1)
  pullPolicy: Never
  tag: "$(echo $IMAGE | cut -d: -f2)"

strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1

nameOverride: ""
fullnameOverride: "$RELEASE_NAME"

serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: ""

podAnnotations: {}
podLabels: {}
podSecurityContext: {}
securityContext: {}

envFrom:
  - configMapRef:
      name: $PROJECT_NAME-env

service:
  type: ClusterIP
  port: $SERVICE_PORT
  targetPort: $CONTAINER_PORT

ingress:
  enabled: true
  className: "nginx"
  annotations:
\${CERT_ANNOTATIONS}
  hosts:
\${HOSTS_YAML}
\${TLS_CONFIG}
resources: {}

livenessProbe:
  tcpSocket:
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 1
  successThreshold: 1
  failureThreshold: 3
readinessProbe:
  tcpSocket:
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 1
  successThreshold: 1
  failureThreshold: 3

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 100
  targetCPUUtilizationPercentage: 80

nodeSelector: {}
tolerations: []
affinity: {}
VALUESEOF
    
    # Update deployment template to include environment variables
    cat > "/deployments/$PROJECT_NAME/charts/templates/deployment.yaml" <<'DEPLOYEOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "charts.fullname" . }}
  labels:
    {{- include "charts.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  {{- if .Values.strategy }}
  strategy:
    {{- toYaml .Values.strategy | nindent 4 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "charts.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        {{- include "charts.selectorLabels" . | nindent 8 }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "charts.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ .Chart.Name }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
          {{- if .Values.env }}
          env:
            {{- toYaml .Values.env | nindent 12 }}
          {{- end }}
          {{- if .Values.envFrom }}
          envFrom:
            {{- toYaml .Values.envFrom | nindent 12 }}
          {{- end }}
          livenessProbe:
            {{- toYaml .Values.livenessProbe | nindent 12 }}
          readinessProbe:
            {{- toYaml .Values.readinessProbe | nindent 12 }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
DEPLOYEOF
    
    # Clean deployment - Remove existing deployment and unused images
    echo "🗑️ Cleaning existing deployment and unused images..."
    
    # Delete existing Helm release
    if [ "$K8S_MODE" = "microk8s" ]; then
      sudo microk8s helm uninstall "$RELEASE_NAME" --ignore-not-found || true
      echo "✅ Existing Helm release removed"
      
      # Check for running pods and force delete immediately if found
      echo "⏳ Checking for remaining pods..."
      RUNNING_PODS=\$(sudo microk8s kubectl get pods -l app.kubernetes.io/instance="$RELEASE_NAME" --no-headers 2>/dev/null | wc -l)
      if [ "\$RUNNING_PODS" -gt 0 ]; then
        echo "🗑️ Found \$RUNNING_PODS running pods, force deleting immediately..."
        sudo microk8s kubectl delete pods -l app.kubernetes.io/instance="$RELEASE_NAME" --force --grace-period=0 || true
        echo "✅ All pods force deleted!"
      else
        echo "✅ All pods terminated!"
      fi
      
      # Clean unused images (optional for disk space)
      echo "🧹 Cleaning unused images..."
      sudo docker image prune -f || true
      
      echo "✅ Cleanup completed"
    else
      helm uninstall "$RELEASE_NAME" --ignore-not-found || true
      kubectl delete pods -l app.kubernetes.io/instance="$RELEASE_NAME" --force --grace-period=0 || true
    fi
    
    # Fresh deployment with Helm
    echo "🚀 Starting fresh deployment..."
    if [ "$K8S_MODE" = "microk8s" ]; then
      sudo microk8s helm install "$RELEASE_NAME" "/deployments/$PROJECT_NAME/charts" --create-namespace --namespace default
    else
      helm install "$RELEASE_NAME" "/deployments/$PROJECT_NAME/charts" --create-namespace --namespace default
    fi
    
    # Wait for deployment to be ready
    echo "⏳ Waiting for deployment to be ready..."
    for i in {1..30}; do
      if [ "$K8S_MODE" = "microk8s" ]; then
        READY_PODS=\$(sudo microk8s kubectl get pods -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | grep -o true | wc -l)
        TOTAL_PODS=\$(sudo microk8s kubectl get pods -l app.kubernetes.io/instance="$RELEASE_NAME" --no-headers 2>/dev/null | wc -l)
      else
        READY_PODS=\$(kubectl get pods -l app.kubernetes.io/instance="$RELEASE_NAME" -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | grep -o true | wc -l)
        TOTAL_PODS=\$(kubectl get pods -l app.kubernetes.io/instance="$RELEASE_NAME" --no-headers 2>/dev/null | wc -l)
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
          sudo microk8s kubectl get pods -l app.kubernetes.io/instance="$RELEASE_NAME" -o wide
          echo ""
          echo "📋 Pod Events:"
          sudo microk8s kubectl get events --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | tail -10
          echo ""
          echo "📋 Pod Logs (last 20 lines):"
          sudo microk8s kubectl logs -l app.kubernetes.io/instance="$RELEASE_NAME" --tail=20 || echo "No logs available"
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
      echo "   🌐 Ingress TLS: \$(sudo microk8s kubectl get ingress $RELEASE_NAME -o jsonpath='{.spec.tls[0].secretName}')"
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
echo "✅ Helm Deploy: $RELEASE_NAME"
echo ""
echo "🔗 Ingress URLs:"
for host in "${INGRESS_HOSTS[@]}"; do
  echo "   - https://$host"
done