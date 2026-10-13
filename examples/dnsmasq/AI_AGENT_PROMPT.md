# dnsmasq Configuration for LLM Discovery - AI Agent Implementation Guide

## Purpose
You are tasked with implementing DNS SRV-based LLM endpoint discovery using dnsmasq - a lightweight DNS forwarder perfect for local development and testing.

## What This Accomplishes

dnsmasq provides:

1. **Lightweight DNS** - Small footprint, fast startup, minimal configuration
2. **Development-Friendly** - Text-file configuration, easy iteration
3. **Local Testing** - Perfect for testing LLM discovery before production deployment
4. **Zero Dependencies** - Often pre-installed on macOS and Linux

## Use Cases

- **Local Development** - Test discovery without setting up BIND/PowerDNS
- **CI/CD Testing** - Automated testing with ephemeral DNS
- **Docker Compose Integration** - Service discovery in containerized environments
- **Team Development** - Consistent DNS configuration across team

## Prerequisites

- dnsmasq installed (or will install)
- Basic shell access
- Ports 53 or 5353 available

## Implementation Steps

### Step 1: Install dnsmasq

**macOS:**
```bash
brew install dnsmasq
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install dnsmasq
```

**RHEL/CentOS/Fedora:**
```bash
sudo dnf install dnsmasq
```

### Step 2: Stop System DNS (if conflicting)

**If port 53 is in use, prefer the non-standard port (5353) that this
guide uses — it avoids the conflict entirely:**

```bash
# Check what's using port 53
sudo lsof -i :53
```

Only stop systemd-resolved if you fully understand the impact (it breaks
system name resolution until restarted) and know how to restore it:

```bash
sudo systemctl stop systemd-resolved
# ... later, to restore:
sudo systemctl start systemd-resolved
```

### Step 3: Create Configuration Directory

```bash
sudo mkdir -p /etc/dnsmasq.d
sudo chmod 755 /etc/dnsmasq.d
```

### Step 4: Create Main Configuration

**Create `/etc/dnsmasq.conf` (or edit existing):**

```conf
# Listen address (localhost only for security)
listen-address=127.0.0.1

# Use port 5353 to avoid conflicts
# Change to 53 if you want dnsmasq as primary DNS
port=5353

# Don't read /etc/resolv.conf
no-resolv

# Don't read /etc/hosts
no-hosts

# Domain for local development
domain=dev.local
local=/dev.local/

# Expand simple names
expand-hosts

# Log queries (helpful for debugging)
log-queries

# Cache size
cache-size=1000

# Negative TTL (short for development)
neg-ttl=60
local-ttl=60

# Include additional configs
conf-dir=/etc/dnsmasq.d/,*.conf

# Localhost mappings
address=/localhost/127.0.0.1
address=/localhost/::1
```

**IMPORTANT:** For a shared/production-facing deployment you can change
`listen-address` to `0.0.0.0` and `port` to `53` — but then restrict who
can query dnsmasq (firewall rules, `interface=`/`except-interface=`,
host ACLs). An open resolver on port 53 will be found and abused.

### Step 5: Create LLM Discovery Configuration

**Create `/etc/dnsmasq.d/llm-discovery.conf`:**

```conf
# =============================================================================
# LLM Discovery SRV Records
# Format: srv-host=<service>.<protocol>.<domain>,<target>,<port>,<priority>,<weight>
# =============================================================================

# CHAT COMPLETION
# Primary: Local mock server
srv-host=_llm-chat._tcp.dev.local,localhost,3000,10,70

# Backup: Shared dev server (if available)
# srv-host=_llm-chat._tcp.dev.local,dev-llm.dev.local,8080,10,30

# Metadata via TXT records
txt-record=_llm-chat._tcp.dev.local,"path=/v1/messages"
txt-record=_llm-chat._tcp.dev.local,"provider=mock"
txt-record=_llm-chat._tcp.dev.local,"protocol=openai-compatible"
txt-record=_llm-chat._tcp.dev.local,"environment=development"
txt-record=_llm-chat._tcp.dev.local,"cost=free"

# EMBEDDING
srv-host=_llm-embedding._tcp.dev.local,localhost,3001,10,100

txt-record=_llm-embedding._tcp.dev.local,"path=/v1/embeddings"
txt-record=_llm-embedding._tcp.dev.local,"provider=mock"
txt-record=_llm-embedding._tcp.dev.local,"dimensions=384"

# VISION
srv-host=_llm-vision._tcp.dev.local,localhost,3002,10,100

txt-record=_llm-vision._tcp.dev.local,"path=/v1/messages"
txt-record=_llm-vision._tcp.dev.local,"provider=mock"

# CODE
srv-host=_llm-code._tcp.dev.local,localhost,3003,10,100

txt-record=_llm-code._tcp.dev.local,"path=/v1/completions"
txt-record=_llm-code._tcp.dev.local,"provider=mock"

# =============================================================================
# POLICY SUBDOMAINS (for testing different tiers)
# =============================================================================

# Fast/cheap tier
srv-host=_llm-chat._tcp.fast.dev.local,localhost,3000,10,100
txt-record=_llm-chat._tcp.fast.dev.local,"tier=fast"
txt-record=_llm-chat._tcp.fast.dev.local,"cost=low"

# Smart/premium tier
srv-host=_llm-chat._tcp.smart.dev.local,localhost,3000,10,100
txt-record=_llm-chat._tcp.smart.dev.local,"tier=premium"
txt-record=_llm-chat._tcp.smart.dev.local,"model=claude-opus-5"

# PII-compliant
srv-host=_llm-chat._tcp.pii.dev.local,localhost,3000,10,100
txt-record=_llm-chat._tcp.pii.dev.local,"compliance=soc2,hipaa"

# =============================================================================
# A RECORDS FOR MOCK SERVERS
# =============================================================================

address=/llm-mock.dev.local/127.0.0.1
```

