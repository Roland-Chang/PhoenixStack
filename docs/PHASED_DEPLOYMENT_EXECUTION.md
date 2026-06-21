# PhoenixStack: Phased Deployment Execution Guide

**Deployment Strategy**: Phased approach, ~1-2 days per phase for testing + validation

---

<<<<<<< HEAD
## Phase 1: PostgreSQL Cluster (PGSQL01/02) - CURRENT
=======
## Phase 1: PostgreSQL Cluster (SQL01/02) - CURRENT
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

### Step 1.1: Deploy Containers (5 minutes)

```bash
cd /home/ayoung/projects/phoenixstack/terraform

# Plan the deployment
<<<<<<< HEAD
terraform plan -target=module.pgsql01 -target=module.pgsql02

# Apply the deployment
terraform apply -target=module.pgsql01 -target=module.pgsql02
=======
terraform plan -target=module.sql01 -target=module.sql02

# Apply the deployment
terraform apply -target=module.sql01 -target=module.sql02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
```

**Expected Output:**
```
Apply complete! Resources added: 2
```

---

### Step 1.2: Verify Containers Running (2 minutes)

```bash
# Check containers exist
pct list | grep -E "112|113"

# Expected output:
<<<<<<< HEAD
#  112  pgsql01    running   -   2    2048
#  113  pgsql02    running   -   2    2048

# Verify networking
ping -c 3 10.101.0.71  # PGSQL01
ping -c 3 10.101.0.72  # PGSQL02
=======
#  112  sql01    running   -   2    2048
#  113  sql02    running   -   2    2048

# Verify networking
ping -c 3 10.101.0.71  # SQL01
ping -c 3 10.101.0.72  # SQL02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

# SSH access test
ssh root@10.101.0.71 "hostname && ip addr show eth0"
ssh root@10.101.0.72 "hostname && ip addr show eth0"
```

---

### Step 1.3: Install PostgreSQL on Both Containers (10 minutes)

```bash
<<<<<<< HEAD
# SSH to PGSQL01
ssh root@10.101.0.71

# Inside PGSQL01 container:
=======
# SSH to SQL01
ssh root@10.101.0.71

# Inside SQL01 container:
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
apt update
apt install -y postgresql postgresql-contrib
psql --version

# Check PostgreSQL is running
systemctl status postgresql
```

```bash
<<<<<<< HEAD
# SSH to PGSQL02
ssh root@10.101.0.72

# Inside PGSQL02 container:
=======
# SSH to SQL02
ssh root@10.101.0.72

# Inside SQL02 container:
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
apt update
apt install -y postgresql postgresql-contrib
psql --version
systemctl status postgresql
```

---

### Step 1.4: Configure PostgreSQL Replication (30 minutes)

<<<<<<< HEAD
#### PGSQL01 (Primary) Configuration:
=======
#### SQL01 (Primary) Configuration:
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

```bash
# SSH to SQL01
ssh root@10.101.0.71

# Edit postgresql.conf
sudo nano /etc/postgresql/14/main/postgresql.conf

# Find and uncomment/modify:
listen_addresses = '*'          # Allow remote connections
wal_level = replica             # Enable WAL for replication
max_wal_senders = 10            # Number of replication connections
max_replication_slots = 10      # Replication slots for standby

# Save and exit (Ctrl+X, Y, Enter)

# Edit pg_hba.conf for replication user
sudo nano /etc/postgresql/14/main/pg_hba.conf

# Add at the end (before any "reject" lines):
host    replication     replicator      10.101.0.72/32      md5

# Save and exit

# Restart PostgreSQL
sudo systemctl restart postgresql

# Create replication user
sudo -u postgres psql -c "CREATE USER replicator WITH REPLICATION PASSWORD 'replicator';"
sudo -u postgres psql -c "SELECT * FROM pg_user WHERE usename='replicator';"
```

<<<<<<< HEAD
#### PGSQL02 (Standby) Setup:
=======
#### SQL02 (Standby) Setup:
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

