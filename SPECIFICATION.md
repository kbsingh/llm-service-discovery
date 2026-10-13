# LLM Discovery via DNS SRV - Technical Specification

## Version

Draft 0.1 - October 2026

## SRV Record Format

DNS SRV records provide both **hostname and port** in a single record:

```
_service._proto.name. TTL class SRV priority weight port target.
```

**Fields:**
- **service**: `_llm-{capability}` (see Capability Types below)
- **proto**: `_tcp` or `_https` 
- **name**: Organization domain (e.g., `corp.example.com`)
- **priority**: Lower values = preferred (0-65535)
- **weight**: Load balancing weight for same priority (0-65535)
- **port**: TCP port number where service listens
- **target**: Hostname/FQDN of the LLM endpoint

### Example

```dns
_llm-chat._tcp.corp.example.com. 300 IN SRV 10 100 443 api.provider1.example.com.
```

This tells clients: "Chat capability available at `api.provider1.example.com:443`"

## Capability Types

Standard service names for different LLM capabilities:

| Service Name | Description | Common Models |
|--------------|-------------|---------------|
| `_llm-chat` | Conversational text generation | Claude, GPT-4, Llama |
| `_llm-embedding` | Vector embeddings | text-embedding-3, Voyage |
| `_llm-vision` | Multimodal image understanding | Claude 3.5, GPT-4V |
| `_llm-code` | Code-specialized models | Claude Opus, GPT-4 |
| `_llm-audio` | Speech/transcription | Whisper |
| `_llm-image-gen` | Image generation | DALL-E, Stable Diffusion |
| `_llm-rerank` | Reranking/scoring | Cohere Rerank |

(The reserved name `_llm-completion` for non-chat text completion was
considered and dropped: every current OpenAI-compatible API exposes it
through the chat endpoints, so a separate service name added noise
without adding routing value.)

## URL Path and Metadata via TXT Records

SRV records provide hostname and port, but API endpoints often need additional information like URL paths. Use companion TXT records:

```dns
; SRV provides hostname + port
_llm-chat._tcp.corp.com. 300 IN SRV 10 100 443 openai-proxy.corp.com.

; TXT provides additional metadata
_llm-chat._tcp.corp.com. 300 IN TXT "path=/v1/chat/completions"
_llm-chat._tcp.corp.com. 300 IN TXT "provider=openai"
_llm-chat._tcp.corp.com. 300 IN TXT "model=gpt-4"
_llm-chat._tcp.corp.com. 300 IN TXT "auth=required"
```

**Standard TXT Record Keys:**
- `path` - URL path for API endpoint
- `provider` - Provider name (openai, provider1, google, etc.)
- `model` - Default model identifier
- `auth` - Authentication method (required, optional, none)
- `protocol` - Application protocol (openai-compatible, provider1, custom)
- `scheme` - URL scheme (`https` or `http`) — overrides the default port-based inference below
- `max_tokens` - Maximum context length
- `region` - Geographic region (us-east, eu-west, etc.)

**URL scheme selection:** by default clients infer `https` when the SRV
port is 443 and `http` otherwise. Because TLS services also run on
other ports (8443 is common for compliance-gated endpoints), servers
SHOULD publish `scheme=https` in the TXT metadata for any TLS endpoint
not on port 443, and clients MUST honor a `scheme` value when present.

## Client Resolution Algorithm

1. **Query SRV records** for desired capability (e.g., `_llm-chat._tcp.corp.com`)
2. **Query TXT records** for same name to get metadata
3. **Sort by priority** (ascending - lower is better)
4. **Within same priority, randomly select by weight**:
   - Sum weights of all same-priority records
   - Generate random number 0 to sum
   - Select record whose weight range contains the number
5. **Construct endpoint URL**: use the TXT `scheme` value if present,
   otherwise `https` when the port is 443 and `http` otherwise; the URL
   is `{scheme}://{target}:{port}{path}`
6. **Attempt connection** with authentication
7. **On failure, retry** with next priority level
8. **Cache results** according to TTL

### Example Resolution

Given these records:
```dns
_llm-chat._tcp.corp.com. 300 IN SRV 10 60 443 provider1.corp.com.
_llm-chat._tcp.corp.com. 300 IN SRV 10 40 443 openai.corp.com.
_llm-chat._tcp.corp.com. 300 IN SRV 20 100 8080 local.corp.com.
_llm-chat._tcp.corp.com. 300 IN TXT "path=/v1/messages"
```

Client behavior:
- **First attempt**: 60% chance provider1, 40% chance OpenAI (both priority 10)
- **If both priority 10 fail**: Try local endpoint on port 8080
- **URL construction**: `https://provider1.corp.com:443/v1/messages`
- **Cache for 300 seconds** (TTL)

## Naming Conventions

### Domain Hierarchy

Use DNS subdomains for logical grouping:

```dns
; Environment-based
_llm-chat._tcp.dev.corp.com.        ; Development endpoints
_llm-chat._tcp.staging.corp.com.    ; Staging endpoints  
_llm-chat._tcp.prod.corp.com.       ; Production endpoints

; Policy-based
_llm-chat._tcp.pii.corp.com.        ; Endpoints for PII data
_llm-chat._tcp.public.corp.com.     ; Endpoints for public data
_llm-chat._tcp.internal.corp.com.   ; Internal-only endpoints

; Cost-based
_llm-chat._tcp.fast.corp.com.       ; Fast, cheaper models
_llm-chat._tcp.smart.corp.com.      ; Slower, high-capability models

; Region-based
_llm-chat._tcp.us.corp.com.         ; US region
_llm-chat._tcp.eu.corp.com.         ; EU region
```

### Multiple Capabilities

For services supporting multiple capabilities, create separate SRV records:

