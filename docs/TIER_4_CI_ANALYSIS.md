# Tier 4: Advanced Automation - Detailed Analysis

**Status**: Research & Planning Phase
**Decision Required**: Choose CI/CD platform based on learning goals and use cases
**Timeline**: After Tier 1-3 stabilization (estimated Week 8+)

---

## Overview

Tier 4 adds advanced automation capabilities to PhoenixStack. Unlike Tier 1-3 which focus on observability, security, and resilience, Tier 4 focuses on **automation, CI/CD, and development workflow**.

> **Note**: Tier 4 is optional. Only deploy if you have specific CI/CD workflows or learning objectives.

---

## Tier 4 Options Analysis

### Option 1: Local CI Runner (Recommended for Most Homelabs)

**What**: Jenkins or GitLab Runner instance running locally in your infrastructure

**Architecture**:
```
CI01 Container
├── Jenkins OR GitLab Runner agent
├── Docker-in-Docker for build artifacts
├── Integration with GitHub/GitLab
└── State stored on local SSD
```

**Pros**:
- **Cost**: Free (Jenkins) or free agent model (GitLab)
- **Control**: Complete control over build environment
- **Learning**: Understand CI/CD pipelines, build automation, artifact management
- **Integration**: Webhooks from GitHub trigger builds automatically
- **Custom**: Can run any custom build scripts, not limited to hosted CI features
- **Security**: Builds stay on your local infrastructure
- **Speed**: No network latency to hosted CI (faster builds for large artifacts)

**Cons**:
- **Maintenance**: Must maintain the CI system yourself
- **Reliability**: Single point of failure if CI01 goes down (add BACKUP01 snapshots)
- **Scalability**: Limited to CI01 resources; cannot easily scale agents
- **Complexity**: Requires learning Jenkins/GitLab configuration

**Use Cases**:
- Building Docker images for DOCKER01/02
- Running tests on your Terraform configuration
- Deploying to Authentik, Vault, or other services
- Building custom applications
- Automating Ansible playbook execution

**Recommended Setup**: Jenkins (simpler, more tutorials for beginners)

---

### Option 2: Kubernetes-Style Runners (Advanced)

**What**: Use Kubernetes or similar orchestration for dynamic build agents

**Architecture**:
```
K8S Cluster (future, not in scope)
├── Control plane
├── Multiple worker nodes
└── Jenkins/GitLab agents spawn as pods
```

**Pros**:
- **Scalability**: Agents spin up/down dynamically based on workload
- **Efficiency**: Resources released after builds complete
- **Isolation**: Each build runs in isolated container
- **Learning**: Understand Kubernetes, container orchestration

**Cons**:
- **Complexity**: High overhead for homelab (requires 3-5 additional containers minimum)
- **Resource Intensive**: Kubernetes is heavy for single-node deployments
- **Overkill**: For most homelabs, unnecessary complexity

**When to Consider**: After mastering Docker and wanting to learn Kubernetes

---

### Option 3: GitHub Actions Self-Hosted Runners (Already Using)

**What**: You're already using this! GitHub runners on BASTION01/02

**Current State**:
- ✅ Two GitHub-hosted runners on BASTION containers
- ✅ Workflows execute on your infrastructure
- ✅ Free for GitHub repos

**Why Tier 4 CI Complements This**:
- GitHub Actions is great for **public repos** and **standard workflows**
- Local CI (Jenkins) is great for **private builds**, **custom tools**, **faster iteration**
- They work together: GitHub Actions for CI gates, local runner for advanced testing

---

### Option 4: Drone CI (Modern, Lightweight)

**What**: Container-native CI platform focused on simplicity

**Architecture**:
```
CI01 Container
├── Drone Server (web UI, configuration)
├── Drone Runner (Docker)
└── Integrates with GitHub/GitLab webhooks
```

**Pros**:
- **Lightweight**: ~200MB footprint, runs in single container
- **Cloud-Native**: Native Docker/Kubernetes support
- **Simple Config**: Single YAML file per project (like GitHub Actions)
- **Multi-Runner**: Can add additional runners as containers scale
- **Learning**: Modern CI/CD patterns, Kubernetes-ready

**Cons**:
- **Smaller Community**: Less Stack Overflow help than Jenkins
- **Limited Plugins**: Fewer integrations than Jenkins
- **Less Familiar**: If you've never used Drone before

**Use Case**: If you want "GitHub Actions, but locally"

---

## Comparison Matrix

| Feature | Jenkins | GitLab Runner | Drone | K8S |
|---------|---------|---------------|-------|-----|
| **Setup Difficulty** | Medium | Low | Low | Very High |
| **Learning Curve** | Medium | Low | Low | Very High |
| **Resource Usage** | Medium (1-2GB) | Low (512MB) | Very Low (200MB) | Very High (3GB+) |
| **Community/Docs** | Excellent | Good | Good | Excellent |
| **Enterprise Features** | Yes | Yes | Limited | N/A |
| **Cost** | Free | Free | Free | Free |
| **Best For** | Complex workflows | DevOps teams | Simple builds | Production k8s |

---

## Recommended Path for Your Homelab

### Phase 1: GitHub Actions (Current) ✅
You're already using this on BASTION01/02. Perfect for:
- Running tests
- Deploying to your infrastructure
- Automating GitHub workflows

### Phase 2: Local Jenkins (Recommended Next)
Adds capability for:
- Building Docker images for DOCKER01/02
- Custom build scripts (not limited to GitHub Actions format)
- **Learning Jenkins, a standard enterprise tool**

