# LLM Discovery Client Examples

Client implementations for discovering and using LLM endpoints via DNS SRV records.

## Available Clients

### Python

Full-featured client with SRV resolution, weighted selection, and health checking.

**Features:**
- RFC 2782 compliant SRV record resolution
- Priority and weight-based endpoint selection
- TXT record metadata parsing
- Health checking
- Multiple capability discovery (chat, embedding, vision, code)
- Policy-based subdomain support

**Installation:**
```bash
cd python
pip install -r requirements.txt
```

**Usage:**
```bash
# Discover and test chat endpoint
python3 llm_discovery_client.py --domain dev.local --dns-server 127.0.0.1 --dns-port 5353

# Use policy subdomain
python3 llm_discovery_client.py --domain corp.example.com --subdomain fast

# Discover embedding endpoint
python3 llm_discovery_client.py --domain dev.local --capability embedding
```

### Go

Zero-dependency client (Go standard library only), with an example CLI in `example/`.

**Usage:**
```bash
cd go
go build -o llm-discovery-example ./example
./llm-discovery-example --domain dev.local --dns-server 127.0.0.1 --dns-port 5353
```

### Rust

Async client built on tokio, with an example CLI at `src/bin/example.rs`.

**Usage:**
```bash
cd rust
cargo build --release
./target/release/llm-discovery-example --domain dev.local --dns-server 127.0.0.1 --dns-port 5353
```

## Quick Start

### 1. Start dnsmasq (in one terminal)

```bash
cd ../dnsmasq
dnsmasq -C dnsmasq.conf --no-daemon --log-queries
```

### 2. Start Mock LLM Server (in another terminal)

```bash
cd python
python3 mock_llm_server.py --port 3000
```

### 3. Run Discovery Client (in a third terminal)

```bash
cd python
python3 llm_discovery_client.py \
  --domain dev.local \
  --dns-server 127.0.0.1 \
  --dns-port 5353 \
  --message "Hello from DNS discovery!" \
  --verbose
```

Expected output (INFO lines come from the client's logging):
```
INFO:__main__:Querying SRV records for: _llm-chat._tcp.dev.local
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
```

## Integration Example

### Python Application

```python
from llm_discovery_client import LLMDiscoveryClient

# Initialize client
client = LLMDiscoveryClient(
    domain="corp.example.com",
    dns_server="10.0.1.10"  # Your DNS server
)

# Discover chat endpoint (with automatic failover)
endpoint = client.discover_chat()

if endpoint:
    print(f"Using LLM at: {endpoint.base_url}")

    # Send chat request
    response = client.chat(
        endpoint=endpoint,
        message="Explain DNS SRV records",
        api_key="your-api-key"
    )

    print(response)
```

### Policy-Based Discovery

```python
# Use fast/cheap models
fast_endpoint = client.discover_chat(subdomain="fast")

# Use high-capability models
smart_endpoint = client.discover_chat(subdomain="smart")

# Use PII-compliant endpoints
pii_endpoint = client.discover_chat(subdomain="pii")
```

### Capability-Specific Discovery

```python
# Chat
chat_endpoint = client.discover_chat()

# Embeddings
embedding_endpoint = client.discover_embedding()

# Vision/Multimodal
vision_endpoint = client.discover_vision()

# Code-specialized
code_endpoint = client.discover_code()
```

## Testing

### Manual SRV Query

```bash
# Query SRV records
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local

# Expected output:
# _llm-chat._tcp.dev.local. 60 IN SRV 10 70 3000 localhost.

# Query metadata
dig @127.0.0.1 -p 5353 TXT _llm-chat._tcp.dev.local

# Expected:
# _llm-chat._tcp.dev.local. 60 IN TXT "path=/v1/messages"
# _llm-chat._tcp.dev.local. 60 IN TXT "provider=mock"
```

### Health Check

```bash
curl http://localhost:3000/health

# Expected:
# {"status": "healthy", "timestamp": "2026-10-12T..."}
```

### Mock API Call

```bash
curl -X POST http://localhost:3000/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mock-model",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Production Usage

### Environment Variables

```bash
# Set DNS server for discovery
export LLM_DISCOVERY_DNS_SERVER=10.0.1.10
export LLM_DISCOVERY_DOMAIN=corp.example.com

# Use in application
python your_app.py
```

### Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY llm_discovery_client.py .
COPY your_app.py .

# Configure DNS
ENV LLM_DISCOVERY_DNS_SERVER=10.0.1.10
ENV LLM_DISCOVERY_DOMAIN=corp.example.com

CMD ["python", "your_app.py"]
```

### Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: llm-app
spec:
  dnsPolicy: ClusterFirst
  dnsConfig:
    nameservers:
      - 10.0.1.10  # Your internal DNS server
    searches:
      - corp.example.com
  containers:
  - name: app
    image: your-app:latest
    env:
    - name: LLM_DISCOVERY_DOMAIN
      value: "corp.example.com"
```

## Advanced Features

### Automatic Retry with Failover

The client automatically tries endpoints in priority order:

```python
# Client tries priority 10 endpoints first
# If all priority 10 fail, tries priority 20
# Within same priority, distributes load by weight

endpoint = client.discover_chat()  # Smart failover built-in
```

### Custom DNS Resolver

```python
# Use custom DNS server
client = LLMDiscoveryClient(
    domain="corp.example.com",
    dns_server="192.168.1.100",
    dns_port=53
)
```

### Caching

`functools.lru_cache` has no TTL parameter, so honor the DNS TTL with a
timestamp check:

```python
import time

_cache = {"endpoint": None, "expires": 0.0}
CACHE_TTL = 300  # seconds - match your zone's TTL

def get_chat_endpoint():
    """Discover once, then reuse the endpoint until the TTL expires."""
    now = time.monotonic()
    if _cache["endpoint"] is None or now >= _cache["expires"]:
        client = LLMDiscoveryClient(domain="corp.example.com")
        _cache["endpoint"] = client.discover_chat()
        _cache["expires"] = now + CACHE_TTL
    return _cache["endpoint"]

# Subsequent calls within the TTL reuse the cached endpoint
endpoint = get_chat_endpoint()
```

## Troubleshooting

### No endpoints discovered

```python
# Enable debug logging
import logging
logging.basicConfig(level=logging.DEBUG)

client = LLMDiscoveryClient(...)
endpoint = client.discover_chat()
# Check logs for DNS resolution details
```

### DNS resolution fails

```bash
# Test DNS directly
dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local

# Check DNS server is running
netstat -tulpn | grep 5353

# Verify dnsmasq config
dnsmasq --test -C /path/to/dnsmasq.conf
```

### Mock server not responding

```bash
# Check if server is running
curl http://localhost:3000/health

# Check port
netstat -tulpn | grep 3000

# Start with debug
python3 mock_llm_server.py --port 3000 --debug
```

## Future Implementations

Possible additional clients:

- **JavaScript/Node.js**: For web applications
- **Java / C#**: Enterprise integrations

## Contributing

Client implementations should:
1. Support RFC 2782 SRV resolution
2. Implement priority and weight-based selection
3. Parse TXT records for metadata
4. Handle failover automatically
5. Provide health checking
6. Include examples and tests

## References

- [RFC 2782 - DNS SRV](https://datatracker.ietf.org/doc/html/rfc2782)
- [dnspython Documentation](https://dnspython.readthedocs.io/)
- [Python Requests](https://docs.python-requests.org/)