```dns
; Same endpoint, different capabilities
_llm-chat._tcp.corp.com.     IN SRV 10 100 443 claude.corp.com.
_llm-vision._tcp.corp.com.   IN SRV 10 100 443 claude.corp.com.
_llm-code._tcp.corp.com.     IN SRV 10 100 443 claude.corp.com.
```

## Priority and Weight Strategy

### Failover (Active/Passive)

```dns
; Primary service
_llm-chat._tcp.corp.com. IN SRV 10 100 443 primary.corp.com.
; Backup - only used if primary fails
_llm-chat._tcp.corp.com. IN SRV 20 100 443 backup.corp.com.
```

### Load Balancing (Active/Active)

```dns
; Equal distribution across 3 endpoints
_llm-chat._tcp.corp.com. IN SRV 10 33 443 endpoint1.corp.com.
_llm-chat._tcp.corp.com. IN SRV 10 33 443 endpoint2.corp.com.
_llm-chat._tcp.corp.com. IN SRV 10 34 443 endpoint3.corp.com.
```

### Weighted Distribution

```dns
; 75% to high-capacity, 25% to standard
_llm-chat._tcp.corp.com. IN SRV 10 75 443 high-capacity.corp.com.
_llm-chat._tcp.corp.com. IN SRV 10 25 443 standard.corp.com.
```

### Cloud + On-Prem Hybrid

```dns
; Try cloud first (fast, scalable)
_llm-chat._tcp.corp.com. IN SRV 10 50 443 provider1-proxy.corp.com.
_llm-chat._tcp.corp.com. IN SRV 10 50 443 openai-proxy.corp.com.
; Fall back to on-prem (compliance, cost)
_llm-chat._tcp.corp.com. IN SRV 20 100 8080 local-llama.corp.com.
```

## Protocol Considerations

### HTTPS vs TCP

- `_tcp` - Raw TCP connection (custom protocols)
- `_https` - HTTPS/TLS connection (most common for LLM APIs)

Most LLM services should use `_https`:

```dns
_llm-chat._https.corp.com. IN SRV 10 100 443 api.corp.com.
```

### Port Selection

**Standard ports:**
- `443` - HTTPS (recommended for production)
- `8080` - HTTP alternative (development/internal)
- `8443` - HTTPS alternative (multi-tenant environments)

**Custom ports:**
- Use for self-hosted models or proxies
- Firewall rules can restrict based on port numbers

## TTL Strategy

**Recommended TTLs:**

- **Production stable services**: 3600 seconds (1 hour)
  - Long cache time for stable endpoints
  
- **Development/testing**: 300 seconds (5 minutes)
  - Quick updates during development
  
- **Maintenance windows**: 60 seconds (1 minute)
  - Rapid failover during planned changes
  
- **Emergency failover**: 0-30 seconds
  - Immediate propagation during incidents

## Security Considerations

### DNSSEC

Recommended for production environments to prevent DNS spoofing:

```bash
# Sign zone with DNSSEC
dnssec-signzone -A -3 $(head -c 1000 /dev/urandom | sha1sum | cut -b 1-16) \
  -N INCREMENT -o corp.com -t corp.com.zone
```

### Split-Horizon DNS

Internal vs external views:

```dns
; Internal view - local endpoints
; /etc/bind/internal/corp.com.zone
_llm-chat._tcp.corp.com. IN SRV 10 100 8080 local-llm.internal.

; External view - public proxies
; /etc/bind/external/corp.com.zone  
_llm-chat._tcp.corp.com. IN SRV 10 100 443 api-gateway.corp.com.
```

### Authentication

**DNS discovery does NOT replace authentication!**

- SRV records only provide endpoint location
- Clients still need API keys, OAuth tokens, mTLS certificates
- Use TXT records to advertise auth requirements:

```dns
_llm-chat._tcp.corp.com. IN TXT "auth=bearer-token"
_llm-chat._tcp.corp.com. IN TXT "auth-endpoint=https://auth.corp.com/token"
```

## Monitoring and Observability

### Health Checks

DNS doesn't provide health status. Implement health checking separately:

1. **Client-side**: Try endpoint, mark unavailable on failure, skip in future
2. **Server-side**: Update DNS when service goes down (short TTL helps)
3. **External monitoring**: Remove unhealthy SRV records automatically

### Logging

Monitor DNS queries for:
- Which services are being discovered
- Query patterns (frequency, sources)
- Failed resolutions (NXDOMAIN)

### Metrics

Track:
- SRV query rate per capability
- Endpoint selection distribution (verify weights work)
- Failover frequency (priority fallback)
- TTL effectiveness (cache hit rate)

## Backwards Compatibility

For existing applications not SRV-aware:

### Option 1: DNS CNAME + Fixed Port

```dns
; Traditional A record approach
llm-api.corp.com. IN A 192.168.1.100

; Migrate to SRV
_llm-chat._tcp.corp.com. IN SRV 10 100 443 llm-api.corp.com.
```

### Option 2: Proxy/Adapter

Implement an HTTP proxy that:
1. Discovers backends via SRV
2. Provides traditional REST endpoint to legacy clients
3. Handles failover transparently

## Example Implementations

See `examples/` directory for:
- BIND zone file configurations
- PowerDNS SQL backend examples
- dnsmasq configuration
- Client libraries (Python, Go, Rust)

## References

- [RFC 2782](https://datatracker.ietf.org/doc/html/rfc2782) - DNS SRV RR specification
- [RFC 6763](https://datatracker.ietf.org/doc/html/rfc6763) - DNS-SD (Service Discovery)
- [RFC 4034](https://datatracker.ietf.org/doc/html/rfc4034) - DNSSEC Resource Records
