# llm-discovery CLI Tool

Universal command-line tool for querying LLM endpoints via DNS SRV records on any Linux/macOS machine with `bash`, `dig`, and `jq`.

## Features

- 🔍 Query SRV records for any capability
- 📊 Multiple output formats (pretty, JSON, CSV)
- 🏥 Built-in health checking
- 🎯 Policy subdomain support
- 📋 Metadata (TXT record) display
- 🎨 Colored, formatted output
- 🐧 Works on any Linux distribution

## Quick Start

```bash
# Make executable
chmod +x llm-discovery

# Query chat endpoints
./llm-discovery --domain dev.local --dns-server 127.0.0.1 --dns-port 5353

# Install globally (optional)
sudo cp llm-discovery /usr/local/bin/
sudo chmod +x /usr/local/bin/llm-discovery

# Use from anywhere
llm-discovery --capability embedding
```

## Installation

### Requirements

```bash
# RHEL/CentOS/Fedora
sudo dnf install bind-utils jq

# Ubuntu/Debian
sudo apt-get install dnsutils jq

# macOS
brew install bind jq
```

### Install Script

```bash
# Copy to /usr/local/bin
sudo install -m 755 llm-discovery /usr/local/bin/

# Verify installation
llm-discovery --help
```

## Usage

### Basic Query (Uses System DNS Search Domains)

By default, `llm-discovery` uses your system's DNS search domains from `/etc/resolv.conf`:

```bash
# Simplest usage - uses search domains from /etc/resolv.conf
llm-discovery
```

If your `/etc/resolv.conf` contains:
```
search corp.example.com
nameserver 10.0.1.10
```

Then `llm-discovery` automatically queries `_llm-chat._tcp.corp.example.com`

### Query with Explicit Domain

```bash
llm-discovery --domain corp.example.com
```

Output:
```
🔍 LLM Discovery Results
━━━━━━━━━━━━━━━━━━━━━━

  Capability: chat
  Domain:     corp.example.com

1. llm-gpu-cluster.internal.corp.example.com
   URL:      http://llm-gpu-cluster.internal.corp.example.com:8080
   Port:     8080
   Priority: 10 (lower = preferred)
   Weight:   70 (higher = more likely)

2. llm-cpu-fallback.internal.corp.example.com
   URL:      http://llm-cpu-fallback.internal.corp.example.com:8080
   Port:     8080
   Priority: 10 (lower = preferred)
   Weight:   30 (higher = more likely)

✅ Selected endpoint: llm-gpu-cluster.internal.corp.example.com:8080
   (Priority 10, Weight 70)
```

### Query Different Capabilities

```bash
# Embedding
llm-discovery --capability embedding

# Vision
llm-discovery --capability vision

# Code
llm-discovery --capability code

# Image generation
llm-discovery --capability image-gen
```

### Use Policy Subdomains

```bash
# Fast/cheap models
llm-discovery --subdomain fast

# High-capability models
llm-discovery --subdomain smart

# PII-compliant endpoints
llm-discovery --subdomain pii

# Experimental models
llm-discovery --subdomain experimental
```

### Custom DNS Server

```bash
# Use specific DNS server and port
llm-discovery \
  --dns-server 10.0.1.10 \
  --dns-port 53

# For dnsmasq on non-standard port
llm-discovery \
  --dns-server 127.0.0.1 \
  --dns-port 5353
```

### Show All Endpoints

```bash
# Show all available endpoints (not just selected one)
llm-discovery --all
```

Output shows complete priority/weight distribution.

### Health Checking

```bash
# Check endpoint health
llm-discovery --health
```

