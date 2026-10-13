-- PowerDNS Seed Data for LLM Discovery
-- Example SRV records and subnet policies

-- =============================================================================
-- CREATE DOMAIN
-- =============================================================================

INSERT INTO domains (name, type) VALUES
('corp.example.com', 'NATIVE'),
('dev.corp.example.com', 'NATIVE');

-- Get domain IDs for use in records
SET @corp_domain_id = (SELECT id FROM domains WHERE name = 'corp.example.com');
SET @dev_domain_id = (SELECT id FROM domains WHERE name = 'dev.corp.example.com');

-- =============================================================================
-- SOA RECORDS
-- =============================================================================

-- NOTE: PowerDNS expects fully-qualified domain names WITH a trailing
-- dot in the content of record types whose RDATA contains domain names
-- (SOA, NS, SRV). The `name` column uses names without the dot.

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, 'corp.example.com', 'SOA',
 'ns1.corp.example.com. admin.corp.example.com. 2026101201 3600 1800 604800 300',
 3600, NULL),
(@dev_domain_id, 'dev.corp.example.com', 'SOA',
 'ns1.corp.example.com. admin.corp.example.com. 2026101201 600 300 86400 60',
 600, NULL);

-- =============================================================================
-- NS RECORDS
-- =============================================================================

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, 'corp.example.com', 'NS', 'ns1.corp.example.com.', 3600, NULL),
(@corp_domain_id, 'corp.example.com', 'NS', 'ns2.corp.example.com.', 3600, NULL),
(@dev_domain_id, 'dev.corp.example.com', 'NS', 'ns1.corp.example.com.', 600, NULL);

-- Nameserver A records
INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, 'ns1.corp.example.com', 'A', '10.0.1.10', 3600, NULL),
(@corp_domain_id, 'ns2.corp.example.com', 'A', '10.0.1.11', 3600, NULL);

-- =============================================================================
-- DEFAULT SRV RECORDS - CHAT COMPLETION
-- =============================================================================

-- These are the baseline records, Lua script will override based on subnet
INSERT INTO records (domain_id, name, type, content, ttl, prio, disabled) VALUES
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'SRV',
 '10 70 8080 llm-gpu-cluster.internal.corp.example.com.', 300, 10, FALSE),
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'SRV',
 '10 30 8080 llm-cpu-fallback.internal.corp.example.com.', 300, 10, FALSE),
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'SRV',
 '20 50 443 provider1-proxy.corp.example.com.', 300, 20, FALSE),
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'SRV',
 '20 50 443 openai-proxy.corp.example.com.', 300, 20, FALSE);

-- TXT metadata for chat
INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'TXT', '"path=/v1/messages"', 300, NULL),
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'TXT', '"provider=mixed"', 300, NULL),
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'TXT', '"protocol=openai-compatible"', 300, NULL),
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'TXT', '"auth=required"', 300, NULL);

-- =============================================================================
-- SRV RECORDS - EMBEDDING
-- =============================================================================

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, '_llm-embedding._tcp.corp.example.com', 'SRV',
 '10 100 8081 embeddings.internal.corp.example.com.', 300, 10),
(@corp_domain_id, '_llm-embedding._tcp.corp.example.com', 'SRV',
 '20 100 443 openai-proxy.corp.example.com.', 300, 20);

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, '_llm-embedding._tcp.corp.example.com', 'TXT', '"path=/v1/embeddings"', 300, NULL),
(@corp_domain_id, '_llm-embedding._tcp.corp.example.com', 'TXT', '"provider=local-e5"', 300, NULL),
(@corp_domain_id, '_llm-embedding._tcp.corp.example.com', 'TXT', '"model=e5-large-v2"', 300, NULL);

-- =============================================================================
-- SRV RECORDS - VISION
-- =============================================================================

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, '_llm-vision._tcp.corp.example.com', 'SRV',
 '10 60 443 provider1-proxy.corp.example.com.', 300, 10),
(@corp_domain_id, '_llm-vision._tcp.corp.example.com', 'SRV',
 '10 40 443 openai-proxy.corp.example.com.', 300, 10);

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, '_llm-vision._tcp.corp.example.com', 'TXT', '"path=/v1/messages"', 300, NULL),
(@corp_domain_id, '_llm-vision._tcp.corp.example.com', 'TXT', '"provider=cloud"', 300, NULL),
(@corp_domain_id, '_llm-vision._tcp.corp.example.com', 'TXT', '"model=claude-3.5-sonnet"', 300, NULL);

-- =============================================================================
-- SRV RECORDS - CODE
-- =============================================================================

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@corp_domain_id, '_llm-code._tcp.corp.example.com', 'SRV',
 '10 100 8082 codellama.internal.corp.example.com.', 300, 10),
(@corp_domain_id, '_llm-code._tcp.corp.example.com', 'SRV',
 '20 100 443 provider1-proxy.corp.example.com.', 300, 20);

-- =============================================================================
-- A RECORDS FOR ENDPOINTS
-- =============================================================================

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
-- Internal endpoints
(@corp_domain_id, 'llm-gpu-cluster.internal.corp.example.com', 'A', '10.0.10.100', 300, NULL),
(@corp_domain_id, 'llm-cpu-fallback.internal.corp.example.com', 'A', '10.0.10.101', 300, NULL),
(@corp_domain_id, 'embeddings.internal.corp.example.com', 'A', '10.0.10.102', 300, NULL),
(@corp_domain_id, 'codellama.internal.corp.example.com', 'A', '10.0.10.103', 300, NULL),
(@corp_domain_id, 'llm-secure.internal.corp.example.com', 'A', '10.0.10.200', 300, NULL),
(@corp_domain_id, 'llm-experimental.internal.corp.example.com', 'A', '10.0.10.150', 300, NULL),