```bash
# SSH to SQL02
ssh root@10.101.0.72

# Stop PostgreSQL
sudo systemctl stop postgresql

# Remove existing data
sudo rm -rf /var/lib/postgresql/14/main/*

<<<<<<< HEAD
# Create base backup from PGSQL01
=======
# Create base backup from SQL01
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
sudo -u postgres pg_basebackup -h 10.101.0.71 -D /var/lib/postgresql/14/main -U replicator -v -P

# Create recovery signal (tells PostgreSQL to enter standby mode)
sudo touch /var/lib/postgresql/14/main/recovery.signal

# Ensure proper permissions
sudo chown -R postgres:postgres /var/lib/postgresql/14/main
sudo chmod 700 /var/lib/postgresql/14/main

# Configure connection to primary (edit recovery.conf or postgresql.auto.conf)
echo "primary_conninfo = 'host=10.101.0.71 port=5432 user=replicator password=replicator'" | \
  sudo tee -a /var/lib/postgresql/14/main/postgresql.auto.conf

# Start PostgreSQL on SQL02
sudo systemctl start postgresql

# Monitor replication
sudo -u postgres psql -c "SELECT status FROM pg_stat_wal_receiver;"
```

---

### Step 1.5: Validate Replication Working (5 minutes)

```bash
<<<<<<< HEAD
# On PGSQL01, check replication is connected
ssh root@10.101.0.71
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Expected output shows PGSQL02 connected with write_lag info

# On PGSQL02, check standby is receiving WAL
=======
# On SQL01, check replication is connected
ssh root@10.101.0.71
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Expected output shows SQL02 connected with write_lag info

# On SQL02, check standby is receiving WAL
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
ssh root@10.101.0.72
sudo -u postgres psql -c "SELECT status FROM pg_stat_wal_receiver;"

# Expected output shows "streaming" status

<<<<<<< HEAD
# Create test database on PGSQL01 to verify replication
ssh root@10.101.0.71
sudo -u postgres psql -c "CREATE DATABASE test_replication;"

# Check it appears on PGSQL02
=======
# Create test database on SQL01 to verify replication
ssh root@10.101.0.71
sudo -u postgres psql -c "CREATE DATABASE test_replication;"

# Check it appears on SQL02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
ssh root@10.101.0.72
sudo -u postgres psql -l | grep test_replication

# Should show the database was replicated
```

---

### Step 1.6: Phase 1 Validation Checklist

<<<<<<< HEAD
- [ ] PGSQL01 container running (pct list shows 112)
- [ ] PGSQL02 container running (pct list shows 113)
- [ ] Both containers have network connectivity (ping succeeds)
- [ ] PostgreSQL installed and running on both
- [ ] Replication user created on PGSQL01
- [ ] PGSQL02 joined as standby (pg_stat_wal_receiver shows "streaming")
- [ ] Test database created on PGSQL01 appears on PGSQL02
=======
- [ ] SQL01 container running (pct list shows 112)
- [ ] SQL02 container running (pct list shows 113)
- [ ] Both containers have network connectivity (ping succeeds)
- [ ] PostgreSQL installed and running on both
- [ ] Replication user created on SQL01
- [ ] SQL02 joined as standby (pg_stat_wal_receiver shows "streaming")
- [ ] Test database created on SQL01 appears on SQL02
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
- [ ] Both containers survive restart without losing replication

---

### Step 1.7: When Ready to Move to Phase 2

Once all checklist items are verified, proceed to Phase 2.

**Do NOT proceed until**:
- Replication is consistently "streaming"
- Test database successfully replicated
- Both containers are stable (no errors in logs)

```bash
# Final verification before moving on:
<<<<<<< HEAD
ssh root@10.101.0.71 "sudo -u postgres psql -c \"SELECT * FROM pg_stat_replication;\" | grep -q 'streaming' && echo 'PGSQL01: OK' || echo 'PGSQL01: ISSUE'"
ssh root@10.101.0.72 "sudo -u postgres psql -c \"SELECT status FROM pg_stat_wal_receiver;\" | grep -q 'streaming' && echo 'PGSQL02: OK' || echo 'PGSQL02: ISSUE'"
=======
ssh root@10.101.0.71 "sudo -u postgres psql -c \"SELECT * FROM pg_stat_replication;\" | grep -q 'streaming' && echo 'SQL01: OK' || echo 'SQL01: ISSUE'"
ssh root@10.101.0.72 "sudo -u postgres psql -c \"SELECT status FROM pg_stat_wal_receiver;\" | grep -q 'streaming' && echo 'SQL02: OK' || echo 'SQL02: ISSUE'"
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
```

