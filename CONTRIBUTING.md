# Contributing

Thanks for your interest in improving DNS-based LLM endpoint discovery!

## Getting oriented

- `README.md` — project overview and motivation
- `SPECIFICATION.md` — the technical specification (the source of truth
  for record formats, capability names, and client behavior)
- `QUICKSTART.md` — the 5-minute demo path; **it must keep working**
- `FINDINGS_REPORT.md` / `FIX_MILESTONES.md` — the pre-publication audit
  and remediation plan, kept as the audit trail

## Before you push

Run the verification suite from the repository root:

```bash
./scripts/verify.sh
```

It must finish with `ALL CHECKS PASSED`. The suite:

- syntax-checks the bash CLI (and shellchecks it when installed)
- builds and vets the Go client (`go vet`, `go build`, `go test`)
- builds and tests the Rust client (`cargo build`, `cargo test`)
- byte-compiles the Python client and mock server
- validates all five BIND zone files with `named-checkzone`
- validates both dnsmasq configs
- loads the PowerDNS Lua script in an embedded Lua runtime (and runs it
  through `luac -p` when available)
- runs a full end-to-end smoke test: dnsmasq + mock LLM server + the
  bash CLI + all three client SDKs + a live chat round-trip through the
  discovered endpoint

Missing optional tools are reported as `SKIP`, never silently ignored.

If your change touches the quickstart flow, also follow `QUICKSTART.md`
verbatim from a fresh clone.

## What we care about

1. **Docs and code move together.** A behavior change without the
   matching doc update (or vice versa) will be sent back. This repo
   exists because the original docs and configs drifted apart.
2. **Every documented command runs.** If you add an example to a doc,
   run it. If it can't run as written (needs a real corp network, a
   database, etc.), mark it clearly as illustrative.
3. **Reserved example data only.** Use `corp.example.com`, `dev.local`,
   and RFC 5737 / RFC 1918 address ranges. Never real hostnames, IPs,
   credentials, or API keys. Placeholders follow the `CHANGE_ME_*`
   convention.
4. **Security posture.** Local-only services bind loopback by default;
   any new network-listening example needs access-control guidance.
   DNS discovery never replaces authentication.

## Commit messages

Use a concise subject line and a body that explains *why*. If your
change fixes or extends something tracked in the audit, reference the
finding ID (e.g. `H-5`). Example:

```
fix(dnsmasq): include records via relative conf-file (C-4)

dnsmasq.conf pointed conf-dir at /etc/dnsmasq.d, so the documented
quickstart never loaded the SRV records. Include the sibling
llm-discovery.conf instead; documented the system-install variant.
```

## Adding a client SDK

New client implementations should, at minimum:

1. Query SRV records for the canonical capability set (see
   `SPECIFICATION.md`)
2. Implement the RFC 2782 priority/weighted selection algorithm
3. Query and expose TXT metadata, honoring the `scheme` key for URL
   construction
4. Accept a custom DNS server/port for testing
5. Come with a smoke test wired into `scripts/verify.sh`
