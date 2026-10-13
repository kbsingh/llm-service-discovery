# DNS SRV Records for LLM Endpoint Discovery

A proposal for using DNS SRV records to enable automatic discovery, failover, and policy-based routing of Large Language Model (LLM) API endpoints in enterprise environments.

## Overview

This specification defines a standard approach for advertising LLM service endpoints via DNS SRV records, enabling:

- **Automatic discovery** of available LLM providers
- **Capability-based routing** to appropriate models
- **Load balancing and failover** across multiple providers
- **Policy enforcement** through DNS-based service advertisement
- **Zero-configuration clients** that discover endpoints automatically

## Motivation

Current LLM integrations require hardcoded endpoints, API keys in environment variables, and manual failover logic. As organizations adopt multiple LLM providers (OpenAI, provider1, self-hosted models), managing endpoint configuration becomes complex.

DNS SRV records provide a standard, hierarchical, cacheable mechanism for service discovery that has proven effective for protocols like SIP, XMPP, and LDAP.

## Status

**Draft proposal with working reference implementations** — seeking feedback and implementation experience.

## Specification

See [SPECIFICATION.md](SPECIFICATION.md) for the complete technical specification.

## Quick Start

### Querying LLM Services

```bash
# Find chat completion endpoints
dig SRV _llm-chat._tcp.example.com

# Find embedding endpoints
dig SRV _llm-embedding._tcp.example.com

# Find vision-capable endpoints
dig SRV _llm-vision._tcp.example.com
```

### Example Response

```dns
_llm-chat._tcp.example.com. 300 IN SRV 10 60 443 provider1-proxy.example.com.
_llm-chat._tcp.example.com. 300 IN SRV 10 40 443 openai-proxy.example.com.
_llm-chat._tcp.example.com. 300 IN SRV 20 100 443 local-llama.example.com.
```

**Interpretation:**
- Priority 10: Try provider1 (60% weight) or OpenAI (40% weight) first
- Priority 20: Fall back to local Llama instance if cloud providers unavail

## Use Cases

### 1. Multi-Provider Failover

Organizations can configure primary and backup LLM providers:

```dns
_llm-chat._tcp.corp.example.com. IN SRV 10 100 443 primary-llm.corp.example.com.
_llm-chat._tcp.corp.example.com. IN SRV 20 100 443 backup-llm.corp.example.com.
```

Applications automatically fail over if the primary service is down.

### 2. Capability-Based Routing

Route requests to models optimized for specific tasks:

```dns
; Fast, cheap models for simple tasks
_llm-chat._tcp.quick.corp.com. IN SRV 10 100 443 haiku-endpoint.corp.com.

; High-capability models for complex reasoning
_llm-chat._tcp.smart.corp.com. IN SRV 10 100 443 opus-endpoint.corp.com.

; Vision models
_llm-vision._tcp.corp.com. IN SRV 10 100 443 gpt4-vision.corp.com.
```

### 3. Data Residency & Compliance

```dns
; Sensitive data - on-premises only
_llm-chat._tcp.pii.corp.com. IN SRV 10 100 8443 local-llm.internal.corp.com.

; General use - cloud providers allowed
_llm-chat._tcp.general.corp.com. IN SRV 10 50 443 provider1.external.corp.com.
_llm-chat._tcp.general.corp.com. IN SRV 10 50 443 openai.external.corp.com.
```

### 4. Cost Optimization

```dns
; Try cheaper provider first, expensive as backup
_llm-chat._tcp.cost-optimized.corp.com. IN SRV 10 100 443 cheap-provider.corp.com.
_llm-chat._tcp.cost-optimized.corp.com. IN SRV 20 100 443 premium-provider.corp.com.
```

### 5. Development vs Production

```dns
; Development - local/mock endpoints
_llm-chat._tcp.dev.corp.com. IN SRV 10 100 8080 localhost.

; Production - real providers
_llm-chat._tcp.prod.corp.com. IN SRV 10 100 443 production-llm.corp.com.
```

## Benefits ( from Home Lab's to Enterprise )

### Centralized Policy Management

- **DNS as policy enforcement** - Network admins control which LLM services are available
- **No application changes needed** - Policy updates via DNS without code deployment
- **Audit trail** - DNS query logs show which services are being discovered

### Simplified Operations

- **Single configuration point** - DNS zone file instead of scattered config files
- **Dynamic updates** - Add/remove providers without touching application configs
- **Standard tooling** - Use existing DNS infrastructure and monitoring

### Security

- **Internal DNS** - Advertise internal-only endpoints not exposed publicly
- **Split-horizon DNS** - Different endpoints for internal vs external networks
- **TTL-based caching** - Control how quickly clients pick up endpoint changes

## Example Bash CLI

A simple bash based cli client is provided in the `llm-discovery` file, with details in [CLI Tool Doc](CLI_TOOL.md)

## Further Examples for Server side and Client side implementations

The `examples/` directory contains configuration examples for:

- **BIND** - Traditional DNS server
- **PowerDNS** - Modern authoritative DNS server
- **dnsmasq** - Lightweight DNS forwarder for development
- **Client implementations** - Python, Go, and Rust examples

See [examples/README.md](examples/README.md) for details. Automation and health check based observability can be included in the config generation as well.

## Implementation Considerations

### Client Library Support

Clients need to:
1. Query SRV records for desired capability
2. Sort by priority (ascending) then randomly select by weight
3. Attempt connection to selected endpoint
4. Retry with next priority level on failure
5. Cache results per DNS TTL

### TXT Record Metadata

Additional service metadata can be advertised via TXT records, including pricing information, rate limits, service capacity etc:

```dns
_llm-chat._tcp.corp.com. IN TXT "provider=provider1" "model=claude-opus-5" "max_tokens=200000"
```

### Security Considerations

- **DNSSEC** recommended for production environments
- **Private DNS zones** for internal-only services
- **Authentication still required** - DNS discovery doesn't replace API key management

## Future Extensions

- **Model version discovery** - Sub-services for specific model versions
- **Regional routing** - Geographic-based endpoint selection
- **Rate limit advertisement** - TXT records indicating capacity

## Contributing

This is an open proposal. Feedback, implementations, and improvements welcome!

## License

This project is dual-licensed under **MIT OR Apache-2.0**, at your option:
see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE).

## See Also

- [RFC 2782](https://datatracker.ietf.org/doc/html/rfc2782) - DNS SRV Record specification
- [SPECIFICATION.md](SPECIFICATION.md) - Detailed technical specification
- [examples/](examples/) - Working configuration examples