---

## Phase 2: MariaDB Cluster (DB01/02) - AFTER PHASE 1 VERIFIED

### Step 2.1: Deploy Containers (5 minutes)

```bash
cd /home/ayoung/projects/phoenixstack/terraform

# Plan the deployment
terraform plan -target=module.db01 -target=module.db02

# Apply the deployment
terraform apply -target=module.db01 -target=module.db02
```

**Expected Output:**
```
Apply complete! Resources added: 2
```

---

### Step 2.2: Verify Containers Running (2 minutes)

```bash
# Check containers exist
pct list | grep -E "116|117"

# Expected output:
#  116  db01     running   -   2    2048
#  117  db02     running   -   2    2048

# Verify networking
ping -c 3 10.101.0.73  # DB01
ping -c 3 10.101.0.74  # DB02

# SSH access test
ssh root@10.101.0.73 "hostname && ip addr show eth0"
ssh root@10.101.0.74 "hostname && ip addr show eth0"
```

---

### Step 2.3: Install MariaDB on Both Containers (10 minutes)

```bash
# SSH to DB01
ssh root@10.101.0.73

# Inside DB01 container:
apt update
apt install -y mariadb-server mariadb-client
mysql --version

# Check MariaDB is running
systemctl status mariadb
```

```bash
# SSH to DB02
ssh root@10.101.0.74

# Inside DB02 container:
apt update
apt install -y mariadb-server mariadb-client
mysql --version
systemctl status mariadb
```

---

### Step 2.4: Configure MariaDB Replication (30 minutes)

#### DB01 (Master) Configuration:

```bash
# SSH to DB01
ssh root@10.101.0.73

# Edit MariaDB config
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf

# Find [mysqld] section and modify/add:
server-id          = 1
log_bin            = /var/log/mysql/mysql-bin.log
binlog_format      = MIXED
relay-log          = /var/log/mysql/mysql-relay-bin
relay-log-index    = /var/log/mysql/mysql-relay-bin.index

# Save and exit (Ctrl+X, Y, Enter)

# Restart MariaDB
sudo systemctl restart mariadb

# Create replication user
sudo mysql -u root -e "GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'10.101.0.74' IDENTIFIED BY 'replicator';"
sudo mysql -u root -e "FLUSH PRIVILEGES;"

# Get current binlog position (needed for DB02)
sudo mysql -u root -e "FLUSH MASTER LOGS;"
BINLOG_FILE=$(sudo mysql -u root -e "SHOW MASTER STATUS\G" | grep "File:" | awk '{print $2}')
BINLOG_POS=$(sudo mysql -u root -e "SHOW MASTER STATUS\G" | grep "Position:" | awk '{print $2}')

echo "Binary Log File: $BINLOG_FILE"
echo "Binary Log Position: $BINLOG_POS"
# Save these values - needed for DB02 configuration
```

#### DB02 (Slave) Configuration:

```bash
# SSH to DB02
ssh root@10.101.0.74

# Edit MariaDB config
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf

# Find [mysqld] section and modify/add:
server-id          = 2
relay-log          = /var/log/mysql/mysql-relay-bin
relay-log-index    = /var/log/mysql/mysql-relay-bin.index

# Save and exit

# Restart MariaDB
sudo systemctl restart mariadb

# Configure replication (use BINLOG_FILE and BINLOG_POS from DB01)
# Replace mysql-bin.000001 and 0 with actual values from DB01
sudo mysql -u root << 'EOF'
CHANGE MASTER TO
  MASTER_HOST='10.101.0.73',
  MASTER_USER='replicator',
  MASTER_PASSWORD='replicator',
  MASTER_LOG_FILE='mysql-bin.000001',
  MASTER_LOG_POS=0;
START SLAVE;
EOF

# Verify replication is running
sudo mysql -u root -e "SHOW SLAVE STATUS\G"

# Expected output shows:
# Slave_IO_Running: Yes
# Slave_SQL_Running: Yes
```

