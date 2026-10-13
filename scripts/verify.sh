#!/usr/bin/env bash
# verify.sh - Build + functional verification suite for dns_llm_discovery
#
# Runs every check from the pre-publication appraisal (FINDINGS_REPORT.md):
#   1. bash CLI syntax (and shellcheck when available)
#   2. Go SDK build + example run
#   3. Rust SDK build + test + example run
#   4. Python client compile
#   5. BIND zone file validation
#   6. dnsmasq config validation
#   7. Lua syntax validation
#   8. End-to-end smoke test (dnsmasq + mock LLM server + every client)
#
# Usage: scripts/verify.sh [--skip-e2e]
#
# The script collects ALL results and exits non-zero if anything failed.
# Missing optional tools are reported as SKIP, never silently ignored.
# Logs and scratch files are written to .tmp/ in the repo root.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP="$ROOT/.tmp"
mkdir -p "$TMP"

SKIP_E2E=false
[[ "${1:-}" == "--skip-e2e" ]] && SKIP_E2E=true

PASS=0
FAIL=0
SKIP=0
FAILED_STEPS=()

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); FAILED_STEPS+=("$1"); }
skip() { echo "  SKIP: $1${2:+ ($2)}"; SKIP=$((SKIP + 1)); }
hdr()  { echo; echo "== $1 =="; }

# ---------------------------------------------------------------------------
# 1. Bash CLI syntax
# ---------------------------------------------------------------------------
hdr "llm-discovery bash script"

if bash -n llm-discovery 2>/dev/null; then
    ok "bash -n llm-discovery"
else
    bad "bash -n llm-discovery"
fi

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -S warning llm-discovery; then
        ok "shellcheck llm-discovery"
    else
        bad "shellcheck llm-discovery"
    fi
else
    skip "shellcheck llm-discovery" "shellcheck not installed"
fi

# ---------------------------------------------------------------------------
# 2. Go SDK
# ---------------------------------------------------------------------------
hdr "Go client"

GO_EXAMPLE="$TMP/verify_go_llm_discovery"
if command -v go >/dev/null 2>&1; then
    if (cd examples/clients/go && go vet ./... >"$TMP/verify_go_vet.log" 2>&1); then
        ok "go vet ./..."
    else
        bad "go vet ./..."
        echo "    vet log: $TMP/verify_go_vet.log"
    fi
    if (cd examples/clients/go && go build -o "$GO_EXAMPLE" ./example >"$TMP/verify_go_build.log" 2>&1); then
        ok "go build example"
    else
        bad "go build example"
        echo "    build log: $TMP/verify_go_build.log"
    fi
else
    skip "Go build" "go not installed"
fi

# ---------------------------------------------------------------------------
# 3. Rust SDK
# ---------------------------------------------------------------------------
hdr "Rust client"

RUST_EXAMPLE="examples/clients/rust/target/release/llm-discovery-example"
if command -v cargo >/dev/null 2>&1; then
    if (cd examples/clients/rust && cargo build --release --quiet >"$TMP/verify_rust_build.log" 2>&1) &&
       [[ -x "$RUST_EXAMPLE" ]]; then
        ok "cargo build --release"
    else
        bad "cargo build --release"
        echo "    build log: $TMP/verify_rust_build.log"
    fi
    if (cd examples/clients/rust && cargo test --quiet >"$TMP/verify_rust_test.log" 2>&1); then
        ok "cargo test"
    else
        bad "cargo test"
        echo "    test log: $TMP/verify_rust_test.log"
    fi
else
    skip "Rust build" "cargo not installed"
fi

# ---------------------------------------------------------------------------
# 4. Python
# ---------------------------------------------------------------------------
hdr "Python client"

if command -v python3 >/dev/null 2>&1; then
    if python3 -m py_compile \
        examples/clients/python/llm_discovery_client.py \
        examples/clients/python/mock_llm_server.py 2>/dev/null; then
        ok "python3 -m py_compile (client + mock server)"
    else
        bad "python3 -m py_compile (client + mock server)"
    fi
    if python3 -c "
import sys; sys.path.insert(0, 'examples/clients/python')
from llm_discovery_client import LLMEndpoint
ep = LLMEndpoint(hostname='llm-secure.internal', port=8443, priority=10, weight=100,
                 metadata={'scheme': 'https'})
assert ep.base_url == 'https://llm-secure.internal:8443', ep.base_url
ep = LLMEndpoint(hostname='api', port=443, priority=10, weight=100)
assert ep.base_url == 'https://api', ep.base_url
" 2>/dev/null; then
        ok "Python scheme-aware URL construction (M-2)"
    else
        bad "Python scheme-aware URL construction (M-2)"
    fi
else
    skip "Python compile" "python3 not installed"