**NOTE:** The repo's `examples/dnsmasq/llm-discovery.conf` can be copied
to `/etc/dnsmasq.d/` directly instead of retyping this — it contains the
same records plus image-gen and audio capabilities.

**CUSTOMIZATION:**

For production-like testing with real servers:
```conf
# GPU cluster
srv-host=_llm-chat._tcp.corp.local,llm-gpu.local,8080,10,70
address=/llm-gpu.local/10.0.10.100

# CPU fallback
srv-host=_llm-chat._tcp.corp.local,llm-cpu.local,8080,10,30
address=/llm-cpu.local/10.0.10.101

# Cloud backup
srv-host=_llm-chat._tcp.corp.local,llm-cloud.local,443,20,100
address=/llm-cloud.local/10.0.20.10
```

### Step 6: Validate Configuration

```bash
# Test configuration syntax
dnsmasq --test -C /etc/dnsmasq.conf

# Expected output: "dnsmasq: syntax check OK."
```

### Step 7: Start dnsmasq

**For testing (foreground):**
```bash
dnsmasq -C /etc/dnsmasq.conf --no-daemon --log-queries
```

**For production (background service):**
```bash
sudo systemctl start dnsmasq
sudo systemctl enable dnsmasq
sudo systemctl status dnsmasq
```

### Step 8: Test DNS Resolution

```bash
# Test SRV record
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local

# Expected output:
# _llm-chat._tcp.dev.local. 60 IN SRV 10 70 3000 localhost.

# Test TXT record
dig @127.0.0.1 -p 5353 TXT _llm-chat._tcp.dev.local

# Expected output:
# _llm-chat._tcp.dev.local. 60 IN TXT "path=/v1/messages"
# _llm-chat._tcp.dev.local. 60 IN TXT "provider=mock"
```

### Step 9: Test with Discovery Client

From the repository root (adjust paths if you only installed the DNS config):

```bash
# Use the bash discovery script
./llm-discovery --domain dev.local --dns-server 127.0.0.1 --dns-port 5353

# Or with Python client
python3 examples/clients/python/llm_discovery_client.py \
  --domain dev.local \
  --dns-server 127.0.0.1 \
  --dns-port 5353
```

## Production-Like Multi-Endpoint Setup

**For testing failover and load balancing:**

```conf
# Priority 10: Two local endpoints (70/30 weight split)
srv-host=_llm-chat._tcp.test.local,llm-primary.test.local,8080,10,70
srv-host=_llm-chat._tcp.test.local,llm-secondary.test.local,8080,10,30

# Priority 20: Backup endpoint
srv-host=_llm-chat._tcp.test.local,llm-backup.test.local,8080,20,100

# A records
address=/llm-primary.test.local/192.168.1.101
address=/llm-secondary.test.local/192.168.1.102
address=/llm-backup.test.local/192.168.1.103
```

**Client behavior:**
- 70% of requests → llm-primary
- 30% of requests → llm-secondary
- Only tries backup if both primary endpoints fail

## Docker Integration

Perfect for containerized development:

**Dockerfile:**
```dockerfile
FROM alpine:latest
RUN apk add --no-cache dnsmasq
COPY dnsmasq.conf /etc/dnsmasq/dnsmasq.conf
COPY llm-discovery.conf /etc/dnsmasq/llm-discovery.conf
EXPOSE 5353/udp 5353/tcp
WORKDIR /etc/dnsmasq
ENTRYPOINT ["dnsmasq", "-C", "/etc/dnsmasq/dnsmasq.conf", "--no-daemon"]
```

Note: dnsmasq listens on port **5353** (per `dnsmasq.conf`), and the
`conf-file=llm-discovery.conf` include is resolved relative to the
working directory — hence the explicit `-C` and `WORKDIR`.

**docker-compose.yml:**
```yaml
version: '3.8'
services:
  dns:
    build: .
    ports:
      - "5353:5353/udp"
      - "5353:5353/tcp"

  mock-llm-chat:
    image: your-mock-llm:latest
    ports:
      - "3000:3000"

  mock-llm-embedding:
    image: your-mock-llm:latest
    ports:
      - "3001:3000"
```

(`your-mock-llm` is a placeholder for any container image that runs an
OpenAI-compatible mock API — or run the repo's Python mock server
directly on the host instead.)

