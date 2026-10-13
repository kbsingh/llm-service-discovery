# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub's
[security advisory](https://github.com/) feature for this repository
("Security" → "Report a vulnerability"), or contact the maintainers
directly if you have their address. Please do not open public issues
for suspected vulnerabilities.

We aim to acknowledge reports within a few days.

## Scope

This repository ships **example configurations and reference client
code** for DNS SRV-based LLM endpoint discovery. Security
considerations that apply to any deployment built from these examples:

- **DNS discovery does not authenticate anything.** SRV/TXT records
  tell clients *where* to connect, not *who may connect*. API keys,
  OAuth, or mTLS remain mandatory at the endpoint.
- **Untrusted DNS is an attack surface.** A client that connects to
  whatever a resolver tells it to can be pointed at attacker hosts.
  Use DNSSEC-signed zones and resolvers you control in production; see
  `SPECIFICATION.md` (Security Considerations).
- **Split-horizon policies are network-level, not cryptographic.** The
  BIND views and the PowerDNS Lua router segment *availability* of
  endpoint information by source subnet; they are not access control
  for the endpoints themselves.
- **Verify before you deploy.** The examples deliberately use
  placeholder secrets (`CHANGE_ME_*`), reserved domains
  (`corp.example.com`, `dev.local`), and reserved IP ranges. Anything
  real that you build from them is your responsibility to harden.

## Example-specific hardening notes

- `examples/clients/python/mock_llm_server.py` binds `127.0.0.1` by
  default and warns if `--debug` (Werkzeug debugger) is combined with a
  non-loopback bind — the debugger allows arbitrary code execution.
- `examples/powerdns/pdns.conf` keeps the API webserver loopback-bound
  with a warning comment on `api-readonly=no`; the database and API
  credentials are placeholders you must replace.
- The dnsmasq example enables `bogus-priv` / `stop-dns-rebind`
  protections and binds loopback on a non-standard port; its README
  documents the open-resolver risks before suggesting any wider bind.
- `scripts/verify.sh` only binds loopback ports (3000/5353) and
  validates DNS data shape before passing it to `jq`/consumers.
