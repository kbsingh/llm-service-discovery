# Quick Start Guide

Get started with DNS SRV-based LLM discovery in 5 minutes.

## Prerequisites

- Linux or macOS
- dnsmasq (for local testing)
- Python 3.8+ or Go 1.21+ or Rust 1.70+

## 0. (Optional) Configure System DNS

For the simplest experience, configure your system to use the DNS server.

**Caution:** these changes affect system-wide name resolution. On hosts
managed by `systemd-resolved` (most modern Linux distros), appending
`nameserver 127.0.0.1` to `/etc/resolv.conf` can break resolution —
prefer the `resolvectl` form below, and keep a note of the original
values to roll back:

```bash
# Temporary (rolls back on reboot)
echo "search dev.local" | sudo tee -a /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee -a /etc/resolv.conf

# Or with systemd-resolved (persistent, per-interface):
sudo resolvectl domain lo dev.local
sudo resolvectl dns lo 127.0.0.1
```

Then you can just run `llm-discovery` with no arguments! (Every example
below also works without this step by passing `--dns-server` /
`--dns-port` explicitly.)

## 1. Start DNS Server

### Install dnsmasq

**macOS:**
```bash
brew install dnsmasq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install dnsmasq
```

**RHEL/Fedora:**
```bash
sudo dnf install dnsmasq
```

### Start dnsmasq

```bash
cd examples/dnsmasq
dnsmasq -C dnsmasq.conf --no-daemon --log-queries
```

Keep this terminal open. You should see:
```
dnsmasq: started, version 2.x
dnsmasq: compile time options: ...
```

## 2. Test DNS Resolution

In a new terminal:

```bash
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local

# Expected output:
# _llm-chat._tcp.dev.local. 60 IN SRV 10 70 3000 localhost.
```

## 3. Start Mock LLM Server

In another terminal:

```bash
cd examples/clients/python
pip install -r requirements.txt
python3 mock_llm_server.py --port 3000
```

You should see:
```
INFO:__main__:Starting Mock LLM Server on 0.0.0.0:3000
```

## 4. Run Discovery Client

### Bash (Simplest!)

```bash
# If you set up /etc/resolv.conf with search domain:
# search dev.local
# nameserver 127.0.0.1
./llm-discovery

# Or specify everything explicitly:
./llm-discovery --domain dev.local --dns-server 127.0.0.1 --dns-port 5353
```

### Python

```bash
cd examples/clients/python
python3 llm_discovery_client.py \
  --domain dev.local \
  --dns-server 127.0.0.1 \
  --dns-port 5353
```

### Go

```bash
cd examples/clients/go
go build -o llm-discovery example/main.go
./llm-discovery \
  --domain dev.local \
  --dns-server 127.0.0.1 \
  --dns-port 5353
```

### Rust

```bash
cd examples/clients/rust
cargo build --release
./target/release/llm-discovery-example \
  --domain dev.local \
  --dns-server 127.0.0.1 \
  --dns-port 5353
```

## Expected Output

