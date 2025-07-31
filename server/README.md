# 🚀 VPS Auto Deploy

Interactive deployment system for VPS/Ubuntu servers with SSH Deploy Keys, Docker, and Kubernetes.

## 📋 Overview

Deploy any application to your VPS with a single command and interactive configuration:

```bash
./deploy-app.sh configs/my-app-config.sh
```

**Key Features:**
- ✅ **Interactive Menu** - Arrow key navigation for easy setup
- ✅ **SSH Deploy Keys** - Automatic GitHub SSH key management
- ✅ **Auto SSL** - Let's Encrypt certificates with cert-manager
- ✅ **Kubernetes Ready** - MicroK8s for production deployment
- ✅ **Multi-App Support** - Deploy multiple apps on same server
- ✅ **Any Technology** - Works with Node.js, Python, Java, Go, PHP, etc.

## 📦 Requirements

- **OS**: Ubuntu 20.04+ or Debian 11+
- **RAM**: 2GB+ recommended
- **Storage**: 20GB+ available
- **Network**: Internet connection (auto-installs all dependencies)

## 🚀 Quick Start

### 1. Setup

```bash
git clone <your-repo-url>
cd auto-deploy/server
chmod +x deploy-app.sh
```

### 2. Create Config

```bash
cp configs/example-config.sh configs/my-app-config.sh
nano configs/my-app-config.sh
```

**Essential settings:**
```bash
# Server
SERVER_USER="ubuntu"
SERVER_IP="your.server.ip"
SSH_AUTH_METHOD="password"
SSH_PASSWORD="your-password"

# Git Repository
GIT_REPO_URL="https://github.com/username/my-app"
GIT_BRANCH="main"
PROJECT_NAME="my-app"

# Application
CONTAINER_PORT=3000         # Port your app runs on
SERVICE_PORT=80            # Kubernetes service port

# Domain & SSL
INGRESS_HOSTS=("app.domain.com")
CERT_EMAIL="admin@domain.com"

# Environment File
ENV_FILE=".env"
```

### 3. Create Environment File

```bash
nano .env
```

Add your app's environment variables:
```bash
NODE_ENV=production
PORT=3000
API_KEY=your-api-key
# ... other app-specific variables
```

### 4. Deploy

```bash
./deploy-app.sh configs/my-app-config.sh
```

## 🎛️ Interactive Configuration

The script will guide you through:

1. **Database Setup** - MySQL, PostgreSQL, or none
2. **Redis Cache** - Optional caching layer
3. **Resource Limits** - CPU/Memory constraints
4. **HTTPS/SSL** - Automatic certificates
5. **Replicas** - Number of app instances
6. **Kubernetes Mode** - MicroK8s or Kubeadm

## 📊 What Gets Deployed

```
Your VPS Server
├── Docker containerized app
├── Kubernetes orchestration (MicroK8s)
├── Nginx load balancer
├── SSL certificates (auto-renewal)
├── Database (if selected)
├── Redis cache (if selected)
└── Environment variables from ConfigMap
```

## 🔧 Configuration Examples

### Node.js API with Database

**Config:** `api-config.sh`
```bash
SERVER_IP="192.168.1.100"
GIT_REPO_URL="https://github.com/company/api"
PROJECT_NAME="api-backend"
CONTAINER_PORT=3000
INGRESS_HOSTS=("api.company.com")
```

**Interactive selections:**
- Database: MySQL
- Redis: Enable
- HTTPS: Enable
- Replicas: 2

### Static Frontend

**Config:** `frontend-config.sh`
```bash
SERVER_IP="192.168.1.100"
GIT_REPO_URL="https://github.com/company/frontend"
PROJECT_NAME="frontend-app"
CONTAINER_PORT=80
INGRESS_HOSTS=("app.company.com" "www.app.company.com")
```

**Interactive selections:**
- Database: None
- Redis: Disable
- HTTPS: Enable
- Replicas: 3

## 🔐 SSH Authentication

**Option 1: Password (Easy)**
```bash
SSH_AUTH_METHOD="password"
SSH_PASSWORD="your-password"
```

**Option 2: SSH Key (Secure)**
```bash
SSH_AUTH_METHOD="key"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
```

## 📋 Post-Deployment

After successful deployment:

```
🎉 DEPLOYMENT COMPLETE!
✅ App URL: https://app.domain.com
✅ SSL: Auto-renewing with cert-manager
✅ Pods: Running (kubectl get pods)
✅ Logs: kubectl logs -f deployment/my-app
```

## 🔍 Useful Commands

```bash
# Check app status
ssh user@server "microk8s kubectl get pods"

# View logs
ssh user@server "microk8s kubectl logs -f deployment/my-app"

# Restart app
ssh user@server "microk8s kubectl rollout restart deployment/my-app"

# Update deployment
./deploy-app.sh configs/my-app-config.sh
```

## ❓ Troubleshooting

**Pod not starting?**
- Check logs: `kubectl logs pod-name`
- Verify environment variables in ConfigMap
- Ensure Docker image builds correctly

**SSL not working?**
- Wait 2-3 minutes for cert-manager to issue certificate
- Check certificate: `kubectl describe certificate`
- Verify domain DNS points to server IP

**Can't connect to database?**
- Database runs inside Kubernetes cluster
- Use service name as host (e.g., `mysql-service`)
- Check credentials match what you configured

## 📚 Additional Resources

- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [MicroK8s Documentation](https://microk8s.io/docs)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

---

**Need help?** Check the [main documentation](../README.md) or open an issue.