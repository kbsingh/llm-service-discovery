# BIND DNS Configuration for LLM Discovery - AI Agent Implementation Guide

## Purpose
You are tasked with implementing DNS SRV-based LLM endpoint discovery using BIND9 DNS server. This configuration enables automatic discovery of Large Language Model API endpoints through DNS Service (SRV) records, with support for split-horizon DNS to return different endpoints based on the client's network location.

## What This Accomplishes

This implementation provides:

1. **Automatic LLM Endpoint Discovery** - Clients query DNS SRV records instead of hardcoding endpoints
2. **Split-Horizon DNS** - Different networks see different endpoints:
   - Internal corporate network: On-premises LLM servers with cloud backup
   - Finance department: Only SOC2/HIPAA compliant endpoints
   - Engineering department: Full access including experimental models
   - External/Internet: Cloud providers only
3. **Failover & Load Balancing** - Multiple endpoints with priority/weight for automatic failover
4. **Metadata Distribution** - TXT records provide API paths, authentication requirements, compliance info

## Context & Background

### DNS SRV Record Format
```
_service._protocol.domain TTL class SRV priority weight port target

Example:
_llm-chat._tcp.corp.example.com. 300 IN SRV 10 100 443 api.provider1.corp.com.
```

**Fields:**
- `priority`: Lower = preferred (clients try lowest first)
- `weight`: Load balancing among same priority (higher = more likely)
- `port`: Service port number
- `target`: Hostname providing the service

### Split-Horizon DNS
BIND "views" return different responses based on client source IP:
- Finance subnet (10.1.0.0/16) → Compliant endpoints only
- Engineering subnet (10.2.0.0/16) → All endpoints including experimental
- Internal (10.0.0.0/8) → On-prem first, cloud backup
- External (everything else) → Cloud providers only

## Prerequisites

- BIND9 installed (`apt-get install bind9` or `dnf install bind`)
- Root/sudo access
- Existing BIND configuration (or new installation)
- DNS zone ownership for your domain

## Implementation Steps

### Step 1: Assess Current BIND Configuration

**Action:** Examine existing BIND setup.

```bash
# Check BIND version
named -v

# Locate configuration
ls -la /etc/bind/named.conf  # Debian/Ubuntu
ls -la /etc/named.conf       # RHEL/CentOS

# Check current zones
grep -r "zone.*{" /etc/bind/ /etc/named/
```

### Step 2: Backup Existing Configuration

**CRITICAL: Always backup before modifications**

```bash
# Backup main config
sudo cp /etc/bind/named.conf /etc/bind/named.conf.backup.$(date +%Y%m%d)

# Backup zone files
sudo tar czf /var/backups/bind-zones-$(date +%Y%m%d).tar.gz /var/named/ /etc/bind/zones/
```

### Step 3: Define Network ACLs

**Add to `/etc/bind/named.conf` (or create `/etc/bind/named.conf.local`):**

```bind
// ACLs for different network segments
acl internal-network {
    10.0.0.0/8;
    172.16.0.0/12;
    192.168.0.0/16;
    localhost;
    localnets;
};

acl finance-network {
    10.1.0.0/16;  // Finance department subnet
};

acl engineering-network {
    10.2.0.0/16;  // Engineering department subnet
};

acl external-network {
    !10.0.0.0/8;
    !172.16.0.0/12;
    !192.168.0.0/16;
    any;
};
```

**IMPORTANT:** Replace these subnet ranges with your actual network segments!

### Step 4: Create Split-Horizon Views

**Add view definitions to `/etc/bind/named.conf`** (order matters — BIND
uses the first view whose `match-clients` matches, so the specific
department views must precede the broad internal view):

```bind
// FINANCE VIEW - Compliant endpoints only
view "finance" {
    match-clients { finance-network; };
    recursion yes;

    zone "corp.example.com" {
        type master;
        file "/var/named/finance/corp.example.com.zone";
        allow-query { finance-network; };
    };
};

// ENGINEERING VIEW - Full access
view "engineering" {
    match-clients { engineering-network; };
    recursion yes;

    zone "corp.example.com" {
        type master;
        file "/var/named/engineering/corp.example.com.zone";
        allow-query { engineering-network; };
    };
};

// INTERNAL VIEW - General corporate network
view "internal" {
    match-clients { internal-network; };
    recursion yes;

    zone "corp.example.com" {
        type master;
        file "/var/named/internal/corp.example.com.zone";
        allow-query { internal-network; };
    };
};

// EXTERNAL VIEW - Public/Internet
view "external" {
    match-clients { external-network; };
    recursion no;

    zone "corp.example.com" {
        type master;
        file "/var/named/external/corp.example.com.zone";
        allow-query { any; };
    };
};
```

**Replace:** `corp.example.com` with your actual domain.

### Step 5: Create Zone File Directories

```bash
sudo mkdir -p /var/named/{internal,external,finance,engineering}
sudo chown -R bind:bind /var/named/      # Debian/Ubuntu ("named" on RHEL/Fedora)
sudo chmod 755 /var/named
```

### Step 6: Create Zone Files with SRV Records

