# BASTION01 Deployment Guide

## Prerequisites

1. ✅ Terraform configured with Azure backend
2. ✅ BASTION01 Terraform module created
3. ✅ Ansible playbooks updated
4. ✅ Changes committed to GitHub

## Deployment Steps

### Step 1: Destroy Old ANSIBLE01 (5 minutes)

```bash
cd /home/ayoung/projects/PhoenixStack/terraform/ansible01
terraform destroy -auto-approve
```

**Expected output:** Container 101 destroyed from Proxmox

---

### Step 2: Deploy New BASTION01 Container (5 minutes)

```bash
cd /home/ayoung/projects/PhoenixStack/terraform/bastion01
terraform init  # First time only
terraform plan
terraform apply -auto-approve
```

**Wait 2-3 minutes for container to boot and get IP.**

**Expected output:**
```
Outputs:
bastion01_hostname = "bastion01"
bastion01_ip = "10.101.0.20"
bastion01_vmid = 101
```

---

### Step 3: Configure BASTION01 with Ansible (5 minutes)

```bash
cd /home/ayoung/projects/PhoenixStack

# Test connectivity
ansible -i ansible/inventory/hosts.yml bastion01 -m ping

# Run configuration playbook
ansible-playbook -i ansible/inventory/hosts.yml playbooks/bastion01_base.yml
```

**When prompted:** Enter a secure password for `svc_ansible` user

**Expected output:**
```
PLAY RECAP
bastion01 : ok=XX changed=XX unreachable=0 failed=0
```

---

### Step 4: Verify Installation (2 minutes)

```bash
# SSH to BASTION01
ssh root@bastion01.phoenix.stack

# Verify services installed
ansible --version
git --version
terraform --version
nano --version

# Logout
exit
```

---

## Next: GitHub Actions Runner Setup

Once BASTION01 is running, we'll set up the GitHub Actions self-hosted runner:

1. Generate GitHub runner token
2. SSH to BASTION01
3. Install and register GitHub runner
4. Update GitHub Actions workflow to use self-hosted runner

---

## Rollback (If Needed)

If anything fails:

```bash
# Destroy BASTION01
cd terraform/bastion01
terraform destroy -auto-approve

# Restore ANSIBLE01 (if needed)
cd ../ansible01
terraform apply -auto-approve
```

---

**Ready to proceed with deployment?** Run the steps above and report any errors!
