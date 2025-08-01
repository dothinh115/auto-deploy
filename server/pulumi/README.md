# 🚀 Pulumi Infrastructure for Auto-Deploy

This directory contains Pulumi infrastructure code that can replace Helm charts for deploying applications to Kubernetes.

## 📋 Overview

Pulumi provides infrastructure as code using real programming languages (TypeScript in this case), offering:

- **Type Safety** - Catch errors at compile time
- **Better IDE Support** - Autocomplete, refactoring, etc.
- **Programmatic Control** - Loops, conditions, functions
- **State Management** - Built-in state tracking
- **CI/CD Friendly** - Easy automation with secrets management

## 🚀 Quick Start

### 1. Install Pulumi

```bash
# macOS
brew install pulumi

# Linux
curl -fsSL https://get.pulumi.com | sh
```

### 2. Install Dependencies

```bash
cd server/pulumi
npm install
```

### 3. Configure Stack

```bash
# Create a new stack (e.g., dev, staging, prod)
pulumi stack init dev

# Set configuration values
pulumi config set projectName my-app
pulumi config set appName my-app
pulumi config set image my-app:latest
pulumi config set ingressHosts '["app.domain.com", "www.app.domain.com"]'
pulumi config set certEmail admin@domain.com
```

### 4. Deploy

```bash
# Preview changes
pulumi preview

# Deploy
pulumi up
```

## 📊 Configuration

All configuration is managed through Pulumi config:

```bash
# Required configuration
pulumi config set projectName <project-name>
pulumi config set appName <app-name>
pulumi config set image <docker-image:tag>
pulumi config set ingressHosts <json-array-of-hosts>

# Optional configuration
pulumi config set replicas 2
pulumi config set containerPort 3000
pulumi config set servicePort 80
pulumi config set enableTls true
pulumi config set certEmail admin@domain.com
pulumi config set enableResourceLimits false
pulumi config set cpuRequest 250m
pulumi config set cpuLimit 500m
pulumi config set memoryRequest 256Mi
pulumi config set memoryLimit 512Mi
pulumi config set envConfigMap <configmap-name>
```

## 🔄 Migration from Helm

To migrate from the existing Helm deployment:

1. **Export current values** from Helm deployment
2. **Set Pulumi config** with same values
3. **Preview deployment** to verify resources
4. **Deploy with Pulumi** (may need to import existing resources)

### Import Existing Resources

```bash
# Import existing deployment
pulumi import kubernetes:apps/v1:Deployment my-app-deployment default/my-app

# Import existing service
pulumi import kubernetes:core/v1:Service my-app-service default/my-app

# Import existing ingress
pulumi import kubernetes:networking.k8s.io/v1:Ingress my-app-ingress default/my-app
```

## 📁 Project Structure

```
pulumi/
├── index.ts                    # Main entry point
├── components/
│   ├── deployment.ts          # Deployment resource
│   ├── service.ts            # Service resource
│   ├── ingress.ts            # Ingress with SSL
│   └── configmap.ts          # ConfigMap helper
├── Pulumi.yaml               # Project configuration
├── Pulumi.dev.yaml           # Dev stack example
├── package.json              # Node dependencies
└── tsconfig.json             # TypeScript config
```

## 🔍 Common Commands

```bash
# View current stack
pulumi stack

# List all stacks
pulumi stack ls

# Switch stack
pulumi stack select <stack-name>

# View outputs
pulumi stack output

# Destroy resources
pulumi destroy

# View logs
pulumi logs -f
```

## 🔧 CI/CD Integration

### GitHub Actions Example

```yaml
- name: Deploy with Pulumi
  uses: pulumi/actions@v3
  with:
    command: up
    stack-name: production
  env:
    PULUMI_ACCESS_TOKEN: ${{ secrets.PULUMI_ACCESS_TOKEN }}
```

### Environment Variables

```bash
# Set Pulumi access token for CI/CD
export PULUMI_ACCESS_TOKEN="pul-xxxxxxxxxxxx"

# Set kubeconfig for Kubernetes access
export KUBECONFIG=/path/to/kubeconfig
```

## 📋 Benefits over Helm

1. **Type Safety** - Catch configuration errors early
2. **Better Conditionals** - Real if/else instead of templates
3. **Reusable Components** - Import and share code
4. **State Management** - Track infrastructure changes
5. **Multi-Cloud** - Same code for different clouds
6. **Secrets Management** - Built-in encryption

## 🆘 Troubleshooting

**Stack already exists error?**
```bash
pulumi stack select <stack-name>
```

**Resource already exists?**
Import the existing resource or delete it first.

**Configuration not found?**
Ensure you've set all required config values.

**Authentication issues?**
Check KUBECONFIG and Pulumi access token.