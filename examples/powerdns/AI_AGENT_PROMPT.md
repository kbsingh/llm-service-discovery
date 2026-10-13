# PowerDNS Configuration for LLM Discovery - AI Agent Implementation Guide

## Purpose
You are tasked with implementing DNS SRV-based LLM endpoint discovery using PowerDNS with MySQL/PostgreSQL backend and Lua scripting for dynamic, subnet-based responses.

## What This Accomplishes

PowerDNS provides:

1. **SQL-Based Record Management** - Store DNS records in MySQL/PostgreSQL for easy programmatic updates
2. **Dynamic Lua Scripting** - Return different endpoints based on client IP, time, or custom logic
3. **REST API** - Programmatically manage records without editing files
4. **High Performance** - Modern authoritative DNS with caching and replication
5. **Health-Check Friendly** - Records live in SQL, so an external health-check script can enable/disable endpoints with simple UPDATEs (PowerDNS does not health-check on its own)

## Advantages Over BIND

| Feature | PowerDNS | BIND |
|---------|----------|------|
| Record Storage | SQL database | Text files |
| Dynamic Updates | SQL INSERT/UPDATE or API | nsupdate or file reload |
| Scripting | Lua (runtime) | None |
| API | Built-in REST API | None |
| Health Checks | SQL-driven external scripts | External scripts |

## Prerequisites

- PowerDNS installed
- MySQL or PostgreSQL
- Root/sudo access
- Basic SQL knowledge

## Implementation Steps

### Step 1: Install PowerDNS and Backend

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install pdns-server pdns-backend-mysql mysql-server
```

**RHEL/CentOS/Fedora:**
```bash
sudo dnf install pdns pdns-backend-mysql mariadb-server
```

### Step 2: Set Up Database

```bash
# Start the database ("mysql" on Debian/Ubuntu, "mariadb" on RHEL/Fedora)
sudo systemctl start mysql
sudo systemctl enable mysql

# Create database and user
sudo mysql <<'EOF'
CREATE DATABASE pdns CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'pdns'@'localhost' IDENTIFIED BY 'CHANGE_ME_DB_PASSWORD';
GRANT ALL PRIVILEGES ON pdns.* TO 'pdns'@'localhost';
FLUSH PRIVILEGES;
EOF
```

**CRITICAL:** Replace `CHANGE_ME_DB_PASSWORD` with a strong password!

### Step 3: Import Database Schema

Use the repository's schema — it contains the standard PowerDNS tables
plus the custom `subnet_policies`, `endpoint_health` and `audit_log`
tables, views, and audit triggers:

```bash
sudo mysql pdns < examples/powerdns/schema.sql

# Optional: example SRV/TXT records and subnet policies
sudo mysql pdns < examples/powerdns/seed-data.sql
```

### Step 4: Configure PowerDNS

**Create `/etc/powerdns/pdns.conf` (or edit existing):**

```ini
# MySQL Backend
launch=gmysql
gmysql-host=127.0.0.1
gmysql-port=3306
gmysql-dbname=pdns
gmysql-user=pdns
gmysql-password=CHANGE_ME_DB_PASSWORD
gmysql-dnssec=no

# General Settings
daemon=yes
guardian=yes
setuid=pdns
setgid=pdns
local-address=0.0.0.0
local-port=53

# Authoritative server
master=yes
slave=no

# Lua pre-query hook for subnet-based routing
lua-prequery-script=/etc/powerdns/subnet-router.lua

# Honor EDNS Client Subnet (so the Lua script sees the real client IP)
use-incoming-edns-subnet=yes

# API Configuration
api=yes
api-key=CHANGE_ME_API_KEY
webserver=yes
webserver-address=127.0.0.1
webserver-port=8081
webserver-allow-from=127.0.0.1,::1

# Logging (query logging disabled by default - privacy/disk usage)
loglevel=4
# log-dns-queries=yes
# log-dns-details=yes

# Performance
distributor-threads=3
receiver-threads=1
cache-ttl=20
```

**CRITICAL:** Replace `CHANGE_ME_DB_PASSWORD` and `CHANGE_ME_API_KEY`!

### Step 5: Create Lua Script for Subnet Routing

**Copy the repository's script** (do not retype it — the shipped version
has real CIDR matching for any /0–/32 prefix, complete endpoint tables
for all four subnets and multiple capabilities, and guarded
initialization):

```bash
sudo cp examples/powerdns/subnet-router.lua /etc/powerdns/subnet-router.lua
sudo chown pdns:pdns /etc/powerdns/subnet-router.lua
sudo chmod 644 /etc/powerdns/subnet-router.lua
```

The script's structure (see the file for the full endpoint tables):

```lua
-- Real CIDR matching for IPv4, any prefix length /0-/32
function ip_in_subnet(ip_str, cidr) ... end