---

### Step 2.5: Validate Replication Working (5 minutes)

```bash
# On DB01, verify slave is connected
ssh root@10.101.0.73
sudo mysql -u root -e "SHOW MASTER STATUS\G"

# On DB02, verify slave status
ssh root@10.101.0.74
sudo mysql -u root -e "SHOW SLAVE STATUS\G"

# Expected output shows:
# Slave_IO_Running: Yes
# Slave_SQL_Running: Yes
# Seconds_Behind_Master: 0

# Create test database on DB01 to verify replication
ssh root@10.101.0.73
sudo mysql -u root -e "CREATE DATABASE test_replication;"

# Check it appears on DB02
ssh root@10.101.0.74
sudo mysql -u root -e "SHOW DATABASES;" | grep test_replication

# Should show the database was replicated
```

---

### Step 2.6: Phase 2 Validation Checklist

- [ ] DB01 container running (pct list shows 116)
- [ ] DB02 container running (pct list shows 117)
- [ ] Both containers have network connectivity (ping succeeds)
- [ ] MariaDB installed and running on both
- [ ] Replication user created on DB01
- [ ] DB02 slave is running (Slave_IO_Running: Yes, Slave_SQL_Running: Yes)
- [ ] Test database created on DB01 appears on DB02
- [ ] Replication lag (Seconds_Behind_Master) is 0 or very low
- [ ] Both containers are stable (no errors in logs)

---

### Step 2.7: When Ready to Move to Phase 3

Once all checklist items are verified, proceed to Phase 3.

```bash
# Final verification before moving on:
ssh root@10.101.0.73 "sudo mysql -u root -e 'SHOW MASTER STATUS\G'" | grep -q 'File:' && echo 'DB01: OK' || echo 'DB01: ISSUE'
ssh root@10.101.0.74 "sudo mysql -u root -e 'SHOW SLAVE STATUS\G'" | grep -q 'Yes' && echo 'DB02: OK' || echo 'DB02: ISSUE'
```

---

## Phase 3: Observability Cluster (MONITOR01/02) - AFTER PHASE 2 VERIFIED

### Step 3.1: Deploy Containers (5 minutes)

```bash
cd /home/ayoung/projects/phoenixstack/terraform

# Plan the deployment
terraform plan -target=module.monitor01 -target=module.monitor02

# Apply the deployment
terraform apply -target=module.monitor01 -target=module.monitor02
```

**Expected Output:**
```
Apply complete! Resources added: 2
```

---

### Step 3.2: Verify Containers Running (2 minutes)

```bash
# Check containers exist
pct list | grep -E "114|115"

# Expected output:
#  114  monitor01  running  -   2    1536
#  115  monitor02  running  -   2    1536

# Verify networking
ping -c 3 10.101.0.101  # MONITOR01
ping -c 3 10.101.0.102  # MONITOR02

# SSH access test
ssh root@10.101.0.101 "hostname && ip addr show eth0"
ssh root@10.101.0.102 "hostname && ip addr show eth0"
```

---

### Step 3.3: Install Prometheus & Grafana (15 minutes)

```bash
# SSH to MONITOR01 (Prometheus)
ssh root@10.101.0.101

# Inside MONITOR01 container:
apt update
apt install -y prometheus prometheus-node-exporter

# Start services
systemctl enable prometheus
systemctl start prometheus
systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# Verify Prometheus is running
curl -s http://localhost:9090/-/ready
# Should return: OK
```

```bash
# SSH to MONITOR02 (Grafana)
ssh root@10.101.0.102

# Inside MONITOR02 container:
apt update
apt install -y grafana-server grafana-piechart-panel

# Start service
systemctl enable grafana-server
systemctl start grafana-server

# Get initial admin password
sudo cat /etc/grafana/provisioning/datasources/* | grep password || echo "Initial password: admin/admin"

# Verify Grafana is running
curl -s http://localhost:3000/api/health
# Should return JSON with status
```

---

### Step 3.4: Configure Prometheus to Scrape Databases (10 minutes)