Running the Python client (step 4) prints (INFO log lines come from the
client's logging, `--verbose` adds more):

```
INFO:__main__:Initialized LLM discovery for domain: dev.local
INFO:__main__:Using custom DNS server: 127.0.0.1:5353
INFO:__main__:Querying SRV records for: _llm-chat._tcp.dev.local
INFO:__main__:Selected chat endpoint: LLMEndpoint(localhost:3000, priority=10, weight=70)

🔍 Discovering chat endpoint...
✅ Discovered endpoint: LLMEndpoint(localhost:3000, priority=10, weight=70)
   URL: http://localhost:3000
   Metadata:
      cost: free
      auth: optional
      environment: development
      protocol: openai-compatible
      provider: mock
      path: /v1/messages

🏥 Checking endpoint health...
✅ Endpoint is healthy
```

## 5. Make an API Call

```bash
curl -X POST http://localhost:3000/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "test",
    "messages": [{"role": "user", "content": "Hello via DNS discovery!"}]
  }'
```

Expected response:
```json
{
  "id": "mock-completion-123",
  "model": "test",
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "[MOCK RESPONSE] You said: Hello via DNS discovery! ..."
    }
  }]
}
```

## What Just Happened?

1. **DNS Resolution**: Client queries `_llm-chat._tcp.dev.local` SRV record
2. **Discovery**: Gets `localhost:3000` with priority 10, weight 70
3. **Metadata**: Fetches TXT records for path, provider info
4. **Connection**: Constructs URL `http://localhost:3000/v1/messages`
5. **API Call**: Makes HTTP request to discovered endpoint

## Next Steps

### Production Setup

1. **Configure BIND or PowerDNS** (see `examples/bind/` or `examples/powerdns/`)
2. **Set up split-horizon DNS** for different networks
3. **Add real LLM endpoints** (OpenAI, provider1, self-hosted)
4. **Configure failover** with multiple SRV records
5. **Implement health checking** to remove failed endpoints

### Explore Features

**Policy-based discovery:**
```bash
python3 llm_discovery_client.py --subdomain fast   # Cheap models
python3 llm_discovery_client.py --subdomain smart  # High-capability
python3 llm_discovery_client.py --subdomain pii    # Compliant
```

**Different capabilities:**
```bash
python3 llm_discovery_client.py --capability embedding
python3 llm_discovery_client.py --capability vision
python3 llm_discovery_client.py --capability code
```

**See all endpoints:**
```bash
python3 llm_discovery_client.py --verbose
```

## Troubleshooting

### DNS not resolving

```bash
# Check dnsmasq is running
ps aux | grep dnsmasq

# Test DNS directly
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short

# Most common cause: dnsmasq was started from a different directory, so
# the relative conf-file include could not be read. Restart it from
# examples/dnsmasq:
cd examples/dnsmasq && dnsmasq -C dnsmasq.conf --no-daemon --log-queries
```

### Mock server not responding

```bash
# Check server is running
curl http://localhost:3000/health

# Check port
lsof -i :3000
```

### Client can't connect

```bash
# Verify DNS returns correct endpoint
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local

# Test endpoint manually
curl http://localhost:3000/health
```

## Architecture Overview

```
┌─────────────┐
│   Client    │
│ Application │
└──────┬──────┘
       │
       │ 1. Query SRV: _llm-chat._tcp.dev.local
       │
       ▼
┌─────────────┐
│  dnsmasq    │  Returns: localhost:3000 (priority 10, weight 70)
│  DNS Server │
└──────┬──────┘
       │ 2. Query TXT (metadata)
       │
       ▼
┌─────────────┐
│  Discovery  │  Constructs: http://localhost:3000/v1/messages
│   Client    │
└──────┬──────┘
       │ 3. HTTP POST
       │
       ▼
┌─────────────┐
│   Mock LLM  │  Returns: Mock response
│   Server    │
└─────────────┘
```

## Real-World Example

In production with multiple providers:

**DNS Configuration:**
```dns
_llm-chat._tcp.corp.com. IN SRV 10 50 443 provider1-proxy.corp.com.
_llm-chat._tcp.corp.com. IN SRV 10 50 443 openai-proxy.corp.com.
_llm-chat._tcp.corp.com. IN SRV 20 100 8080 local-llama.corp.com.
```

**Client Code:**
```python
from llm_discovery_client import LLMDiscoveryClient

client = LLMDiscoveryClient(
    domain="corp.com",
    dns_server="10.0.1.10"
)

# Automatic failover: tries provider1/OpenAI first (50/50)
# Falls back to local Llama if both fail
endpoint = client.discover_chat()

# Use endpoint
response = client.chat(endpoint, "Hello!", api_key=os.getenv("API_KEY"))
```

**Benefits:**
- ✅ No hardcoded endpoints
- ✅ Automatic failover
- ✅ Load balancing (50/50 between cloud providers)
- ✅ Centralized configuration (via DNS)
- ✅ Different endpoints per network (split-horizon)

## Documentation

- [README.md](README.md) - Full proposal and overview
- [SPECIFICATION.md](SPECIFICATION.md) - Technical specification
- [examples/bind/](examples/bind/) - BIND configuration
- [examples/powerdns/](examples/powerdns/) - PowerDNS with SQL
- [examples/dnsmasq/](examples/dnsmasq/) - Lightweight DNS
- [examples/clients/](examples/clients/) - Client implementations

## Support

- Report issues on GitHub
- See specification for RFC 2782 details
- Check example configurations for your DNS server
