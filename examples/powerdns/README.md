# PowerDNS Configuration for LLM SRV Discovery

PowerDNS with SQL backend and Lua scripting for dynamic, subnet-based LLM endpoint discovery.

## Why PowerDNS?

- **SQL Backend**: Manage records via database queries
- **Lua Scripting**: Dynamic responses based on client IP, time, or any logic
- **API**: REST API for programmatic record management
- **Performance**: High-performance authoritative DNS server

## Architecture

PowerDNS uses:
1. **MySQL/PostgreSQL** backend for record storage
2. **Lua scripts** to modify responses based on client subnet
3. **API** for dynamic record updates

## Files

```
powerdns/
├── README.md                    # This file
├── pdns.conf                    # PowerDNS configuration
├── schema.sql                   # Database schema
├── seed-data.sql                # Example SRV records
└── subnet-router.lua            # Lua script for subnet-based routing
```

## Installation

### 1. Install PowerDNS with Backend

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install pdns-server pdns-backend-mysql mysql-server
```

**RHEL/CentOS/Fedora:**
```bash
sudo dnf install pdns pdns-backend-mysql mariadb-server
```

### 2. Setup Database

```bash
# Start the database ("mysql" on Debian/Ubuntu, "mariadb" on RHEL/Fedora)
sudo systemctl start mysql      # Debian/Ubuntu
sudo systemctl enable mysql

# Create database and user
sudo mysql <<EOF
CREATE DATABASE pdns;
CREATE USER 'pdns'@'localhost' IDENTIFIED BY 'CHANGE_ME_DB_PASSWORD';
GRANT ALL PRIVILEGES ON pdns.* TO 'pdns'@'localhost';
FLUSH PRIVILEGES;
EOF

# Import schema
sudo mysql pdns < schema.sql

# Import example data
sudo mysql pdns < seed-data.sql
```

### 3. Configure PowerDNS

```bash
# Backup existing config
sudo cp /etc/powerdns/pdns.conf /etc/powerdns/pdns.conf.backup

# Copy our config
sudo cp pdns.conf /etc/powerdns/pdns.conf

# Copy Lua script
sudo cp subnet-router.lua /etc/powerdns/subnet-router.lua
sudo chown pdns:pdns /etc/powerdns/subnet-router.lua

# Update database credentials in pdns.conf
sudo nano /etc/powerdns/pdns.conf
# Change: gmysql-password=CHANGE_ME_DB_PASSWORD and api-key=CHANGE_ME_API_KEY
```

### 4. Start PowerDNS

```bash
sudo systemctl start pdns
sudo systemctl enable pdns
sudo systemctl status pdns
```

## Configuration Details

### pdns.conf

Key settings for LLM discovery:

```ini
# MySQL backend
launch=gmysql
gmysql-host=127.0.0.1
gmysql-port=3306
gmysql-dbname=pdns
gmysql-user=pdns
gmysql-password=CHANGE_ME_DB_PASSWORD

# Lua pre-query hook for subnet-based responses
lua-prequery-script=/etc/powerdns/subnet-router.lua

# Honor EDNS Client Subnet (so the Lua script sees the real client IP
# even through forwarding resolvers)
use-incoming-edns-subnet=yes

