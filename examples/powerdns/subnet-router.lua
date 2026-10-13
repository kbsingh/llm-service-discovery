-- PowerDNS Lua Script for Subnet-Based LLM Endpoint Routing
-- This script intercepts DNS queries and returns different SRV records
-- based on the client's source IP address/subnet

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

-- Convert a dotted-quad IPv4 string to a number; nil if malformed.
local function ip_to_num(ip)
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
    return ((a * 256 + b) * 256 + c) * 256 + d
end

-- True CIDR match for IPv4, any prefix length /0-/32.
-- (An earlier version only implemented /8 and /16, which silently
-- misclassified clients in e.g. 172.16.0.0/12 as external.)
function ip_in_subnet(ip_str, cidr)
    local net_str, bits_str = cidr:match("^([^/]+)/(%d+)$")
    if not net_str or not bits_str then return false end
    local bits = tonumber(bits_str)
    if not bits or bits < 0 or bits > 32 then return false end

    local ip, net = ip_to_num(ip_str), ip_to_num(net_str)
    if not ip or not net then return false end
    if bits == 0 then return true end

    local block = 2 ^ (32 - bits)
    return math.floor(ip / block) == math.floor(net / block)
end

-- Determine subnet/department from client IP
function determine_subnet(client_ip)
    if ip_in_subnet(client_ip, "10.1.0.0/16") then
        return "finance"
    elseif ip_in_subnet(client_ip, "10.2.0.0/16") then
        return "engineering"
    elseif ip_in_subnet(client_ip, "10.0.0.0/8") or
           ip_in_subnet(client_ip, "192.168.0.0/16") or
           ip_in_subnet(client_ip, "172.16.0.0/12") then
        return "internal"
    else
        return "external"
    end
end

-- Extract service name from query (e.g., "_llm-chat" from "_llm-chat._tcp.corp.example.com")
function extract_service(qname)
    local service = string.match(qname, "^(_llm%-[^%.]+)")
    return service or ""
end

-- =============================================================================
-- SUBNET-SPECIFIC SRV RECORDS
-- =============================================================================

-- Finance department: Compliant endpoints only
finance_endpoints = {
    ["_llm-chat._tcp"] = {
        {prio=10, weight=100, port=8443, target="llm-secure.internal.corp.example.com"}
    },
    ["_llm-embedding._tcp"] = {
        {prio=10, weight=100, port=8443, target="embeddings-secure.internal.corp.example.com"}
    },
    ["_llm-code._tcp"] = {
        {prio=10, weight=100, port=8443, target="llm-secure.internal.corp.example.com"}
    }
    -- Note: No vision or image-gen - restricted by policy
}

-- Engineering department: Full access including experimental
engineering_endpoints = {
    ["_llm-chat._tcp"] = {
        {prio=10, weight=40, port=8080, target="llm-gpu-cluster.internal.corp.example.com"},
        {prio=10, weight=30, port=8090, target="llm-experimental.internal.corp.example.com"},
        {prio=10, weight=15, port=443, target="provider1-proxy.corp.example.com"},
        {prio=10, weight=15, port=443, target="openai-proxy.corp.example.com"},
        {prio=20, weight=100, port=8080, target="llm-cpu-fallback.internal.corp.example.com"}
    },
    ["_llm-embedding._tcp"] = {
        {prio=10, weight=50, port=8081, target="embeddings.internal.corp.example.com"},
        {prio=10, weight=30, port=443, target="openai-proxy.corp.example.com"},
        {prio=10, weight=20, port=443, target="voyage-proxy.corp.example.com"}
    },
    ["_llm-vision._tcp"] = {
        {prio=10, weight=50, port=443, target="provider1-proxy.corp.example.com"},
        {prio=10, weight=30, port=443, target="openai-proxy.corp.example.com"},
        {prio=10, weight=20, port=443, target="gemini-proxy.corp.example.com"}
    },
    ["_llm-code._tcp"] = {
        {prio=10, weight=40, port=8082, target="codellama.internal.corp.example.com"},
        {prio=10, weight=30, port=443, target="provider1-proxy.corp.example.com"},
        {prio=10, weight=30, port=443, target="openai-proxy.corp.example.com"}
    }
}

-- Internal (general corporate network): Local first, cloud backup
internal_endpoints = {
    ["_llm-chat._tcp"] = {
        {prio=10, weight=70, port=8080, target="llm-gpu-cluster.internal.corp.example.com"},
        {prio=10, weight=30, port=8080, target="llm-cpu-fallback.internal.corp.example.com"},
        {prio=20, weight=50, port=443, target="provider1-proxy.corp.example.com"},
        {prio=20, weight=50, port=443, target="openai-proxy.corp.example.com"}
    },
    ["_llm-embedding._tcp"] = {
        {prio=10, weight=100, port=8081, target="embeddings.internal.corp.example.com"},
        {prio=20, weight=100, port=443, target="openai-proxy.corp.example.com"}
    },
    ["_llm-vision._tcp"] = {
        {prio=10, weight=60, port=443, target="provider1-proxy.corp.example.com"},
        {prio=10, weight=40, port=443, target="openai-proxy.corp.example.com"}
    },
    ["_llm-code._tcp"] = {
        {prio=10, weight=100, port=8082, target="codellama.internal.corp.example.com"},
        {prio=20, weight=100, port=443, target="provider1-proxy.corp.example.com"}
    }
}

