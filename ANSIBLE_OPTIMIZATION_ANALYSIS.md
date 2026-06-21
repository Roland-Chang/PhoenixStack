# ANSIBLE PLAYBOOK OPTIMIZATION ANALYSIS

**Date**: 2026-06-17  
**Issue**: Base configuration tasks run sequentially for each host (slow)  
**Goal**: Consolidate common base tasks to run once for all hosts (fast)

---

## 📊 Current Execution Flow

```
BASTION01
├─ base_config (APT mirrors, dpkg lock, update cache, upgrade packages)
├─ 1Password CLI
└─ GitHub Runner

↓ (wait for bastion01 to complete)

DNS01
├─ base_config (APT mirrors, dpkg lock, update cache, upgrade packages)  ← REDUNDANT
├─ PiHole

↓ (wait for dns01 to complete)

DNS02
├─ base_config (APT mirrors, dpkg lock, update cache, upgrade packages)  ← REDUNDANT
└─ PiHole

... and so on for 14+ VMs
```

**Problem**: Each VM runs the entire `base_config` role individually, wasting time on:
- APT mirror configuration (same for all)
- dpkg lock clearing (sequential, not parallel)
- APT cache updates (sequential, not parallel)
- Package upgrades (sequential, not parallel)

**Impact**: Deployment time = ~5-10 min per VM × 16 VMs = 80-160 minutes

---

## ✅ Optimized Execution Flow (3 Options)

### OPTION 1: Unified Base Phase + Parallel Service Phases (RECOMMENDED)

```
PHASE 0: BASE CONFIGURATION (Run Once for All Hosts - Parallel)
├─ bastion01  [base_config]
├─ bastion02  [base_config]  ← All run in parallel!
├─ dns01      [base_config]
├─ dns02      [base_config]
├─ proxy01    [base_config]
├─ proxy02    [base_config]
├─ authentik01 [base_config]
├─ authentik02 [base_config]
├─ docker01   [base_config]
├─ docker02   [base_config]
├─ plex01     [base_config]
├─ plex02     [base_config]
├─ amp01      [base_config]
├─ amp02      [base_config]
├─ pgsql01    [base_config]
└─ pgsql02    [base_config]  ← All complete ~5-10 min (not 80-160 min!)

↓ (wait for all base_config to complete)

PHASE 1: SERVICE-SPECIFIC SETUP (Sequential or Grouped)
├─ Bastion Phase (1Password, GitHub Runner)
├─ DNS Phase (PiHole)
├─ Proxy Phase (Traefik)
├─ Authentik Phase
├─ Docker Phase
├─ Plex Phase
├─ AMP Phase
└─ PostgreSQL Phase
```

**Time Savings**: 80-160 min → ~20-30 min (75% faster!)

---

### OPTION 2: Split Playbooks

**site-phase0-base.yml** - Run once for all hosts
```yaml
- name: "PHASE 0: Base Configuration for All Hosts"
  hosts: all
  roles:
    - base_config
```

**site-phase1-services.yml** - Run service-specific roles
```yaml
- name: "PHASE 1: Bastion Services"
  import_playbook: bastion_full_setup.yml

- name: "PHASE 2: DNS Services"
  import_playbook: dns_base.yml
  
... etc
```

---

### OPTION 3: Unified site.yml with Smart Grouping

Refactor site.yml to:
1. First play: All hosts in parallel (base_config only)
2. Subsequent plays: Service-specific roles

---

## 📋 Recommended Approach: OPTION 1

**Implementation Steps**:

1. **Add base configuration phase** at the top of site.yml
   ```yaml
   - name: "PHASE 0: Base Configuration for All Hosts"
     hosts: all
     import_playbook: common_base_setup.yml
   ```

2. **Create common_base_setup.yml**
   ```yaml
   - name: "Common Base Configuration"
     hosts: all
     roles:
       - base_config
   ```

3. **Keep service playbooks as-is** (bastion_full_setup.yml, dns_base.yml, etc.)
   - They'll now skip base_config since it already ran
   - Or wrap base_config in conditional tags

4. **Adjust tags** to support:
   - `--tags base` - Only base config phase
   - `--tags services` - Only service-specific phases
   - `--tags all` - Full deployment

---

## 🔧 Configuration Options

### For Parallel Execution
Add to site.yml:
```yaml
[defaults]
strategy = free  # Or 'linear' for sequential
forks = 16       # Run 16 hosts in parallel (adjust as needed)
```

In ansible.cfg:
```ini
[defaults]
strategy_plugins = /usr/share/ansible/plugins/strategy
strategy = free
forks = 16
```

### To Skip Re-running Base Config
Tag the base_config role:
```yaml
- role: base_config
  tags:
    - base
    - always  # Or remove if not needed
```

Then run:
```bash
# First run: All hosts get base + services
ansible-playbook site.yml

# Second run: Only services (skip base)
ansible-playbook site.yml --skip-tags base
```

---

## 📊 Time Comparison

| Scenario | Current | Optimized | Savings |
|----------|---------|-----------|---------|
| 16 VMs (sequential base) | 80-160 min | 20-30 min | **75-87%** |
| 8 VMs (sequential base) | 40-80 min | 10-15 min | **75-87%** |
| 4 VMs (sequential base) | 20-40 min | 5-10 min | **75-87%** |

---

## ✅ Implementation Checklist

- [ ] Create `ansible/playbooks/common_base_setup.yml`
- [ ] Update `site.yml` to import common_base_setup as Phase 0
- [ ] Add strategy_plugins and forks to ansible.cfg
- [ ] Add conditional tags to skip base_config on subsequent runs
- [ ] Test Phase 0 alone: `ansible-playbook ... --tags base`
- [ ] Test Phase 1 alone: `ansible-playbook ... --skip-tags base`
- [ ] Test full deployment: `ansible-playbook site.yml`
- [ ] Document new deployment workflow

---

## 🚀 Usage After Optimization

```bash
# Full deployment (first time)
ansible-playbook site.yml \
  -e @vault/onepassword.yml \
  -e @vault/github_runner.yml \
  -e @vault/pihole.yml

# Just base config phase
ansible-playbook site.yml --tags base

# Add a new VM (reuse base config)
ansible-playbook site.yml -l newvm --skip-tags base

# Full deployment (reuse base config if already run)
ansible-playbook site.yml --skip-tags base
```

---

**Next**: Ready to implement? I can create the optimized playbooks now.