```bash
# SSH to MONITOR01
ssh root@10.101.0.101

# Edit Prometheus config
sudo nano /etc/prometheus/prometheus.yml

# Find the "scrape_configs:" section and add:
<<<<<<< HEAD
  - job_name: 'postgres_pgsql01'
    static_configs:
      - targets: ['10.101.0.71:9187']
  
  - job_name: 'postgres_pgsql02'
=======
  - job_name: 'postgres_sql01'
    static_configs:
      - targets: ['10.101.0.71:9187']
  
  - job_name: 'postgres_sql02'
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072
    static_configs:
      - targets: ['10.101.0.72:9187']
  
  - job_name: 'mariadb_db01'
    static_configs:
      - targets: ['10.101.0.73:9104']
  
  - job_name: 'mariadb_db02'
    static_configs:
      - targets: ['10.101.0.74:9104']

# Save and exit

# Restart Prometheus
sudo systemctl restart prometheus
```

---

### Step 3.5: Phase 3 Validation Checklist

- [ ] MONITOR01 container running (pct list shows 114)
- [ ] MONITOR02 container running (pct list shows 115)
- [ ] Both containers have network connectivity (ping succeeds)
- [ ] Prometheus installed and running on MONITOR01
- [ ] Prometheus web UI accessible at http://10.101.0.101:9090
- [ ] Grafana installed and running on MONITOR02
- [ ] Grafana web UI accessible at http://10.101.0.102:3000 (username: admin, password: admin)
- [ ] All services are stable (no errors in logs)

---

## What's Next After Phase 3?

<<<<<<< HEAD
Once all 6 containers (PGSQL01/02, DB01/02, MONITOR01/02) are running:
=======
Once all 6 containers (SQL01/02, DB01/02, MONITOR01/02) are running:
>>>>>>> 33549d8e5ca7b898273e4356d0bf3f3af5081072

1. **Quick Win**: Add PostgreSQL and MariaDB exporter agents
   - Installs prometheus exporters on databases
   - Prometheus starts collecting database metrics
   - Grafana shows real-time database health

2. **Then Deploy Tier 2**: VAULT01/02 (Security tier)
   - HashiCorp Vault for secrets management
   - Integrates with SQL cluster for state storage

3. **Then Deploy Tier 3**: BACKUP01 (Backup tier)
   - Automated backups of all containers
   - Disaster recovery procedures

---

## Troubleshooting Quick Reference

### PostgreSQL Issues
```bash
# Check replication status
ssh root@10.101.0.71 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'"

# Check standby WAL receiver
ssh root@10.101.0.72 "sudo -u postgres psql -c 'SELECT status FROM pg_stat_wal_receiver;'"

# View PostgreSQL logs
ssh root@10.101.0.71 "sudo tail -50 /var/log/postgresql/postgresql-14-main.log"
ssh root@10.101.0.72 "sudo tail -50 /var/log/postgresql/postgresql-14-main.log"
```

### MariaDB Issues
```bash
# Check replication status on master
ssh root@10.101.0.73 "sudo mysql -u root -e 'SHOW MASTER STATUS\G'"

# Check replication status on slave
ssh root@10.101.0.74 "sudo mysql -u root -e 'SHOW SLAVE STATUS\G'"

# View MariaDB logs
ssh root@10.101.0.73 "sudo tail -50 /var/log/mysql/error.log"
ssh root@10.101.0.74 "sudo tail -50 /var/log/mysql/error.log"
```

### Prometheus Issues
```bash
# Check Prometheus config syntax
ssh root@10.101.0.101 "promtool check config /etc/prometheus/prometheus.yml"

# View Prometheus targets
curl -s http://10.101.0.101:9090/api/v1/targets | jq .
```

---

## Success Criteria

**Phase 1 Complete**: PostgreSQL replication streaming, test database replicated  
**Phase 2 Complete**: MariaDB replication running, test database replicated  
**Phase 3 Complete**: Prometheus collecting metrics, Grafana displaying dashboards  

**All Phases Complete**: Infrastructure is observable, both database clusters are HA, ready for VAULT and BACKUP tiers