-- Map client IP to a policy group
function determine_subnet(client_ip)
    -- finance (10.1.0.0/16), engineering (10.2.0.0/16),
    -- internal (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16), external
end

-- Per-subnet endpoint tables keyed by service, e.g.
-- finance_endpoints["_llm-chat._tcp"] = { {prio=10, weight=100, port=8443, ...} }

-- Pre-query hook: intercept SRV queries, return the subnet's endpoints
function preresolve(dq) ... end
```

**IMPORTANT:** Customize the endpoint hostnames, ports and weights in
the `*_endpoints` tables for your environment!

### Step 6: Populate Database

If you skipped the optional seed import in Step 3, add your own data.
Note the trailing dots on domain-name RDATA (SOA/NS/SRV targets) —
PowerDNS requires them:

```sql
-- Add domain
INSERT INTO domains (name, type) VALUES ('corp.example.com', 'NATIVE');

SET @domain_id = LAST_INSERT_ID();

-- Add SOA record
INSERT INTO records (domain_id, name, type, content, ttl) VALUES
(@domain_id, 'corp.example.com', 'SOA',
 'ns1.corp.example.com. admin.corp.example.com. 2026101201 3600 1800 604800 300',
 3600);

-- Add default SRV records (Lua will override based on subnet)
INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@domain_id, '_llm-chat._tcp.corp.example.com', 'SRV',
 '10 100 8080 llm-gpu-cluster.internal.corp.example.com.', 300, 10);

-- Add TXT metadata
INSERT INTO records (domain_id, name, type, content, ttl) VALUES
(@domain_id, '_llm-chat._tcp.corp.example.com', 'TXT',
 '"path=/v1/messages"', 300),
(@domain_id, '_llm-chat._tcp.corp.example.com', 'TXT',
 '"provider=mixed"', 300);

-- Add subnet policies
INSERT INTO subnet_policies
(subnet, department, service, domain, endpoint, priority, weight, port, notes) VALUES
('10.1.0.0/16', 'finance', '_llm-chat._tcp', 'corp.example.com',
 'llm-secure.internal.corp.example.com', 10, 100, 8443,
 'SOC2/HIPAA compliant endpoint'),
('10.2.0.0/16', 'engineering', '_llm-chat._tcp', 'corp.example.com',
 'llm-experimental.internal.corp.example.com', 10, 30, 8090,
 'Experimental models for testing');

-- Add endpoint health
INSERT INTO endpoint_health (endpoint, status) VALUES
('llm-gpu-cluster.internal.corp.example.com', 'healthy'),
('provider1-proxy.corp.example.com', 'healthy');
```

### Step 7: Start PowerDNS

```bash
sudo systemctl start pdns
sudo systemctl enable pdns
sudo systemctl status pdns
```

### Step 8: Test Resolution

```bash
dig @localhost SRV _llm-chat._tcp.corp.example.com
```

### Step 9: Test API

```bash
# List zones
curl -H "X-API-Key: CHANGE_ME_API_KEY" \
  http://localhost:8081/api/v1/servers/localhost/zones

# Add record via API
curl -X PATCH http://localhost:8081/api/v1/servers/localhost/zones/corp.example.com \
  -H "X-API-Key: CHANGE_ME_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "_llm-embedding._tcp.corp.example.com.",
      "type": "SRV",
      "changetype": "REPLACE",
      "records": [{
        "content": "10 100 8081 embeddings.internal.corp.example.com.",
        "disabled": false
      }]
    }]
  }'
```

## Integration with Existing PowerDNS

### If PowerDNS Already Running

1. **Backup database:**
   ```bash
   mysqldump -u pdns -p pdns > pdns_backup_$(date +%Y%m%d).sql
   ```

2. **Add custom tables:**
   ```sql
   USE pdns;
   -- Run only subnet_policies and endpoint_health table creation
   ```

3. **Add Lua script:**
   - Create `/etc/powerdns/subnet-router.lua`
   - Add to `pdns.conf`: `lua-prequery-script=/etc/powerdns/subnet-router.lua`
   - Restart (the packaged systemd unit has no reload action):
     `sudo systemctl restart pdns` (or `sudo pdns_control reload`)

4. **Test without affecting existing zones:**
   - Create test domain first
   - Verify Lua script doesn't break existing queries

## Dynamic Record Management

### Via SQL

```sql
-- Add new endpoint
INSERT INTO records (domain_id, name, type, content, ttl, prio)
SELECT id, '_llm-vision._tcp.corp.example.com', 'SRV',
       '10 100 443 vision.corp.example.com.', 300, 10