fi

# ---------------------------------------------------------------------------
# 5. BIND zone files
# ---------------------------------------------------------------------------
hdr "BIND zone files"

if command -v named-checkzone >/dev/null 2>&1; then
    while read -r origin zonefile; do
        if named-checkzone "$origin" "$zonefile" >/dev/null 2>&1; then
            ok "named-checkzone $zonefile"
        else
            bad "named-checkzone $zonefile"
        fi
    done <<'ZONES'
corp.example.com examples/bind/internal/corp.example.com.zone
corp.example.com examples/bind/external/corp.example.com.zone
corp.example.com examples/bind/finance/corp.example.com.zone
corp.example.com examples/bind/engineering/corp.example.com.zone
dev.corp.example.com examples/bind/internal/dev.corp.example.com.zone
ZONES
else
    skip "zone file checks" "named-checkzone not installed"
fi

# ---------------------------------------------------------------------------
# 6. dnsmasq configs
# ---------------------------------------------------------------------------
hdr "dnsmasq configs"

if command -v dnsmasq >/dev/null 2>&1; then
    # Run from the config's directory: dnsmasq.conf includes
    # llm-discovery.conf by relative path (conf-file=)
    if (cd examples/dnsmasq && dnsmasq --test -C dnsmasq.conf >/dev/null 2>&1); then
        ok "dnsmasq --test dnsmasq.conf"
    else
        bad "dnsmasq --test dnsmasq.conf"
    fi
    if dnsmasq --test -C examples/dnsmasq/llm-discovery.conf >/dev/null 2>&1; then
        ok "dnsmasq --test llm-discovery.conf"
    else
        bad "dnsmasq --test llm-discovery.conf"
    fi
else
    skip "dnsmasq config checks" "dnsmasq not installed"
fi

# ---------------------------------------------------------------------------
# 7. Lua
# ---------------------------------------------------------------------------
hdr "PowerDNS Lua script"

if command -v luac >/dev/null 2>&1; then
    if luac -p examples/powerdns/subnet-router.lua >/dev/null 2>&1; then
        ok "luac -p subnet-router.lua"
    else
        bad "luac -p subnet-router.lua"
    fi
elif python3 -c "import lupa" >/dev/null 2>&1; then
    # lupa embeds a real Lua runtime: loading the file validates syntax
    if python3 -c "
from lupa import LuaRuntime
LuaRuntime().execute(open('examples/powerdns/subnet-router.lua').read())
" 2>/dev/null; then
        ok "lua load check via python lupa"
    else
        bad "lua load check via python lupa"
    fi
else
    skip "Lua syntax check" "neither luac nor python lupa installed"
fi

# ---------------------------------------------------------------------------
# 8. End-to-end smoke test
# ---------------------------------------------------------------------------
hdr "End-to-end smoke test (dnsmasq + mock LLM + all clients)"