-- Cloud proxies
(@corp_domain_id, 'provider1-proxy.corp.example.com', 'A', '10.0.20.10', 300, NULL),
(@corp_domain_id, 'openai-proxy.corp.example.com', 'A', '10.0.20.11', 300, NULL);

-- =============================================================================
-- DEV ENVIRONMENT RECORDS
-- =============================================================================

INSERT INTO records (domain_id, name, type, content, ttl, prio) VALUES
(@dev_domain_id, '_llm-chat._tcp.dev.corp.example.com', 'SRV',
 '10 70 3000 localhost.', 60, 10),
(@dev_domain_id, '_llm-chat._tcp.dev.corp.example.com', 'TXT', '"environment=development"', 60, NULL),
(@dev_domain_id, '_llm-chat._tcp.dev.corp.example.com', 'TXT', '"provider=mock"', 60, NULL);

-- =============================================================================
-- SUBNET POLICIES - Overrides for specific network segments
-- =============================================================================

-- Finance Department (10.1.0.0/16) - Compliant endpoints only
INSERT INTO subnet_policies (subnet, department, service, domain, endpoint, priority, weight, port, notes) VALUES
('10.1.0.0/16', 'finance', '_llm-chat._tcp', 'corp.example.com',
 'llm-secure.internal.corp.example.com', 10, 100, 8443,
 'SOC2/HIPAA compliant endpoint for finance dept'),
('10.1.0.0/16', 'finance', '_llm-embedding._tcp', 'corp.example.com',
 'embeddings-secure.internal.corp.example.com', 10, 100, 8443,
 'Compliant embeddings for finance'),
('10.1.0.0/16', 'finance', '_llm-code._tcp', 'corp.example.com',
 'llm-secure.internal.corp.example.com', 10, 100, 8443,
 'Code analysis must stay on-prem');

-- Engineering Department (10.2.0.0/16) - Full access including experimental
INSERT INTO subnet_policies (subnet, department, service, domain, endpoint, priority, weight, port, notes) VALUES
('10.2.0.0/16', 'engineering', '_llm-chat._tcp', 'corp.example.com',
 'llm-gpu-cluster.internal.corp.example.com', 10, 40, 8080,
 'Primary GPU cluster for engineering'),
('10.2.0.0/16', 'engineering', '_llm-chat._tcp', 'corp.example.com',
 'llm-experimental.internal.corp.example.com', 10, 30, 8090,
 'Experimental models for testing'),
('10.2.0.0/16', 'engineering', '_llm-chat._tcp', 'corp.example.com',
 'provider1-proxy.corp.example.com', 10, 15, 443,
 'Cloud backup - provider1'),
('10.2.0.0/16', 'engineering', '_llm-chat._tcp', 'corp.example.com',
 'openai-proxy.corp.example.com', 10, 15, 443,
 'Cloud backup - OpenAI');

-- External/Public (0.0.0.0/0) - Cloud providers only
INSERT INTO subnet_policies (subnet, department, service, domain, endpoint, priority, weight, port, notes) VALUES
('0.0.0.0/0', 'external', '_llm-chat._tcp', 'corp.example.com',
 'api-gateway-us.corp.example.com', 10, 50, 443,
 'US cloud gateway for external clients'),
('0.0.0.0/0', 'external', '_llm-chat._tcp', 'corp.example.com',
 'api-gateway-eu.corp.example.com', 10, 50, 443,
 'EU cloud gateway for external clients');

-- =============================================================================
-- ENDPOINT HEALTH STATUS
-- =============================================================================

INSERT INTO endpoint_health (endpoint, status, consecutive_failures, notes) VALUES
('llm-gpu-cluster.internal.corp.example.com', 'healthy', 0, 'Primary GPU cluster'),
('llm-cpu-fallback.internal.corp.example.com', 'healthy', 0, 'CPU fallback'),
('llm-secure.internal.corp.example.com', 'healthy', 0, 'Compliant endpoint'),
('llm-experimental.internal.corp.example.com', 'degraded', 2, 'Occasional timeouts'),
('provider1-proxy.corp.example.com', 'healthy', 0, 'provider1 cloud proxy'),
('openai-proxy.corp.example.com', 'healthy', 0, 'OpenAI cloud proxy'),
('embeddings.internal.corp.example.com', 'healthy', 0, 'Embedding service'),
('codellama.internal.corp.example.com', 'healthy', 0, 'Code LLM');

-- =============================================================================
-- COMMENTS FOR DOCUMENTATION
-- =============================================================================

INSERT INTO comments (domain_id, name, type, modified_at, account, comment) VALUES
(@corp_domain_id, '_llm-chat._tcp.corp.example.com', 'SRV', UNIX_TIMESTAMP(),
 'admin', 'Main chat completion endpoint. Priority 10 = local, Priority 20 = cloud backup.'),
(@corp_domain_id, '_llm-vision._tcp.corp.example.com', 'SRV', UNIX_TIMESTAMP(),
 'admin', 'Vision endpoints - cloud only, no local vision models available yet.'),
(@corp_domain_id, '_llm-embedding._tcp.corp.example.com', 'SRV', UNIX_TIMESTAMP(),
 'admin', 'Embedding service - local e5-large-v2 model preferred, OpenAI as backup.');

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- To verify the data was inserted:
-- SELECT * FROM domains;
-- SELECT name, type, content FROM records WHERE type='SRV';
-- SELECT * FROM subnet_policies;
-- SELECT * FROM srv_records_view;
-- SELECT * FROM active_policies_view;
