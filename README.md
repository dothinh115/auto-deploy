# 🚀 Auto Deploy System

One-command deployment system for modern applications with automatic SSL, Kubernetes, and database setup.

## ✨ What is it?

Deploy any application to your VPS in minutes with a single command. Auto Deploy handles everything - from server setup to SSL certificates.

```bash
./deploy-app.sh configs/my-app-config.sh
```

## 🎯 Key Features

- **⚡ One-Command Deploy** - No complex configurations
- **🔐 Automatic SSL** - HTTPS with Let's Encrypt
- **☸️ Kubernetes Ready** - Production-grade orchestration
- **🗄️ Database Setup** - MySQL/PostgreSQL/Redis auto-config
- **📦 Any Technology** - Node.js, Python, Java, Go, PHP, etc.
- **🔄 Multi-App Support** - Deploy multiple apps on one server

## 🚀 Quick Start

### 1. Setup
```bash
git clone <your-repo-url>
cd auto-deploy/server
chmod +x deploy-app.sh
```

### 2. Configure
```bash
cp configs/example-config.sh configs/my-app-config.sh
nano configs/my-app-config.sh  # Add your server IP & GitHub repo
```

### 3. Deploy
```bash
./deploy-app.sh configs/my-app-config.sh
```

That's it! Your app is now live with HTTPS, database, and auto-scaling.

## 📋 What Gets Deployed

- ✅ Docker containerized application
- ✅ Kubernetes orchestration (MicroK8s)
- ✅ Nginx load balancer
- ✅ SSL certificates (cert-manager)
- ✅ Database (MySQL/PostgreSQL)
- ✅ Redis caching (optional)
- ✅ Environment variables management

## 🛠️ Supported Technologies

**Languages**: Node.js, Python, Java, Go, PHP, Ruby, .NET  
**Databases**: MySQL, PostgreSQL, MariaDB, Redis  
**Platforms**: DigitalOcean, Linode, AWS EC2, any Ubuntu/Debian VPS

## 📚 Documentation

- **[Complete Guide](server/README.md)** - Detailed setup and configuration
- **[Config Examples](server/configs/)** - Real-world configurations
- **[Troubleshooting](server/README.md#troubleshooting)** - Common issues

## 📄 License

MIT License - Free for personal and commercial use.

---

**Deploy with confidence. Scale with ease.** 🚀