**Infrastructure**:
```
CI01 Container (VMID 121, 10.101.0.121)
├── Jenkins Server (8080)
├── Plugins: GitHub, Docker, Ansible, Terraform
└── Can execute on BASTION01/02 runners via SSH
```

### Phase 3: Optional Advanced Options
After mastering Tier 1-3 and Jenkins:
- **Loki**: Log aggregation for all CI builds
- **Artifact Repository**: Nexus or Artifactory for build artifacts
- **Container Registry**: Local Docker Registry for images
- **Git Server**: Gitea for self-hosted Git repositories

---

## Tier 4 Deployment Roadmap (If Chosen)

### Week 1: Deploy CI01 & Jenkins Setup
```bash
# Deploy CI01 container
terraform apply -target=module.ci01

# Post-deployment: Install Jenkins
ssh root@10.101.0.121
apt update && apt install -y jenkins

# Configure Jenkins
# - Create admin user
# - Add GitHub integration
# - Set up Docker plugin
```

**Skills to Learn**:
- Jenkins UI navigation
- Job creation and configuration
- Pipeline-as-code (Jenkinsfile syntax)
- GitHub webhook integration

### Week 2: Integrate with Your Services
```bash
# Create Jenkins jobs for:
1. GitHub repo tests
2. Docker image builds for DOCKER01/02
3. Ansible playbook execution
4. Terraform plan/apply automation
```

### Week 3+: Expand & Optimize
- Add distributed agents (can run agents on BASTION01/02)
- Set up artifact repository
- Integrate with MONITOR01 for build metrics
- Add Vault integration for secrets

---

## Learning Value: Why Tier 4?

### What You'll Learn

**Jenkins / CI/CD Fundamentals**:
- How continuous integration pipelines work
- Build automation and testing strategies
- Artifact management and versioning
- Webhook integration patterns

**DevOps Best Practices**:
- Infrastructure-as-Code automation (Terraform via Jenkins)
- Container build workflows (Docker in CI)
- Configuration management (Ansible via Jenkins)
- Secret management in CI (Vault integration)

**Advanced Topics** (after mastering basics):
- Multi-stage pipelines
- Distributed build agents
- Build caching and optimization
- Compliance and audit logging

**Practical Skills**:
- Writing Jenkinsfile (Jenkins DSL)
- Debugging failed builds
- Performance tuning
- Security in CI/CD

### Real-World Application

**Your Company's Use of Vault + CI**:
- Most organizations use **Vault in CI pipelines**
- CI jobs authenticate to Vault for secrets
- Builds inject secrets into containers
- Audit trail of all secret access

**By Building This**:
- You'll deeply understand how your company does CI/CD
- You can troubleshoot production CI issues
- You'll have hands-on experience with enterprise patterns
- Direct transfer of knowledge to your work

---

## Decision Framework

**Choose Jenkins if**:
- You want the most flexible, powerful CI system
- You need to learn a tool used in most enterprises
- You have complex build workflows
- You want 100s of plugins for integration

**Choose Drone if**:
- You prefer modern, container-native tools
- You want simplicity over power
- You like YAML-based config (like GitHub Actions)
- You're interested in Kubernetes eventually

**Choose GitLab Runner if**:
- You run a self-hosted GitLab instance (you don't)
- You prefer GitLab's opinionated platform

**Skip Tier 4 (for now) if**:
- You're happy with GitHub Actions
- You want to focus on core infrastructure (Tier 1-3)
- You have limited compute capacity
- You want to master Vault/monitoring first

---

## Resource Estimation for Tier 4

### Single CI01 Container
- **VMID**: 121
- **IP**: 10.101.0.121
- **CPU**: 2 cores
- **RAM**: 2GB (Jenkins needs memory for plugin compilation)
- **Storage**: 20GB (build artifacts, logs)
- **Total Cost**: 20% additional resource overhead

### With CI Scaling (Optional)
If you add multiple CI runners on other containers:
- **BASTION01/02**: Already have GitHub runners, can add Jenkins agents
- **DOCKER01/02**: Can run build jobs natively
- **Additional Containers**: CI02 (VMID 122) for distributed builds

---

## Next Steps

### Before Deciding
1. Review how **your company uses CI/CD** and what tools they use
2. Check if mastering **Tier 1-3 first** aligns with your learning plan
3. Determine if you have **time and compute capacity** for Tier 4

### If You Choose Jenkins
1. Create `terraform/ci01/` directory and variables
2. Deploy CI01 container
3. Install and configure Jenkins
4. Create first build pipeline for Docker image build
5. Integrate GitHub webhook for automatic triggers

### Recommended Timeline
- **Tier 1**: This week (MONITOR01/02)
- **Tier 2**: Next week (VAULT01/02)
- **Tier 3**: Week after (BACKUP01)
- **Stabilization**: 2-3 weeks (tune, test, troubleshoot)
- **Tier 4**: Weeks 6-8+ (when Tier 1-3 are stable)

---

## Final Recommendation

**For your learning path** given that your company uses Vault heavily:

1. **Deploy Tier 1-3 first** (Observability, Vault, Backups)
2. **Master Vault** by integrating it into your infrastructure
3. **Then add Tier 4 CI** to see Vault integration in real CI/CD pipelines
4. **Practice secret rotation and audit** using both Vault and CI

This progression teaches you the **full DevOps stack** in the right order: infrastructure → observability → security (Vault) → automation (CI/CD).

Would you like me to create `terraform/ci01/` configurations for Jenkins, or would you prefer to finalize Tier 1-3 deployment first?