> **Note:** health checks connect to hosts learned from DNS. In environments
> where the DNS data is not fully trusted (e.g., unauthenticated DNS or a
> resolver you don't control), keep in mind that `--health` will make HTTP
> requests to whatever hosts the SRV records advertise.

Output:
```
1. llm-gpu-cluster.internal.corp.example.com
   URL:      http://llm-gpu-cluster.internal.corp.example.com:8080
   Port:     8080
   Priority: 10
   Weight:   70
   Health:   ✅ healthy

2. provider1-proxy.corp.example.com
   URL:      https://provider1-proxy.corp.example.com:443
   Port:     443
   Priority: 20
   Weight:   50
   Health:   ❌ down
```

### JSON Output

```bash
llm-discovery --format json
```

Output:
```json
[
  {
    "target": "llm-gpu-cluster.internal.corp.example.com",
    "port": 8080,
    "priority": 10,
    "weight": 70,
    "url": "http://llm-gpu-cluster.internal.corp.example.com:8080",
    "health": "unknown",
    "metadata": {
      "path": "/v1/messages",
      "provider": "mixed",
      "protocol": "openai-compatible",
      "auth": "required"
    }
  },
  {
    "target": "llm-cpu-fallback.internal.corp.example.com",
    "port": 8080,
    "priority": 10,
    "weight": 30,
    "url": "http://llm-cpu-fallback.internal.corp.example.com:8080",
    "health": "unknown",
    "metadata": {
      "path": "/v1/messages",
      "provider": "mixed",
      "protocol": "openai-compatible",
      "auth": "required"
    }
  }
]
```

TXT metadata is included as a `metadata` object in JSON output (disable with `--no-metadata`). CSV output does not include metadata.

### CSV Output

```bash
llm-discovery --format csv
```

Output:
```csv
target,port,priority,weight,url,health
llm-gpu-cluster.internal.corp.example.com,8080,10,70,http://llm-gpu-cluster.internal.corp.example.com:8080,unknown
llm-cpu-fallback.internal.corp.example.com,8080,10,30,http://llm-cpu-fallback.internal.corp.example.com:8080,unknown
```

Perfect for piping to other tools or importing to spreadsheets.

## System DNS Configuration

The tool uses your system's DNS resolver by default. Configure `/etc/resolv.conf`:

**For production:**
```bash
# /etc/resolv.conf
search corp.example.com
nameserver 10.0.1.10
nameserver 10.0.1.11
```

Now `llm-discovery` (without any arguments) automatically queries your corporate DNS!

**For local testing with dnsmasq:**
```bash
# Temporary - edit /etc/resolv.conf
search dev.local
nameserver 127.0.0.1

# Or use systemd-resolved
sudo resolvectl domain eth0 dev.local
sudo resolvectl dns eth0 127.0.0.1
```

## Environment Variables

Set defaults via environment variables:

```bash
export LLM_DISCOVERY_DOMAIN="corp.example.com"  # Override search domains
export LLM_DISCOVERY_DNS_SERVER="10.0.1.10"
export LLM_DISCOVERY_DNS_PORT="53"

# Now can use without flags
llm-discovery --capability embedding
```

Add to `~/.bashrc` or `~/.zshrc` for persistence:

```bash
# LLM Discovery defaults
export LLM_DISCOVERY_DOMAIN="corp.example.com"
export LLM_DISCOVERY_DNS_SERVER="10.0.1.10"
```

## Advanced Usage

### Pipe to jq for Processing

```bash
# Get just the URLs
llm-discovery --format json | jq -r '.[].url'

# Get endpoint with highest weight
llm-discovery --format json | jq 'max_by(.weight)'

# Filter by health status
llm-discovery --format json --health | jq '.[] | select(.health == "healthy")'
```

### Use in Scripts

```bash
#!/bin/bash

# Get chat endpoint
ENDPOINT=$(llm-discovery --format json | jq -r '.[0].url')

# Make request ( may need API_KEY )
curl -X POST "${ENDPOINT}/v1/messages" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Monitor Endpoints

```bash
# Check health every 30 seconds
watch -n 30 'llm-discovery --health --all'

# Log to file
llm-discovery --format csv --health > endpoints_$(date +%Y%m%d_%H%M%S).csv
```

### Test Failover

```bash
# Show all endpoints with priority
llm-discovery --all

# Simulate primary failure (disable in DNS or firewall)
# Run again to see if backup is selected
llm-discovery --verbose
```

## Integration Examples

### Shell Script

```bash
#!/bin/bash
set -e

# Discover endpoint
ENDPOINT=$(llm-discovery --domain corp.example.com --format json | jq -r '.[0]')
URL=$(echo "$ENDPOINT" | jq -r '.url')
TARGET=$(echo "$ENDPOINT" | jq -r '.target')

echo "Using LLM endpoint: $TARGET"
echo "URL: $URL"

# Make API call
curl -sf "$URL/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "test"}]}' \
  | jq '.choices[0].message.content'
```

### Python Integration

```python
import subprocess
import json

def discover_llm_endpoint(capability="chat", subdomain=None):
    """Discover LLM endpoint using CLI tool"""
    cmd = ["llm-discovery", "--format", "json", "--capability", capability]
    
    if subdomain:
        cmd.extend(["--subdomain", subdomain])
    
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    endpoints = json.loads(result.stdout)
    
    return endpoints[0] if endpoints else None

# Use it
endpoint = discover_llm_endpoint("chat", subdomain="fast")
print(f"Using: {endpoint['url']}")
```

### Ansible Playbook

```yaml
- name: Discover LLM endpoint
  command: llm-discovery --format json --capability chat
  register: llm_discovery
  changed_when: false

- name: Parse endpoint
  set_fact:
    llm_endpoint: "{{ (llm_discovery.stdout | from_json)[0] }}"

- name: Configure application
  template:
    src: config.j2
    dest: /etc/myapp/config.yaml
  vars:
    llm_url: "{{ llm_endpoint.url }}"
```

### Kubernetes Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: llm-discovery-check
spec:
  template:
    spec:
      containers:
      - name: discovery
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          apk add --no-cache bind-tools jq curl bash
          # Publish the llm-discovery script somewhere you control and
          # download it here (URL below is a placeholder)
          curl -L https://your-repo.example/llm-discovery -o /usr/local/bin/llm-discovery
          chmod +x /usr/local/bin/llm-discovery
          llm-discovery --health --all
      restartPolicy: Never
```

## Troubleshooting

### No endpoints found

```bash
# Check DNS resolution manually
dig @your-dns-server SRV _llm-chat._tcp.your-domain.com

# Use verbose mode
llm-discovery --verbose

# Verify DNS server is reachable
ping your-dns-server
```

### "Missing required commands"

```bash
# Install dependencies
sudo dnf install bind-utils jq     # RHEL/CentOS
sudo apt-get install dnsutils jq   # Debian/Ubuntu
brew install bind jq               # macOS
```

### Wrong endpoint selected

```bash
# Show all endpoints with priorities
llm-discovery --all

# Verify SRV record priority/weight
dig @your-dns-server SRV _llm-chat._tcp.your-domain.com
```

### Health check fails

```bash
# Check endpoint is reachable
curl -I http://endpoint:port/health

# Firewall may be blocking
telnet endpoint port

# Try without health check first
llm-discovery --no-metadata
```

## Complete Command Reference

```
llm-discovery [OPTIONS]

OPTIONS:
  -d, --domain DOMAIN         DNS domain
  -s, --dns-server SERVER     DNS server address
  -p, --dns-port PORT         DNS port (default: 53)
  -c, --capability TYPE       chat|embedding|vision|code|audio|image-gen|rerank
  -u, --subdomain SUB         Policy subdomain
  -a, --all                   Show all endpoints
  -m, --no-metadata           Skip TXT metadata
  -H, --health                Check endpoint health
  -f, --format FORMAT         pretty|json|csv
  -v, --verbose               Verbose output
  -h, --help                  Show help

ENVIRONMENT VARIABLES:
  LLM_DISCOVERY_DOMAIN        Default domain
  LLM_DISCOVERY_DNS_SERVER    Default DNS server
  LLM_DISCOVERY_DNS_PORT      Default DNS port
```

## Examples

```bash
# Basic query
llm-discovery

# Different capability with custom DNS
llm-discovery --capability embedding --dns-server 10.0.1.10

# Policy subdomain with health check
llm-discovery --subdomain pii --health

# JSON output for scripting
llm-discovery --format json | jq '.[0].url'

# CSV for spreadsheet
llm-discovery --format csv > endpoints.csv

# All endpoints with metadata
llm-discovery --all --verbose

# Local dnsmasq testing
llm-discovery --domain dev.local --dns-server 127.0.0.1 --dns-port 5353
```

## Tips

1. **Use environment variables** for repeated queries in the same environment
2. **JSON format** is best for scripting and integration
3. **CSV format** is good for reports and spreadsheets
4. **Health checking** adds latency - use only when needed
5. **Verbose mode** helps debug DNS resolution issues
6. **All mode** shows complete priority/weight distribution

## See Also

- [README.md](README.md) - Project overview
- [SPECIFICATION.md](SPECIFICATION.md) - Technical specification
- [QUICKSTART.md](QUICKSTART.md) - Getting started guide
- [examples/clients/](examples/clients/) - Client library implementations