FROM domains WHERE name = 'corp.example.com';
```

```bash
# Flush cache
sudo pdns_control purge corp.example.com
```

### Via API

```bash
#!/bin/bash
# add_llm_endpoint.sh

API_KEY="CHANGE_ME_API_KEY"
DOMAIN="corp.example.com"
SERVICE="_llm-chat._tcp"
TARGET="new-llm.corp.example.com."
PORT="443"

curl -X PATCH "http://localhost:8081/api/v1/servers/localhost/zones/${DOMAIN}" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"rrsets\": [{
      \"name\": \"${SERVICE}.${DOMAIN}.\",
      \"type\": \"SRV\",
      \"changetype\": \"REPLACE\",
      \"records\": [{
        \"content\": \"10 100 ${PORT} ${TARGET}\",
        \"disabled\": false
      }]
    }]
  }"
```

## Health Check Integration

```bash
#!/bin/bash
# health_check.sh - Disable unhealthy endpoints

for endpoint in llm-gpu-cluster.internal.corp.example.com \
                provider1-proxy.corp.example.com; do
    if ! curl -sf --max-time 5 "https://${endpoint}/health" > /dev/null; then
        echo "Endpoint $endpoint is down"
        mysql pdns -e "UPDATE records SET disabled=1 WHERE content LIKE '%${endpoint}%'"
        pdns_control purge corp.example.com
        
        # Update health table
        mysql pdns -e "
            INSERT INTO endpoint_health (endpoint, status, consecutive_failures)
            VALUES ('$endpoint', 'down', 1)
            ON DUPLICATE KEY UPDATE
                status='down',
                consecutive_failures=consecutive_failures+1,
                last_check=NOW()
        "
    else
        # Re-enable healthy endpoints
        mysql pdns -e "UPDATE records SET disabled=0 WHERE content LIKE '%${endpoint}%'"
        mysql pdns -e "
            INSERT INTO endpoint_health (endpoint, status, consecutive_failures)
            VALUES ('$endpoint', 'healthy', 0)
            ON DUPLICATE KEY UPDATE
                status='healthy',
                consecutive_failures=0,
                last_check=NOW()
        "
    fi
done
```

**Add to cron** (after saving as `/usr/local/bin/llm-health-check.sh`
with `sudo install -m 755`):
```bash
*/5 * * * * /usr/local/bin/llm-health-check.sh
```

## Troubleshooting

### PowerDNS won't start

```bash
# Check configuration
pdns_server --config-dir=/etc/powerdns --daemon=no

# Check database connection
mysql -u pdns -p pdns -e "SELECT COUNT(*) FROM domains;"

# Check logs
sudo journalctl -u pdns -n 50
```

### Lua script errors

```bash
# Check logs for Lua errors
sudo journalctl -u pdns | grep -i lua

# Syntax-check the script (luac -p checks without executing; the
# script's guarded initialization also makes plain `lua file.lua`
# load safely)
luac -p /etc/powerdns/subnet-router.lua
```

### No responses from API

```bash
# Check API is enabled
grep "^api=" /etc/powerdns/pdns.conf

# Check webserver is running (API requires the X-API-Key header - a
# bare curl returns 401)
curl -H "X-API-Key: CHANGE_ME_API_KEY" \
  http://localhost:8081/api/v1/servers/localhost
```

## Production Checklist

- [ ] Change default passwords
- [ ] Generate strong API key
- [ ] Configure database replication
- [ ] Set up backup/restore procedures
- [ ] Enable DNSSEC (optional)
- [ ] Configure monitoring (Prometheus exporter available)
- [ ] Set up master-slave replication
- [ ] Implement automated health checking
- [ ] Configure firewall rules
- [ ] Document API key management
- [ ] Test failover scenarios

## Reference

- Full schema: `examples/powerdns/schema.sql`
- Example data: `examples/powerdns/seed-data.sql`
- Lua script: `examples/powerdns/subnet-router.lua`
- Configuration: `examples/powerdns/pdns.conf`
