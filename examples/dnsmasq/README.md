# dnsmasq Configuration for LLM SRV Discovery

dnsmasq is a lightweight DNS forwarder perfect for local development and testing of LLM discovery.

## Why dnsmasq?

- **Lightweight**: Small footprint, fast startup
- **Simple**: Text file configuration, no database
- **Development-friendly**: Great for local testing
- **Built-in**: Often pre-installed on macOS and Linux

## Files

```
dnsmasq/
├── README.md            # This file
├── dnsmasq.conf         # Main configuration
└── llm-discovery.conf   # LLM SRV records
```

## Quick Start

### 1. Install dnsmasq

**macOS:**
```bash
brew install dnsmasq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install dnsmasq
```

**RHEL/CentOS/Fedora:**
```bash
sudo dnf install dnsmasq
```

### 2. Run From the Repo (No Install)

The main config includes `llm-discovery.conf` by relative path, so start
dnsmasq **from this directory**:

```bash
cd examples/dnsmasq
dnsmasq -C dnsmasq.conf --no-daemon --log-queries
```

Verify it is answering (this is the real test — a syntax check alone
won't catch a missing include):

```bash
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short
# expected: 10 70 3000 localhost.
```

### 3. System-Wide Install (Optional)

```bash
# Copy configs
sudo cp dnsmasq.conf /etc/dnsmasq.conf
sudo cp llm-discovery.conf /etc/dnsmasq.d/llm-discovery.conf

# The system-wide main config must include the records via the
# system conf-dir instead of the repo-relative conf-file:
sudo sed -i 's|^conf-file=llm-discovery.conf$|conf-dir=/etc/dnsmasq.d/,*.conf|' /etc/dnsmasq.conf

# Test and start
dnsmasq --test -C /etc/dnsmasq.conf
sudo systemctl start dnsmasq
sudo systemctl enable dnsmasq
```

### 4. Test Queries

```bash
# Query chat endpoint
dig @localhost -p 5353 SRV _llm-chat._tcp.dev.local

# Get TXT metadata
dig @localhost -p 5353 TXT _llm-chat._tcp.dev.local
```

## Configuration Overview

### dnsmasq.conf

Main configuration file:

```conf
# Listen on localhost only (safe for development)
listen-address=127.0.0.1

# Use port 5353 to avoid conflict with system DNS
port=5353

# Don't read /etc/resolv.conf
no-resolv

# Don't read /etc/hosts
no-hosts

# Log queries
log-queries

# Include LLM discovery records (relative to the directory dnsmasq
# is started from - see the comment in dnsmasq.conf for details)
conf-file=llm-discovery.conf
```

### llm-discovery.conf

LLM SRV records for development (excerpt — the file also defines code,
image-gen and audio capabilities plus policy subdomains like
`fast`, `smart` and `pii`):

```conf
# Chat completion - localhost mock server
srv-host=_llm-chat._tcp.dev.local,localhost,3000,10,70

# Embedding - localhost mock
srv-host=_llm-embedding._tcp.dev.local,localhost,3001,10,100

# Vision - localhost mock
srv-host=_llm-vision._tcp.dev.local,localhost,3002,10,100

# TXT records for metadata
txt-record=_llm-chat._tcp.dev.local,"path=/v1/messages"
txt-record=_llm-chat._tcp.dev.local,"provider=mock"
txt-record=_llm-chat._tcp.dev.local,"environment=development"
```

## Subnet-Based Responses

dnsmasq does not natively support returning different answers per client
subnet. If you need split-horizon behavior (different endpoints for
finance/engineering/internal networks), use the BIND or PowerDNS examples
in this repository — they implement it properly.

For simple cases you can run multiple dnsmasq instances, each with its
own config and interface/port:

```bash
# Instance for the finance network
dnsmasq -C finance-dnsmasq.conf --interface=eth1

# Instance for the engineering network
dnsmasq -C engineering-dnsmasq.conf --interface=eth2
```

(Write each `*-dnsmasq.conf` by copying `dnsmasq.conf` and editing the
`srv-host`/`txt-record` entries in `llm-discovery.conf` to match the
policy for that network.)

## Production-Like Testing

### Simulate Multiple Endpoints with Priorities

```conf
# Priority 10: Local GPU cluster (70% weight)
srv-host=_llm-chat._tcp.corp.local,llm-gpu.local,8080,10,70

# Priority 10: Local CPU fallback (30% weight)
srv-host=_llm-chat._tcp.corp.local,llm-cpu.local,8080,10,30

# Priority 20: Cloud backup (100% weight)
srv-host=_llm-chat._tcp.corp.local,llm-cloud.local,443,20,100

# A records for targets
address=/llm-gpu.local/10.0.10.100
address=/llm-cpu.local/10.0.10.101
address=/llm-cloud.local/10.0.20.10
```

### Multiple Capabilities

```conf
# Chat
srv-host=_llm-chat._tcp.corp.local,localhost,3000,10,100

# Embedding
srv-host=_llm-embedding._tcp.corp.local,localhost,3001,10,100

# Vision
srv-host=_llm-vision._tcp.corp.local,localhost,3002,10,100

# Code
srv-host=_llm-code._tcp.corp.local,localhost,3003,10,100
```

## Docker Setup

Handy for containerized development. Note dnsmasq listens on port
**5353** inside the container (per `dnsmasq.conf`), so that is what we
expose and map.

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

**docker-compose.yml:**
```yaml
version: '3.8'
services:
  dns:
    build: .
    ports:
      - "5353:5353/udp"
      - "5353:5353/tcp"
```

Run:
```bash
docker-compose up -d
dig @localhost -p 5353 SRV _llm-chat._tcp.dev.local
```

The mock LLM server is not containerized — run it directly when you need
the full discovery loop:

```bash
python3 examples/clients/python/mock_llm_server.py --port 3000
```

## Integration with /etc/hosts

**Note**: `/etc/hosts` does NOT support SRV records. You need dnsmasq for SRV support.

However, you can combine them:

```conf
# In dnsmasq.conf
# Read /etc/hosts for A records
addn-hosts=/etc/hosts

# SRV records in dnsmasq
srv-host=_llm-chat._tcp.dev.local,my-llm-server,3000,10,100
```

Then in `/etc/hosts`:
```
127.0.0.1  my-llm-server
```

## Monitoring and Debugging

### Enable Query Logging

```conf
# In dnsmasq.conf
log-queries
log-facility=/var/log/dnsmasq.log
```

Watch logs:
```bash
tail -f /var/log/dnsmasq.log
```

### Verbose Mode

```bash
# Run in foreground with verbose output
dnsmasq --no-daemon --log-queries --log-dhcp
```

### Test Configuration

```bash
# Validate config file syntax
dnsmasq --test -C dnsmasq.conf

# REALLY verify it serves records (a syntax pass does not prove the
# records are loaded):
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short

# Check what dnsmasq is listening on
sudo ss -tulpn | grep dnsmasq
```

## Client Configuration

### macOS

```bash
# Add to /etc/resolver/dev.local
nameserver 127.0.0.1
port 5353
```

Test:
```bash
scutil --dns
dig _llm-chat._tcp.dev.local
```

### Linux

```bash
# Add to /etc/systemd/resolved.conf
[Resolve]
DNS=127.0.0.1:5353
Domains=~dev.local

# Restart systemd-resolved
sudo systemctl restart systemd-resolved
```

Or point `/etc/resolv.conf` at dnsmasq:
```bash
nameserver 127.0.0.1
```

## Use Cases

### Local Development

Run mock LLM servers and discover them via DNS:

```bash
# Terminal 1: Start mock server (from the repo root)
python3 examples/clients/python/mock_llm_server.py --port 3000

# Terminal 2: Start dnsmasq
cd examples/dnsmasq && dnsmasq -C dnsmasq.conf --no-daemon

# Terminal 3: Your app
python3 my_app.py  # App discovers LLM at _llm-chat._tcp.dev.local
```

### CI/CD Testing

```yaml
# .github/workflows/test.yml
- name: Start DNS and mock LLM
  run: |
    (cd examples/dnsmasq && dnsmasq -C dnsmasq.conf --no-daemon &)
    python3 examples/clients/python/mock_llm_server.py --port 3000 &
    sleep 1
    dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short

- name: Run integration tests
  run: pytest tests/integration/
```

### Team Consistency

Commit the dnsmasq config to your repo so all developers use the same
DNS setup:

```bash
cd examples/dnsmasq && dnsmasq -C dnsmasq.conf --no-daemon &
```

## Limitations

| Feature | Supported? | Notes |
|---------|-----------|-------|
| SRV records | ✅ Yes | Core feature |
| TXT records | ✅ Yes | Metadata support |
| Subnet-based responses | ⚠️ Limited | Multiple instances only; prefer BIND/PowerDNS |
| DNSSEC | ⚠️ Optional | Enable in config; not shown in this example |
| Dynamic updates | ❌ No | File-based only |
| Health checks | ❌ No | Manual file updates needed |
| Database backend | ❌ No | Text files only |

## Migration to Production

When ready for production, migrate to BIND or PowerDNS:

1. **Recreate the SRV/TXT records as BIND zone files** (see
   `../bind/` for ready-made examples)
2. **Or import into PowerDNS** (see `../powerdns/`):
   ```sql
   INSERT INTO records (name, type, content, ttl)
   VALUES ('_llm-chat._tcp.corp.com', 'SRV', '10 100 8080 llm.corp.com.', 300);
   ```
3. **Update client DNS servers** to point to production DNS

## Troubleshooting

### dnsmasq won't start

```bash
# Check if port 5353 (or 53) is already in use
sudo lsof -i :5353

# Try a different port
dnsmasq --port=5354
```

### No SRV records returned

```bash
# Test dnsmasq directly
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short

# Most common cause: dnsmasq was started from a different directory, so
# the relative conf-file=llm-discovery.conf could not be read. Start it
# from examples/dnsmasq:
cd examples/dnsmasq && dnsmasq -C dnsmasq.conf --no-daemon

# Check config syntax
dnsmasq --test -C dnsmasq.conf

# View what records dnsmasq has loaded
sudo kill -USR1 $(pidof dnsmasq)
sudo tail /var/log/syslog
```

### Caching issues

```bash
# Restart dnsmasq to clear cache
sudo systemctl restart dnsmasq

# Or send HUP signal
sudo killall -HUP dnsmasq
```

## Next Steps

- Create mock LLM servers for testing (see `../clients/` directory)
- Set up automated testing with discovered endpoints
- Plan migration to BIND/PowerDNS for production
- Implement health checking for development endpoints
