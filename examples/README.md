# DNS SRV Configuration Examples

This directory contains working examples for configuring various DNS servers to advertise LLM endpoints via SRV records.

## Examples Included

### [bind/](bind/) - BIND DNS Server
- Traditional authoritative DNS server
- **Split-horizon DNS** - Different responses based on client IP subnet
- Zone file examples for development and production

### [powerdns/](powerdns/) - PowerDNS
- Modern authoritative DNS with SQL backend
- **Subnet-based responses** via a Lua pre-query script
- MySQL schema and sample data

### [dnsmasq/](dnsmasq/) - dnsmasq
- Lightweight DNS forwarder for development
- Simple configuration for local testing
- Self-contained local records (runs straight from the repo)

### [clients/](clients/) - Client Implementations
- Python client with SRV resolution
- Go client library
- Rust async client
- Bash script using dig

## Quick Test

### Start dnsmasq (easiest for testing)

```bash
cd examples/dnsmasq
dnsmasq -C dnsmasq.conf --no-daemon
```

### Query SRV records

```bash
# Find chat endpoints
dig @localhost -p 5353 SRV _llm-chat._tcp.dev.local

# Find embedding endpoints  
dig @localhost -p 5353 SRV _llm-embedding._tcp.dev.local

# Get metadata
dig @localhost -p 5353 TXT _llm-chat._tcp.dev.local
```

## Split-Horizon DNS Examples

Both BIND and PowerDNS examples demonstrate returning different endpoints based on client IP:

**Internal clients (10.0.0.0/8):**
- Get on-premises endpoints
- Lower latency, no egress costs
- May include experimental/dev models

**External clients (Internet):**
- Get cloud provider endpoints
- Geo-distributed, highly available
- Production-grade only

**Department-specific (by subnet):**
- Finance (10.1.0.0/16): PII-compliant endpoints only
- Engineering (10.2.0.0/16): Full access including beta models

## Testing Different Subnets

### With BIND

BIND views are determined server-side based on client source IP. To test:

```bash
# From internal network
dig @your-bind-server SRV _llm-chat._tcp.corp.com

# Simulate external query (if you have control of firewall)
dig @your-bind-server -b <external-ip> SRV _llm-chat._tcp.corp.com
```

### With PowerDNS + Lua

PowerDNS can execute Lua scripts to modify responses:

```bash
# Query will return different results based on your source IP
dig @your-pdns-server SRV _llm-chat._tcp.corp.com
```

The Lua script examines `remote` (client IP) and returns different record sets.

## Production Deployment Checklist

- [ ] Enable DNSSEC for zone signing
- [ ] Configure appropriate TTLs (shorter for active changes, longer for stable)
- [ ] Set up monitoring for DNS query patterns
- [ ] Implement health checks to remove failed endpoints
- [ ] Configure split-horizon for internal vs external clients
- [ ] Document subnet-to-endpoint mapping policy
- [ ] Test failover by disabling priority 10 records
- [ ] Verify TXT record parsing in clients
- [ ] Set up automated zone file deployment
- [ ] Configure logging for security audit

## Additional Resources

- [RFC 2782 - DNS SRV](https://datatracker.ietf.org/doc/html/rfc2782)
- [BIND 9 Documentation](https://bind9.readthedocs.io/)
- [PowerDNS Documentation](https://doc.powerdns.com/)
- [dnsmasq man page](https://thekelleys.org.uk/dnsmasq/doc.html)