# API (optional, for programmatic updates)
api=yes
api-key=CHANGE_ME_API_KEY
webserver=yes
webserver-address=127.0.0.1
webserver-port=8081
webserver-allow-from=127.0.0.1
```

## Database Schema

PowerDNS stores DNS records in SQL tables. Our schema (`schema.sql`) includes:

**`domains` table**: Zone information
**`records` table**: DNS records (A, SRV, TXT, etc.)
**`subnet_policies` table**: Custom table for per-subnet endpoint policies
**`endpoint_health` table**: Custom table for endpoint health status (consumed by an external health-check script — PowerDNS does not read it automatically)
**`audit_log` table**: Trigger-based audit trail of record changes

### Example SRV Record in Database

```sql
INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(1, '_llm-chat._tcp.corp.example.com', 'SRV', '10 70 8080 llm-gpu-cluster.internal.corp.example.com.', 300, 10);
```

The `content` field contains: `priority weight port target` — note the
**trailing dot** on the target, which PowerDNS requires for domain-name
RDATA.

## Subnet-Based Routing with Lua

The `subnet-router.lua` script intercepts SRV queries before normal
resolution and returns different endpoint sets per client subnet
(finance / engineering / internal / external). It is a self-contained,
working script — see the file itself for the full endpoint tables. The
core of it:

```lua
function preresolve(dq)
    local client_ip = dq.remote:toString()
    local subnet = determine_subnet(client_ip)   -- "finance", "engineering", ...

    if dq.qtype ~= pdns.SRV then
        return false   -- not an SRV query: normal resolution
    end

    local service = extract_service(dq.qname:toString())  -- e.g. "_llm-chat._tcp"
    local endpoints = endpoint_sets[subnet][service]      -- per-subnet policy tables

    for _, ep in ipairs(endpoints) do
        dq:addRecord(dq.qtype,
                     string.format("%d %d %d %s", ep.prio, ep.weight, ep.port, ep.target),
                     300)
    end

    dq.rcode = 0
    return true   -- we handled this query
end
```

The script performs real CIDR matching (`ip_in_subnet` handles any
/0–/32 prefix, including 172.16.0.0/12) rather than string prefixes.

## Testing

### Query SRV Records

```bash
# Basic query
dig @localhost SRV _llm-chat._tcp.corp.example.com

# With a specific source IP (only works with an IP configured on the
# querying host - dig -b binds a local source address)
dig @localhost -b <local-ip-in-10.1.0.0/16> SRV _llm-chat._tcp.corp.example.com
```

### Query via PowerDNS API

```bash
# List all records
curl -H "X-API-Key: CHANGE_ME_API_KEY" \
  http://localhost:8081/api/v1/servers/localhost/zones/corp.example.com

# Search for SRV records
curl -H "X-API-Key: CHANGE_ME_API_KEY" \
  http://localhost:8081/api/v1/servers/localhost/search-data?q=_llm-chat
```

## Dynamic Record Management

### Add SRV Record via API

```bash
curl -X PATCH http://localhost:8081/api/v1/servers/localhost/zones/corp.example.com \
  -H "X-API-Key: CHANGE_ME_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [
      {
        "name": "_llm-chat._tcp.corp.example.com.",
        "type": "SRV",
        "changetype": "REPLACE",
        "records": [
          {
            "content": "10 100 443 new-llm-endpoint.corp.example.com.",
            "disabled": false
          }
        ]
      }
    ]
  }'
```

### Add SRV Record via SQL

```bash
mysql pdns <<EOF
INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
((SELECT id FROM domains WHERE name='corp.example.com'),
 '_llm-embedding._tcp.corp.example.com',
 'SRV',
 '10 100 8081 new-embeddings.internal.corp.example.com.',
 300,
 10);
EOF

# Trigger cache flush
sudo pdns_control purge corp.example.com
```

## Subnet Policy Examples

The `subnet_policies` table (created by `schema.sql`, seeded by
`seed-data.sql`) maps subnets to endpoint sets:

```sql
-- Which endpoints does each department get? (from seed-data.sql)
SELECT subnet, department, service, endpoint, priority, weight, port
FROM subnet_policies
WHERE enabled = TRUE
ORDER BY subnet, service, priority, weight DESC;

-- Active policies joined with endpoint health status
SELECT * FROM active_policies_view;
```

Note: the Lua router currently serves its own in-script endpoint
tables (fast, no per-query DB access); the `subnet_policies` table is
the SQL-visible representation of the same policy for management and
API-driven deployments. Keep the two in sync, or extend the script to
read from the table with a proper parameterized connector (see the
notes in `subnet-router.lua`).

## Monitoring

### Enable Query Logging

```bash
# In pdns.conf (disabled by default - see the privacy note there)
log-dns-queries=yes
loglevel=4

# Restart PowerDNS
sudo systemctl restart pdns

# View logs
sudo journalctl -u pdns -f
```

### Statistics

```bash
# Query statistics via control socket
sudo pdns_control show '*'