**Finance Zone (`/var/named/finance/corp.example.com.zone`):**

```bind
$TTL 300
@       IN      SOA     ns1.corp.example.com. admin.corp.example.com. (
                        2026101201 ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        300 )      ; Negative Cache TTL

@       IN      NS      ns1.corp.example.com.

; CHAT - Compliant endpoint ONLY (no cloud)
_llm-chat._tcp  IN  SRV  10  100  8443  llm-secure.internal.corp.example.com.

; TXT metadata
_llm-chat._tcp  IN  TXT  "path=/v1/messages"
_llm-chat._tcp  IN  TXT  "compliance=soc2,hipaa"
_llm-chat._tcp  IN  TXT  "provider=on-premises"

; A record for endpoint
llm-secure.internal  IN  A  10.1.10.100
```

**Internal Zone (`/var/named/internal/corp.example.com.zone`):**

```bind
$TTL 300
@       IN      SOA     ns1.corp.example.com. admin.corp.example.com. (
                        2026101201 ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        300 )      ; Negative Cache TTL

@       IN      NS      ns1.corp.example.com.

; CHAT - On-prem first (priority 10), cloud backup (priority 20)
_llm-chat._tcp  IN  SRV  10  70  8080  llm-gpu-cluster.internal.corp.example.com.
_llm-chat._tcp  IN  SRV  10  30  8080  llm-cpu-fallback.internal.corp.example.com.
_llm-chat._tcp  IN  SRV  20  50  443   provider1-proxy.corp.example.com.
_llm-chat._tcp  IN  SRV  20  50  443   openai-proxy.corp.example.com.

; EMBEDDING
_llm-embedding._tcp  IN  SRV  10  100  8081  embeddings.internal.corp.example.com.

; VISION
_llm-vision._tcp  IN  SRV  10  60  443  provider1-proxy.corp.example.com.
_llm-vision._tcp  IN  SRV  10  40  443  openai-proxy.corp.example.com.

; TXT metadata
_llm-chat._tcp  IN  TXT  "path=/v1/messages"
_llm-chat._tcp  IN  TXT  "provider=mixed"
_llm-chat._tcp  IN  TXT  "protocol=openai-compatible"

; A records
llm-gpu-cluster.internal     IN  A  10.0.10.100
llm-cpu-fallback.internal    IN  A  10.0.10.101
embeddings.internal          IN  A  10.0.10.102
provider1-proxy              IN  A  10.0.20.10
openai-proxy                 IN  A  10.0.20.11
```

**External Zone (`/var/named/external/corp.example.com.zone`):**

```bind
$TTL 3600
@       IN      SOA     ns1.corp.example.com. admin.corp.example.com. (
                        2026101201 ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        3600 )     ; Negative Cache TTL

@       IN      NS      ns1.corp.example.com.

; CHAT - Cloud only
_llm-chat._tcp  IN  SRV  10  50  443  api-gateway-us.corp.example.com.
_llm-chat._tcp  IN  SRV  10  50  443  api-gateway-eu.corp.example.com.

; TXT metadata
_llm-chat._tcp  IN  TXT  "path=/v1/chat"
_llm-chat._tcp  IN  TXT  "provider=cloud"
_llm-chat._tcp  IN  TXT  "environment=production"

; A records (public IPs)
api-gateway-us  IN  A  203.0.113.100
api-gateway-eu  IN  A  198.51.100.100
```

**IMPORTANT CUSTOMIZATION POINTS:**

1. **Replace hostnames** with your actual LLM server hostnames
2. **Replace IP addresses** with your actual server IPs
3. **Replace domain** `corp.example.com` with your domain
4. **Adjust ports** if your services use different ports
5. **Update serial number** whenever you make changes (use `YYYYMMDDNN` format)

### Step 7: Validate Configuration

```bash
# Test main config syntax
sudo named-checkconf /etc/bind/named.conf

# Test each zone file
sudo named-checkzone corp.example.com /var/named/internal/corp.example.com.zone
sudo named-checkzone corp.example.com /var/named/external/corp.example.com.zone
sudo named-checkzone corp.example.com /var/named/finance/corp.example.com.zone
sudo named-checkzone corp.example.com /var/named/engineering/corp.example.com.zone
```

**Expected output:** "OK" for each zone.

### Step 8: Set File Permissions

```bash
sudo chown bind:bind /var/named/*/*.zone
sudo chmod 644 /var/named/*/*.zone
```

### Step 9: Restart BIND

```bash
# Reload configuration
sudo rndc reload

# Or restart service
sudo systemctl restart named

# Check status
sudo systemctl status named

# View logs
sudo journalctl -u named -f
```

### Step 10: Test Resolution

**From internal network (10.0.x.x):**
```bash
dig @your-dns-server SRV _llm-chat._tcp.corp.example.com

# Should return on-prem endpoints first
```

**From finance network (10.1.x.x):**
```bash
dig @your-dns-server SRV _llm-chat._tcp.corp.example.com

# Should return only llm-secure.internal
```