-- External (internet): Cloud providers only
external_endpoints = {
    ["_llm-chat._tcp"] = {
        {prio=10, weight=50, port=443, target="api-gateway-us.corp.example.com"},
        {prio=10, weight=50, port=443, target="api-gateway-eu.corp.example.com"}
    },
    ["_llm-embedding._tcp"] = {
        {prio=10, weight=100, port=443, target="api-gateway-us.corp.example.com"}
    },
    ["_llm-vision._tcp"] = {
        {prio=10, weight=50, port=443, target="api-gateway-us.corp.example.com"},
        {prio=10, weight=50, port=443, target="api-gateway-eu.corp.example.com"}
    },
    ["_llm-code._tcp"] = {
        {prio=10, weight=100, port=443, target="api-gateway-us.corp.example.com"}
    }
}

-- =============================================================================
-- MAIN QUERY INTERCEPTION FUNCTION
-- =============================================================================

-- This function is called by PowerDNS before normal resolution
function preresolve(dq)
    -- Get client IP and query details
    local client_ip = dq.remote:toString()
    local qname = dq.qname:toString()
    local qtype = dq.qtype

    -- Log the query (debug)
    pdnslog("Query from " .. client_ip .. " for " .. qname .. " type " .. tostring(qtype), pdns.loglevels.Info)

    -- Only process SRV queries
    if qtype ~= pdns.SRV then
        return false  -- Let PowerDNS handle non-SRV queries normally
    end

    -- Determine subnet/department
    local subnet = determine_subnet(client_ip)

    -- Extract service name
    local service = extract_service(qname)
    if service == "" then
        return false  -- Not an LLM service query
    end

    -- Select endpoint set based on subnet
    local endpoints = nil
    if subnet == "finance" then
        endpoints = finance_endpoints[service]
    elseif subnet == "engineering" then
        endpoints = engineering_endpoints[service]
    elseif subnet == "internal" then
        endpoints = internal_endpoints[service]
    else  -- external
        endpoints = external_endpoints[service]
    end

    -- If no specific endpoints defined, return false to use default records
    if not endpoints then
        pdnslog("No specific endpoints for " .. subnet .. "/" .. service .. ", using defaults", pdns.loglevels.Info)
        return false
    end

    -- Add SRV records to response
    for _, ep in ipairs(endpoints) do
        local srv_content = string.format("%d %d %d %s",
            ep.prio, ep.weight, ep.port, ep.target)

        -- Add the SRV record to the response
        dq:addRecord(qtype, srv_content, 300)  -- 300 = TTL

        pdnslog("Added SRV: " .. srv_content, pdns.loglevels.Info)
    end

    -- Set response code to NOERROR
    dq.rcode = 0

    -- Return true to indicate we handled this query
    return true
end

-- =============================================================================
-- ADDITIONAL HOOKS (Optional)
-- =============================================================================

-- Post-resolution hook (called after normal resolution)
-- Can be used to modify or log responses
function postresolve(dq)
    -- Example: Log all SRV responses
    if dq.qtype == pdns.SRV then
        pdnslog("SRV response sent to " .. dq.remote:toString() .. " for " .. dq.qname:toString(),
                pdns.loglevels.Info)
    end
    return false  -- Don't modify the response
end

-- No-op hook for non-existent domains
function nxdomain(dq)
    pdnslog("NXDOMAIN for " .. dq.qname:toString() .. " from " .. dq.remote:toString(),
            pdns.loglevels.Warning)
    return false
end

-- =============================================================================
-- HEALTH CHECK INTEGRATION (Advanced)
-- =============================================================================

--[[
For production, integrate with the endpoint_health table.

IMPORTANT: do NOT build SQL by string interpolation of query-derived
values (SQL injection). PowerDNS's Lua environment does not ship a
parameterized SQL API, so the recommended pattern is to keep an
external health-check process that periodically DISABLES unhealthy
rows in the subnet_policies / records tables (or flips endpoint_health
status consumed by that same process), rather than executing SQL from
preresolve(). The api-gateway or pdnsutil CLI can drive those updates:

    pdnsutil edit-zone corp.example.com        # manual record surgery
    curl -X PATCH -H 'X-API-Key: ...' ...      # programmatic updates

If you do experiment with DB access from Lua, use your own guarded
connector, validate inputs against a strict allow-list pattern first,
 and pin the PowerDNS version (lua-prequery-script is an internal,
 unstable API).
]]--

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- pdnslog() and pdns.loglevels are provided by the PowerDNS Lua
-- environment. The guard keeps this file loadable under a plain lua
-- interpreter (syntax checking) where they don't exist.
if pdnslog and pdns and pdns.loglevels then
    pdnslog("LLM Discovery Lua script loaded successfully", pdns.loglevels.Info)
end