**Run:**
```bash
docker-compose up -d
dig @localhost -p 5353 SRV _llm-chat._tcp.dev.local
```

## Integration with Existing dnsmasq

### If dnsmasq Already Running

1. **Check current config:**
   ```bash
   ps aux | grep dnsmasq
   cat /etc/dnsmasq.conf
   ```

2. **Add LLM discovery config:**
   ```bash
   sudo cp llm-discovery.conf /etc/dnsmasq.d/
   ```

3. **Reload:**
   ```bash
   sudo killall -HUP dnsmasq
   # Or restart
   sudo systemctl restart dnsmasq
   ```

4. **Test without breaking existing:**
   - Use different domain (dev.local vs existing domains)
   - Verify existing queries still work
   - Test new SRV records

## Team Development Setup

The simplest consistent setup is to run the repo's own configs — every
developer gets identical records because they come from the same commit:

```bash
# From the repository root
(cd examples/dnsmasq && dnsmasq -C dnsmasq.conf --no-daemon &)
```

**Add to your project README:**

```markdown
## Development DNS Setup

Start local DNS for LLM discovery:

\`\`\`bash
(cd examples/dnsmasq && dnsmasq -C dnsmasq.conf --no-daemon &)
\`\`\`

In another terminal, start mock LLM:
\`\`\`bash
python3 examples/clients/python/mock_llm_server.py --port 3000
\`\`\`
```

(If you prefer a system-wide install, follow Steps 3–7 above; just keep
in mind the repo copy and the `/etc` copy can drift apart.)

## CI/CD Integration

**GitHub Actions:**
```yaml
- name: Start DNS and Mock LLM
  run: |
    (cd examples/dnsmasq && dnsmasq -C dnsmasq.conf --no-daemon &)
    python3 examples/clients/python/mock_llm_server.py --port 3000 &
    sleep 2

    # Verify DNS works
    dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short

- name: Run Integration Tests
  run: pytest tests/integration/
```

## Troubleshooting

### dnsmasq won't start

```bash
# Check port 53
sudo lsof -i :53

# Check config
dnsmasq --test -C /etc/dnsmasq.conf

# Check logs
sudo journalctl -u dnsmasq -n 50
```

### No SRV records returned

```bash
# Test directly
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short

# Check dnsmasq loaded config
sudo kill -USR1 $(pidof dnsmasq)
sudo tail /var/log/syslog | grep dnsmasq

# Verify config syntax
grep "srv-host" /etc/dnsmasq.d/llm-discovery.conf
```

### Client can't resolve

```bash
# Check dnsmasq is listening
sudo netstat -tulpn | grep dnsmasq

# Verify port
sudo lsof -i :5353

# Test with explicit server
dig @127.0.0.1 -p 5353 _llm-chat._tcp.dev.local SRV
```

### Cache issues

```bash
# Restart to clear cache
sudo systemctl restart dnsmasq

# Or send HUP signal
sudo killall -HUP dnsmasq
```

## Migration to Production DNS

When ready for production:

### To BIND:

```bash
# Convert SRV records
# srv-host=_llm-chat._tcp.dev.local,localhost,3000,10,70
# Becomes:
# _llm-chat._tcp IN SRV 10 70 3000 localhost.
```

### To PowerDNS:

```sql
INSERT INTO records (domain_id, name, type, content, ttl, prio)
VALUES (1, '_llm-chat._tcp.corp.com', 'SRV', '10 70 3000 localhost', 300, 10);
```

## Production Checklist

If you do deploy dnsmasq beyond a single machine (for real production
DNS, prefer BIND or PowerDNS — see the limitations below):

- [ ] Change port to 53
- [ ] Set listen-address to 0.0.0.0
- [ ] Configure upstream DNS servers
- [ ] Enable DNSSEC if needed
- [ ] Set appropriate TTLs (higher for production)
- [ ] Configure logging
- [ ] Set up monitoring
- [ ] Configure systemd service
- [ ] Test failover scenarios
- [ ] Document all endpoints

## Limitations

- **No split-horizon** - Can't return different records per client IP
- **No database backend** - All configuration in text files
- **Limited scalability** - Not designed for high query volumes
- **No native health checks** - Can't automatically disable failed endpoints
- **Static configuration** - Changes require config reload

**For production, use:**
- BIND for split-horizon DNS
- PowerDNS for dynamic SQL-based management
- dnsmasq for local development and testing only

## Next Steps

1. **Start mock LLM server:**
   ```bash
   python examples/clients/python/mock_llm_server.py --port 3000
   ```

2. **Test discovery:**
   ```bash
   python examples/clients/python/llm_discovery_client.py \
     --domain dev.local --dns-port 5353
   ```

3. **Extend the records:**
   - Additional policy subdomains
   - Production-like multi-endpoint setups (see below)

4. **Integrate with your app:**
   - Use client library
   - Configure DNS server in app

5. **Plan migration to production DNS** when ready

## Reference Files

- `examples/dnsmasq/dnsmasq.conf` - Main configuration
- `examples/dnsmasq/llm-discovery.conf` - SRV/TXT records
- `examples/dnsmasq/README.md` - Detailed usage guide