**From external IP:**
```bash
# Query from any machine with a public IP (e.g. your laptop on the
# internet, or a cloud VM). Note: `dig -b` binds a LOCAL source
# address, so it only works with an IP actually configured on the
# querying host - it cannot simulate a foreign client.
dig @your-dns-server SRV _llm-chat._tcp.corp.example.com

# Should return only cloud gateways
```

## Integration with Existing BIND Setup

### Scenario 1: BIND Already Managing Your Domain

If BIND already serves `corp.example.com`:

1. **Identify existing zone file location**
   ```bash
   grep -A5 "zone.*corp.example.com" /etc/bind/named.conf
   ```

2. **Convert to split-horizon:**
   - Create view structure (Step 4)
   - Copy existing zone file to each view directory
   - Add SRV/TXT records to each view's zone file
   - Different SRV records per view

3. **Test with non-authoritative query first:**
   ```bash
   dig +norecurse @localhost _llm-chat._tcp.corp.example.com SRV
   ```

### Scenario 2: BIND Exists, Different Domain

If BIND exists but doesn't manage your target domain:

1. **Add new zone within existing view structure**
2. **Or create separate views just for LLM discovery domain**
3. **Ensure ACLs don't conflict with existing**

### Scenario 3: Fresh BIND Installation

Follow all steps 1-10 as-is. The provided `named.conf` is a complete working configuration.

## Troubleshooting Guide

### Issue: "zone loading from master file failed"

**Solution:**
```bash
# Check zone file syntax
named-checkzone corp.example.com /var/named/internal/corp.example.com.zone

# Check file permissions
ls -la /var/named/internal/

# Ensure the BIND user can read ("bind" on Debian/Ubuntu,
# "named" on RHEL/CentOS/Fedora)
sudo chown bind:bind /var/named/internal/corp.example.com.zone
```

### Issue: No SRV records returned

**Solution:**
```bash
# Check which view is matching
sudo tail -f /var/log/named/queries.log

# Verify ACL matches your client IP
# (dig -b requires the source IP to be configured on the querying host)
dig @your-dns-server -b <a-local-ip-in-the-subnet> SRV _llm-chat._tcp.corp.example.com

# Check zone is loaded
sudo rndc status
```

### Issue: SERVFAIL response

**Solution:**
```bash
# Check logs for errors
sudo journalctl -u named --no-pager | tail -50

# Verify zone serial numbers are incrementing
grep -r "Serial" /var/named/

# Reload zones
sudo rndc reload
```

### Issue: Wrong view responding

**Solution:**
- BIND uses first matching view
- Order matters! More specific views first
- Check ACL definitions
- Verify client source IP

## Production Checklist

- [ ] Backup all configurations
- [ ] Update serial numbers in SOA records
- [ ] Test from each network segment
- [ ] Configure DNSSEC (optional but recommended)
- [ ] Set up secondary/slave DNS servers
- [ ] Configure monitoring (query logs, health checks)
- [ ] Document endpoint-to-hostname mappings
- [ ] Set up automated zone updates
- [ ] Configure firewall rules (port 53 TCP/UDP)
- [ ] Test failover by disabling primary endpoints
- [ ] Verify TTL values are appropriate
- [ ] Enable query logging for audit

## Next Steps

1. **Add more capabilities:**
   - `_llm-embedding._tcp`
   - `_llm-vision._tcp`
   - `_llm-code._tcp`
   - `_llm-image-gen._tcp`

2. **Add policy subdomains:**
   - `_llm-chat._tcp.fast.corp.example.com` (cheap models)
   - `_llm-chat._tcp.smart.corp.example.com` (high-capability)
   - `_llm-chat._tcp.pii.corp.example.com` (compliant)

3. **Implement health checking:**
   - Script to check endpoint health
   - Automatically disable failed endpoints
   - Update zone files dynamically

4. **Set up monitoring:**
   - Track query patterns
   - Monitor endpoint selection distribution
   - Alert on DNS resolution failures

## Reference Files

All example files are in the `examples/bind/` directory:
- `named.conf` - Main configuration with views
- `internal/corp.example.com.zone` - Internal network zone
- `external/corp.example.com.zone` - External network zone
- `finance/corp.example.com.zone` - Finance network zone
- `engineering/corp.example.com.zone` - Engineering network zone

## Security Considerations

1. **DNSSEC**: Sign zones for production
   ```bash
   dnssec-keygen -a RSASHA256 -b 2048 -n ZONE corp.example.com
   dnssec-signzone -o corp.example.com corp.example.com.zone
   ```

2. **Zone transfers**: Restricted by default (`allow-transfer { none; }`)

3. **Query ACLs**: Each view restricts queries to appropriate networks

4. **Logging**: Enable for security audit
   ```bind
   logging {
       channel query_log {
           file "/var/log/named/queries.log" versions 3 size 5m;
           severity info;
       };
       category queries { query_log; };
   };
   ```

## Support Resources

- [RFC 2782](https://datatracker.ietf.org/doc/html/rfc2782) - DNS SRV specification
- [BIND 9 Documentation](https://bind9.readthedocs.io/)
- Project README.md for architecture overview
- SPECIFICATION.md for detailed protocol info
