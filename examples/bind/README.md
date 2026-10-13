# BIND Configuration for LLM SRV Discovery

This directory contains a complete BIND9 configuration demonstrating split-horizon DNS for LLM endpoint discovery.

## Architecture

**Split-horizon DNS** returns different SRV records based on client IP subnet:

| Client Subnet | View | Behavior |
|---------------|------|----------|
| `10.1.0.0/16` | `finance` | Only compliant, audited, on-prem endpoints |
| `10.2.0.0/16` | `engineering` | Full access including experimental models |
| `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | `internal` | Gets on-prem endpoints first, cloud as backup |
| All other IPs | `external` | Only public cloud endpoints |

Views are declared most-specific-first in `named.conf` (finance and
engineering before internal) because BIND uses the **first** view whose
`match-clients` matches — and the finance/engineering subnets are
subsets of the internal `10.0.0.0/8` ACL.

## Files

```
bind/
├── named.conf                           # Main BIND config with ACLs and views
├── internal/
│   ├── corp.example.com.zone           # Internal network zone
│   └── dev.corp.example.com.zone       # Development zone
├── finance/
│   └── corp.example.com.zone           # Finance dept (compliance-focused)
├── engineering/
│   └── corp.example.com.zone           # Engineering dept (full access)
└── external/
    └── corp.example.com.zone           # External/internet zone
```

## Installation

### 1. Install BIND9

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install bind9 bind9-utils bind9-doc
```

**RHEL/CentOS/Fedora:**
```bash
sudo dnf install bind bind-utils
```

**macOS:**
```bash
brew install bind
```

### 2. Copy Configuration

```bash
# Backup existing config
sudo cp /etc/bind/named.conf /etc/bind/named.conf.backup

# Copy our config
sudo cp named.conf /etc/bind/named.conf

# Create directory structure
sudo mkdir -p /var/named/{internal,external,finance,engineering}

# Copy zone files
sudo cp internal/*.zone /var/named/internal/
sudo cp external/*.zone /var/named/external/
sudo cp finance/*.zone /var/named/finance/
sudo cp engineering/*.zone /var/named/engineering/

# Set permissions (Debian/Ubuntu runs BIND as user "bind";
# RHEL/CentOS/Fedora runs it as user "named" - adjust accordingly)
sudo chown -R bind:bind /var/named/     # Debian/Ubuntu
# sudo chown -R named:named /var/named/ # RHEL/CentOS/Fedora
sudo chmod 755 /var/named
sudo chmod 644 /var/named/*/*.zone
```

### 3. Validate Configuration

```bash
# Check named.conf syntax
sudo named-checkconf /etc/bind/named.conf

# Check zone files
sudo named-checkzone corp.example.com /var/named/internal/corp.example.com.zone
sudo named-checkzone corp.example.com /var/named/external/corp.example.com.zone
sudo named-checkzone corp.example.com /var/named/finance/corp.example.com.zone
sudo named-checkzone corp.example.com /var/named/engineering/corp.example.com.zone
sudo named-checkzone dev.corp.example.com /var/named/internal/dev.corp.example.com.zone
```

### 4. Start BIND

```bash
# Start service
sudo systemctl start named

# Enable on boot
sudo systemctl enable named

# Check status
sudo systemctl status named

# View logs
sudo journalctl -u named -f
```

## Testing

### Test from Internal Network

```bash
# Query from any machine with an internal IP (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
dig @<bind-server> SRV _llm-chat._tcp.corp.example.com

# Expected: Should return local GPU cluster first
# _llm-chat._tcp.corp.example.com. 300 IN SRV 10 70 8080 llm-gpu-cluster.internal.corp.example.com.
```

### Test Finance View

```bash
# Query from a machine on the finance subnet (10.1.x.x)
dig @<bind-server> SRV _llm-chat._tcp.corp.example.com

# Expected: Only compliant on-prem endpoints
# _llm-chat._tcp.corp.example.com. 300 IN SRV 10 100 8443 llm-secure.internal.corp.example.com.
```

(To test without a finance machine, you can add a temporary test IP from
the subnet to your own host and use `dig -b <that-ip> @<bind-server> ...`;
`-b` requires the source address to be configured on the querying host.)

### Test Engineering View

```bash
# Query from a machine on the engineering subnet (10.2.x.x)
dig @<bind-server> SRV _llm-chat._tcp.corp.example.com

# Expected: All endpoints including experimental
# Multiple SRV records with experimental models
```

### Test External View

```bash
# Query from a machine with a public IP
dig @<bind-server> SRV _llm-chat._tcp.corp.example.com

# Expected: Only public cloud endpoints
# _llm-chat._tcp.corp.example.com. 3600 IN SRV 10 50 443 api-gateway-us.corp.example.com.
```

### Query TXT Records for Metadata

```bash
dig @localhost TXT _llm-chat._tcp.corp.example.com

# Expected metadata:
# "path=/v1/messages"
# "provider=mixed"
# "protocol=openai-compatible"
```

### Test Different Capabilities

