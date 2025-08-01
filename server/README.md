# 🚀 VPS Auto Deploy

Fully automated deployment system for VPS/Ubuntu servers with YAML configuration, Pulumi, Docker, and Kubernetes.

## 📋 Overview

Deploy any application to your VPS with a single command and YAML configuration:

```bash
./ezdeploy.sh configs/my-app-config.yaml
```

**Key Features:**
- ✅ **YAML Configuration** - Simple, structured config files with full documentation
- ✅ **Zero Interaction** - Fully automated deployment, perfect for CI/CD
- ✅ **Pulumi IaC** - Infrastructure as Code for better CI/CD integration
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
chmod +x ezdeploy.sh
```

### 2. Create Config

```bash
cp configs/example-config.yaml configs/my-app-config.yaml
nano configs/my-app-config.yaml
```

**Essential settings:**
```yaml
version: "1.0"

server:
  user: ubuntu
  ip: your.server.ip
  ssh:
    method: password
    password: "your-password"

repository:
  url: https://github.com/username/my-app
  branch: main

application:
  name: my-app
  directory: /apps
  image:
    name: my-app
    tag: latest

kubernetes:
  provider: microk8s
  deployment:
    port: 3000
    replicas: 2
  resources:
    limits:
      enabled: false

ingress:
  hosts:
    - app.domain.com
  tls:
    email: admin@domain.com

environment:
  file: .env
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
./ezdeploy.sh configs/my-app-config.yaml
```

## 📋 YAML Configuration

All configuration is done through YAML files with full documentation:

1. **Database Setup** - MySQL, PostgreSQL, or disable
2. **Redis Cache** - Enable/disable caching layer
3. **Resource Limits** - CPU/Memory constraints configuration
4. **HTTPS/SSL** - Automatic Let's Encrypt certificates
5. **Replicas** - Number of app instances (1-10+)
6. **Kubernetes Mode** - MicroK8s or Kubeadm
7. **Complete Documentation** - Every field explained with examples

## 📊 What Gets Deployed

```
Your VPS Server
├── Docker containerized app
├── Kubernetes orchestration (MicroK8s)
├── Pulumi infrastructure management
├── Nginx ingress controller
├── SSL certificates (auto-renewal with cert-manager)
├── Database (if selected)
├── Redis cache (if selected)
└── Environment variables from ConfigMap
```

## 🔧 Configuration Examples

### Node.js API with Database

**Config:** `api-config.yaml`
```yaml
server:
  ip: 192.168.1.100
repository:
  url: https://github.com/company/api
application:
  name: api-backend
kubernetes:
  deployment:
    port: 3000
ingress:
  hosts:
    - api.company.com
```

**Interactive selections:**
- Database: MySQL
- Redis: Enable
- HTTPS: Enable
- Replicas: 2

### Static Frontend

**Config:** `frontend-config.yaml`
```yaml
server:
  ip: 192.168.1.100
repository:
  url: https://github.com/company/frontend
application:
  name: frontend-app
kubernetes:
  deployment:
    port: 80
ingress:
  hosts:
    - app.company.com
    - www.app.company.com
```

**Interactive selections:**
- Database: None
- Redis: Disable
- HTTPS: Enable
- Replicas: 3

## 🔐 SSH Authentication

**Option 1: Password (Easy)**
```yaml
server:
  ssh:
    method: password
    password: "your-password"
```

**Option 2: SSH Key (Secure)**
```yaml
server:
  ssh:
    method: key
    key_path: ~/.ssh/id_rsa
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
ssh user@server "microk8s kubectl logs -f deployment/my-app-deployment"

# Restart app
ssh user@server "microk8s kubectl rollout restart deployment/my-app-deployment"

# Check Pulumi stack status
ssh user@server "cd /deployments/my-app && pulumi stack"

# View Pulumi outputs
ssh user@server "cd /deployments/my-app && pulumi stack output"

# Update deployment
./ezdeploy.sh configs/my-app-config.yaml
```

## ❓ Troubleshooting

**Pod not starting?**
- Check logs: `kubectl logs pod-name`
- Verify environment variables in ConfigMap
- Ensure Docker image builds correctly
- Check resource limits if getting OOM kills (exit code 137)

**SSL not working?**
- Wait 2-3 minutes for cert-manager to issue certificate
- Check certificate: `kubectl describe certificate app-name-tls`
- Verify domain DNS points to server IP
- Check for Let's Encrypt rate limits (5 certificates per week per domain)

**Can't connect to database?**
- Database runs inside Kubernetes cluster
- Use service name as host (e.g., `mysql-service`)
- Check credentials match what you configured

**Pulumi deployment failed?**
- Check Pulumi state: `pulumi stack`
- View detailed errors: `pulumi stack export`
- Clear conflicts: Script automatically handles cleanup and retry

## 📚 Additional Resources

- [Pulumi Documentation](https://www.pulumi.com/docs/)
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [MicroK8s Documentation](https://microk8s.io/docs)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [cert-manager Documentation](https://cert-manager.io/docs/)

---

**Need help?** Check the [main documentation](../README.md) or open an issue.