# Via API
curl -H "X-API-Key: CHANGE_ME_API_KEY" \
  http://localhost:8081/api/v1/servers/localhost/statistics
```

### Database Queries for Analytics

```sql
-- Most queried services (requires custom logging)
-- Note: PowerDNS doesn't log to DB by default

-- Current SRV record count
SELECT type, COUNT(*) 
FROM records 
WHERE type='SRV' 
GROUP BY type;

-- All LLM services
SELECT name, content, ttl 
FROM records 
WHERE type='SRV' AND name LIKE '%_llm-%'
ORDER BY name;
```

## Health Checking Integration

PowerDNS has **no built-in health checking** — but because records live
in SQL, you can automate disabling failed endpoints with a small
external script:

```sql
-- Mark endpoint as disabled
UPDATE records 
SET disabled=1 
WHERE content LIKE '%failed-endpoint.corp.example.com%';
```

```bash
# Flush PowerDNS's cache after changing records
sudo pdns_control purge corp.example.com
```

For example, save this as `/usr/local/bin/llm-health-check.sh`:

```bash
#!/bin/bash
# llm-health-check.sh - Disable unhealthy endpoints
# (install with: sudo install -m 755 llm-health-check.sh /usr/local/bin/)

for endpoint in llm-gpu-cluster.internal.corp.example.com provider1-proxy.corp.example.com; do
    if ! curl -sf --max-time 5 https://$endpoint/health > /dev/null; then
        echo "Endpoint $endpoint is down, disabling..."
        mysql pdns -e "UPDATE records SET disabled=1 WHERE content LIKE '%$endpoint%'"
        pdns_control purge corp.example.com
    else
        # Re-enable if healthy
        mysql pdns -e "UPDATE records SET disabled=0 WHERE content LIKE '%$endpoint%'"
    fi
done
```

Run via cron:
```cron
*/5 * * * * /usr/local/bin/llm-health-check.sh
```

(The `endpoint_health` table in `schema.sql` is handy storage for this
script's findings; nothing in PowerDNS reads it automatically.)

## Advantages Over BIND

| Feature | PowerDNS | BIND |
|---------|----------|------|
| Backend | SQL (MySQL, PostgreSQL) | Zone files |
| Dynamic Updates | SQL INSERT/UPDATE | nsupdate or zone reload |
| API | Built-in REST API | No native API |
| Scripting | Lua (runtime) | None (compile-time) |
| Scaling | Database replication | Zone transfers |
| Management UI | Third-party (PowerDNS-Admin) | Third-party |

## Production Deployment

### Master-Slave Replication

```bash
# On master pdns.conf
master=yes
allow-notify-from=10.0.0.0/8

# On slave pdns.conf
slave=yes
```

### Database Replication

Use MySQL/PostgreSQL replication for high availability — see your
database's documentation (e.g. MariaDB's "Replication" guides). The
relevant pieces: the `pdns` database replicates like any other schema;
run one PowerDNS primary and point replicas at their local DB copies.

### Monitoring

```bash
# Prometheus exporter (prefer your distro's package if it ships one;
# if downloading a release binary, verify its checksum/signature)
# https://github.com/janeczku/powerdns_exporter

./powerdns_exporter --api-url=http://localhost:8081/api/v1 \
                    --api-key=CHANGE_ME_API_KEY
```

## Troubleshooting

### Check PowerDNS status

```bash
sudo pdns_control status
sudo systemctl status pdns
```

### Test database connection

```bash
sudo pdns_control show gmysql-queries
```

### Reload zones

```bash
sudo pdns_control reload
```

### Check Lua script errors

```bash
sudo journalctl -u pdns | grep -i lua
```

## Security

- **API Key**: Strong, random key for API access
- **Database**: Restrict MySQL access to localhost only
- **Lua Scripts**: Validate and sanitize all Lua script inputs
- **Firewall**: Restrict port 53 to trusted networks
- **DNSSEC**: Enable with `pdnsutil` commands

## Next Steps

- Deploy PowerDNS-Admin for web UI
- Set up database replication for HA
- Implement automated health checking
- Configure DNSSEC signing
- Set up metrics collection (Prometheus)