```bash
# Embeddings
dig @localhost SRV _llm-embedding._tcp.corp.example.com

# Vision
dig @localhost SRV _llm-vision._tcp.corp.example.com

# Code
dig @localhost SRV _llm-code._tcp.corp.example.com

# Image generation
dig @localhost SRV _llm-image-gen._tcp.corp.example.com
```

### Test Policy Subdomains

```bash
# Fast/cheap models
dig @localhost SRV _llm-chat._tcp.fast.corp.example.com

# High-capability models
dig @localhost SRV _llm-chat._tcp.smart.corp.example.com

# PII-compliant endpoints
dig @localhost SRV _llm-chat._tcp.pii.corp.example.com
```

## View Differences Summary

### Internal View
- **Priority 10**: Local GPU cluster (70%), local CPU (30%)
- **Priority 20**: Cloud providers as backup
- **Endpoints**: Mix of on-prem and cloud

### Finance View
- **Priority 10**: Only `llm-secure.internal` (SOC2/HIPAA compliant)
- **No cloud backup** - all data stays on-prem
- **No vision/image-gen** - policy restricted

### Engineering View
- **Priority 10**: GPU cluster (40%), experimental (30%), cloud (15% + 15% across two providers)
- **Priority 20**: CPU fallback
- **All capabilities** enabled including audio, reranking
- **Mock endpoints** for CI/CD testing

### External View
- **Priority 10**: Cloud API gateways only
- **No internal IPs** exposed
- **Limited capabilities** (no experimental access)

## Monitoring

### Query Logging

Query logging is already configured in `named.conf` (channel
`query_log`, writing to `/var/log/named/queries.log` with rotation
`versions 5 size 10m`). Adjust the rotation parameters there if you
need more history:

```
channel query_log {
    file "/var/log/named/queries.log" versions 5 size 10m;
    severity info;
    print-time yes;
};
```

### Watch Queries in Real-time

```bash
sudo tail -f /var/log/named/queries.log
```

### Analyze Query Patterns

```bash
# Most queried services
sudo grep "query.*SRV" /var/log/named/queries.log | \
  awk '{print $6}' | sort | uniq -c | sort -rn

# Queries by client IP
sudo grep "query.*SRV" /var/log/named/queries.log | \
  awk '{print $4}' | cut -d'#' -f1 | sort | uniq -c | sort -rn
```

## Security

### Enable DNSSEC

```bash
# Generate keys
cd /var/named
sudo dnssec-keygen -a RSASHA256 -b 2048 -n ZONE corp.example.com
sudo dnssec-keygen -a RSASHA256 -b 2048 -f KSK -n ZONE corp.example.com

# Sign zone (/dev/urandom - never blocks, unlike /dev/random)
sudo dnssec-signzone -A -3 $(head -c 1000 /dev/urandom | sha1sum | cut -b 1-16) \
  -N INCREMENT -o corp.example.com \
  -t internal/corp.example.com.zone

# Update named.conf to use .signed files
```

### Restrict Zone Transfers

Already configured in `named.conf`:

```
allow-transfer { none; };
```

### ACL Best Practices

The ACLs in `named.conf` define the shipped demo networks. Customize
them to your environment — keep the most specific subnets (finance,
engineering) as separate ACLs and declare their views before the
broader internal view:

```
acl internal-network {
    10.0.0.0/8;      # Your internal network
    172.16.0.0/12;   # Private network ranges
    192.168.0.0/16;  # Private network ranges
    localhost;
    localnets;
};

acl finance-network {
    10.1.0.0/16;     # Finance department subnet
};
```

## Troubleshooting

### Check BIND is listening

```bash
sudo netstat -tulpn | grep named
# Should show: tcp 0.0.0.0:53 LISTEN named
```

### Test configuration reload

```bash
sudo rndc reload
sudo rndc status
```

### View which view is matching

```bash
# Query and check logs to see which view matched
dig @localhost SRV _llm-chat._tcp.corp.example.com
sudo tail /var/log/named/default.log
```

### Common errors

**Error: `zone corp.example.com/IN: loading from master file failed`**
- Check zone file syntax with `named-checkzone`
- Verify file permissions are readable by bind user

**Error: `none:0: open: /etc/bind/rndc.key: file not found`**
- Generate rndc key: `sudo rndc-confgen -a`

**No SRV records returned:**
- Verify zone file has correct service names
- Check TTL hasn't expired negatively
- Ensure view ACLs match your client IP

## Production Considerations

1. **Update Serial Numbers**: Increment serial in SOA when changing zone files
2. **Reload Zones**: Run `sudo rndc reload` after changes
3. **Monitor TTLs**: Adjust TTLs based on change frequency
4. **Backup Configuration**: Regularly backup zone files
5. **High Availability**: Run secondary BIND servers with zone transfers
6. **Automate Updates**: Use dynamic DNS updates or automation for endpoint changes

## Next Steps

- Configure health checking to automatically remove failed endpoints
- Set up BIND statistics monitoring
- Implement automated zone file generation from inventory
- Configure BIND notifications for zone updates
- Set up slave/secondary DNS servers for redundancy