run_e2e() {
    local needed=(dnsmasq dig jq python3)
    local missing=()
    for cmd in "${needed[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        skip "end-to-end test" "missing: ${missing[*]}"
        return 0
    fi
    if ! python3 -c "import dns.resolver, flask" >/dev/null 2>&1; then
        skip "end-to-end test" "python modules dns.resolver/flask not installed"
        return 0
    fi

    local DNSMASQ_PID="" MOCK_PID=""
    local tmpdir
    tmpdir="$(mktemp -d "$TMP/verify_e2e.XXXXXX")"

    cleanup() {
        [[ -n "$DNSMASQ_PID" ]] && kill "$DNSMASQ_PID" 2>/dev/null
        [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null
        wait 2>/dev/null
    }
    trap cleanup RETURN

    # TCP ports must be free. (UDP 5353 is deliberately not checked:
    # multicast mDNS sockets on 0.0.0.0/[::]:5353 coexist fine with
    # dnsmasq's specific 127.0.0.1:5353 bind.)
    local busy
    busy="$(ss -tlnp 2>/dev/null | grep -E ':(3000|5353)\b' || true)"
    if [[ -n "$busy" ]]; then
        bad "end-to-end test" "ports 3000/5353 already in use by:"
        echo "$busy" | sed 's/^/    /'
        return 0
    fi

    # Start dnsmasq exactly as QUICKSTART.md documents
    (cd examples/dnsmasq && exec dnsmasq -C dnsmasq.conf --no-daemon) \
        >"$tmpdir/dnsmasq.log" 2>&1 &
    DNSMASQ_PID=$!
    # Start mock LLM server
    (cd examples/clients/python && exec python3 mock_llm_server.py --port 3000) \
        >"$tmpdir/mock.log" 2>&1 &
    MOCK_PID=$!

    local waited=0
    until dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short 2>/dev/null | grep -q .; do
        waited=$((waited + 1))
        [[ $waited -ge 40 ]] && break
        sleep 0.25
    done
    # Wait for the mock server too (flask startup takes ~1s)
    waited=0
    until curl -sf --max-time 1 http://127.0.0.1:3000/health >/dev/null 2>&1; do
        waited=$((waited + 1))
        [[ $waited -ge 40 ]] && break
        sleep 0.25
    done

    # DNS must answer (verifies the documented quickstart path)
    local srv_answer
    srv_answer="$(dig @127.0.0.1 -p 5353 SRV _llm-chat._tcp.dev.local +short 2>/dev/null | head -1)"
    if [[ "$srv_answer" == "10 70 3000 localhost." ]]; then
        ok "dnsmasq serves _llm-chat._tcp.dev.local (quickstart step 2)"
    else
        bad "dnsmasq serves _llm-chat._tcp.dev.local (got: '${srv_answer:-nothing}')"
    fi

    # Mock server health
    if curl -sf --max-time 3 http://127.0.0.1:3000/health >/dev/null 2>&1; then
        ok "mock LLM server healthy"
    else
        bad "mock LLM server healthy"
    fi

    # Bash CLI: JSON must be valid and correct (also with a DOWN endpoint,
    # which previously aborted the script - finding H-4)
    if ./llm-discovery --domain dev.local --dns-server 127.0.0.1 --dns-port 5353 \
            --format json --no-metadata 2>/dev/null \
            | jq -e '.[0].url == "http://localhost:3000"' >/dev/null 2>&1; then
        ok "llm-discovery --format json (valid JSON, correct endpoint)"
    else
        bad "llm-discovery --format json"
    fi
    if ./llm-discovery --domain dev.local --dns-server 127.0.0.1 --dns-port 5353 \
            --capability embedding --health --format json --no-metadata 2>/dev/null \
            | jq -e '.[0].health == "down"' >/dev/null 2>&1; then
        ok "llm-discovery --health --format json survives a down endpoint (H-4)"
    else
        bad "llm-discovery --health --format json with down endpoint (H-4)"
    fi

    # Python client
    if (cd examples/clients/python && timeout 30 python3 llm_discovery_client.py \
            --domain dev.local --dns-server 127.0.0.1 --dns-port 5353 \
            2>/dev/null | grep -q "Discovered endpoint: LLMEndpoint(localhost:3000"); then
        ok "Python client discovers chat endpoint"
    else
        bad "Python client discovers chat endpoint"
    fi

    # Go client (only if built above). Output is captured rather than
    # piped: grep -q closes the pipe after matching, and Go's unbuffered
    # stdout would then die of SIGPIPE, failing the pipeline under
    # pipefail even though the client worked.
    if [[ -x "$GO_EXAMPLE" ]]; then
        local go_out
        go_out="$("$GO_EXAMPLE" --domain dev.local --dns-server 127.0.0.1 --dns-port 5353 2>/dev/null)"
        if [[ "$go_out" == *"Hostname: localhost"* ]]; then
            ok "Go client discovers chat endpoint"
        else
            bad "Go client discovers chat endpoint"
        fi
    else
        skip "Go client e2e" "example not built"
    fi

    # Rust client (only if built above)
    if [[ -x "$RUST_EXAMPLE" ]]; then
        local rust_out
        rust_out="$("$RUST_EXAMPLE" --domain dev.local --dns-server 127.0.0.1 --dns-port 5353 2>/dev/null)"
        if [[ "$rust_out" == *"Hostname: localhost"* ]]; then
            ok "Rust client discovers chat endpoint"
        else
            bad "Rust client discovers chat endpoint"
        fi
    else
        skip "Rust client e2e" "example not built"
    fi

    # Live API round-trip through discovery (Python)
    if (cd examples/clients/python && timeout 30 python3 -c "
from llm_discovery_client import LLMDiscoveryClient
c = LLMDiscoveryClient(domain='dev.local', dns_server='127.0.0.1', dns_port=5353)
ep = c.discover_chat()
resp = c.chat(ep, 'verify')
assert '[MOCK RESPONSE]' in resp['choices'][0]['message']['content']
" >/dev/null 2>&1); then
        ok "full discovery -> chat API round-trip"
    else
        bad "full discovery -> chat API round-trip"
    fi
}

if [[ "$SKIP_E2E" == "true" ]]; then
    skip "end-to-end test" "disabled via --skip-e2e"
else
    run_e2e
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "======================================"
echo "RESULTS: $PASS passed, $FAIL failed, $SKIP skipped"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed steps:"
    for s in "${FAILED_STEPS[@]}"; do
        echo "  - $s"
    done
    exit 1
fi
echo "ALL CHECKS PASSED"
exit 0
