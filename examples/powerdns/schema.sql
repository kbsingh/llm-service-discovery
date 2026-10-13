-- PowerDNS MySQL Schema for LLM Discovery
-- Compatible with PowerDNS 4.x

-- Drop existing tables if any
DROP TABLE IF EXISTS records;
DROP TABLE IF EXISTS domainmetadata;
DROP TABLE IF EXISTS cryptokeys;
DROP TABLE IF EXISTS tsigkeys;
DROP TABLE IF EXISTS domains;
DROP TABLE IF EXISTS supermasters;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS subnet_policies;

-- =============================================================================
-- STANDARD POWERDNS TABLES
-- =============================================================================

-- Domains table: DNS zones
CREATE TABLE domains (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL UNIQUE,
    master              VARCHAR(128) DEFAULT NULL,
    last_check          INT DEFAULT NULL,
    type                VARCHAR(6) NOT NULL,
    notified_serial     INT DEFAULT NULL,
    account             VARCHAR(40) DEFAULT NULL,
    INDEX name_index(name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Records table: All DNS records (A, SRV, TXT, etc.)
CREATE TABLE records (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    domain_id           INT DEFAULT NULL,
    name                VARCHAR(255) DEFAULT NULL,
    type                VARCHAR(10) DEFAULT NULL,
    content             TEXT DEFAULT NULL,
    ttl                 INT DEFAULT NULL,
    prio                INT DEFAULT NULL,
    disabled            BOOLEAN DEFAULT FALSE,
    ordername           VARCHAR(255) DEFAULT NULL,
    auth                BOOLEAN DEFAULT TRUE,
    INDEX nametype_index(name, type),
    INDEX domain_id_index(domain_id),
    FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Comments table: Human-readable comments on records
CREATE TABLE comments (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    domain_id           INT NOT NULL,
    name                VARCHAR(255) NOT NULL,
    type                VARCHAR(10) NOT NULL,
    modified_at         INT NOT NULL,
    account             VARCHAR(40) DEFAULT NULL,
    comment             TEXT NOT NULL,
    INDEX comments_domain_id_idx(domain_id),
    INDEX comments_name_type_idx(name, type),
    INDEX comments_order_idx(domain_id, modified_at),
    FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Domain metadata table: Metadata for zones
CREATE TABLE domainmetadata (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    domain_id           INT NOT NULL,
    kind                VARCHAR(32),
    content             TEXT,
    INDEX domainmetadata_idx(domain_id),
    FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Cryptographic keys table: DNSSEC keys
CREATE TABLE cryptokeys (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    domain_id           INT NOT NULL,
    flags               INT NOT NULL,
    active              BOOL,
    published           BOOL DEFAULT TRUE,
    content             TEXT,
    INDEX domainidindex(domain_id),
    FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TSIG keys table: Transaction signatures
CREATE TABLE tsigkeys (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    name                VARCHAR(255) UNIQUE,
    algorithm           VARCHAR(50),
    secret              VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Supermasters table: Automatic slave zone provisioning
CREATE TABLE supermasters (
    ip                  VARCHAR(64) NOT NULL,
    nameserver          VARCHAR(255) NOT NULL,
    account             VARCHAR(40) NOT NULL,
    PRIMARY KEY (ip, nameserver)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- CUSTOM TABLE FOR SUBNET-BASED POLICIES
-- =============================================================================

-- Subnet policies: Define which endpoints to return for which subnets
CREATE TABLE subnet_policies (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    subnet              VARCHAR(50) NOT NULL COMMENT 'CIDR notation, e.g., 10.1.0.0/16',
    department          VARCHAR(50) COMMENT 'Department name for documentation',
    service             VARCHAR(100) NOT NULL COMMENT 'Service name, e.g., _llm-chat._tcp',
    domain              VARCHAR(255) NOT NULL COMMENT 'Domain name',
    endpoint            VARCHAR(255) NOT NULL COMMENT 'Target hostname',
    priority            INT NOT NULL DEFAULT 10 COMMENT 'SRV priority (lower = preferred)',
    weight              INT NOT NULL DEFAULT 100 COMMENT 'SRV weight (load balancing)',
    port                INT NOT NULL COMMENT 'Service port number',
    enabled             BOOLEAN DEFAULT TRUE COMMENT 'Whether this policy is active',
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    notes               TEXT COMMENT 'Human-readable notes about this policy',

    INDEX subnet_idx(subnet),
    INDEX service_idx(service),
    INDEX domain_idx(domain),
    INDEX enabled_idx(enabled),
    INDEX subnet_service_idx(subnet, service, enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- CUSTOM TABLE FOR ENDPOINT HEALTH STATUS
-- =============================================================================

CREATE TABLE endpoint_health (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    endpoint            VARCHAR(255) NOT NULL UNIQUE COMMENT 'Hostname',
    status              ENUM('healthy', 'degraded', 'down') DEFAULT 'healthy',
    last_check          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    consecutive_failures INT DEFAULT 0,
    notes               TEXT,

    INDEX endpoint_idx(endpoint),
    INDEX status_idx(status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- VIEWS FOR EASIER QUERYING
-- =============================================================================

-- View: All SRV records with parsed content
CREATE VIEW srv_records_view AS
SELECT
    r.id,
    r.domain_id,
    d.name as domain_name,
    r.name as record_name,
    r.type,
    r.content,
    r.ttl,
    r.prio,
    r.disabled,
    SUBSTRING_INDEX(r.content, ' ', 1) as priority,
    SUBSTRING_INDEX(SUBSTRING_INDEX(r.content, ' ', 2), ' ', -1) as weight,
    SUBSTRING_INDEX(SUBSTRING_INDEX(r.content, ' ', 3), ' ', -1) as port,
    SUBSTRING_INDEX(r.content, ' ', -1) as target
FROM records r
JOIN domains d ON r.domain_id = d.id
WHERE r.type = 'SRV';

-- View: Active subnet policies
CREATE VIEW active_policies_view AS
SELECT
    sp.subnet,
    sp.department,
    sp.service,
    sp.domain,
    sp.endpoint,
    sp.priority,
    sp.weight,
    sp.port,
    eh.status as endpoint_status,
    eh.last_check as endpoint_last_check
FROM subnet_policies sp
LEFT JOIN endpoint_health eh ON sp.endpoint = eh.endpoint
WHERE sp.enabled = TRUE
ORDER BY sp.subnet, sp.service, sp.priority, sp.weight DESC;

-- =============================================================================
-- INDEXES FOR PERFORMANCE
-- =============================================================================

-- Additional composite indexes for common queries
CREATE INDEX records_name_type_disabled_idx ON records(name, type, disabled);
CREATE INDEX records_domain_type_idx ON records(domain_id, type);

-- =============================================================================
-- TRIGGERS FOR AUDIT LOGGING
-- =============================================================================

-- Audit log table
CREATE TABLE audit_log (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    table_name          VARCHAR(50) NOT NULL,
    record_id           INT,
    action              ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    old_value           TEXT,
    new_value           TEXT,
    changed_by          VARCHAR(100),
    changed_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX table_idx(table_name),
    INDEX action_idx(action),
    INDEX changed_at_idx(changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Trigger: Log record changes
DELIMITER $$
CREATE TRIGGER records_audit_insert AFTER INSERT ON records
FOR EACH ROW BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_value, changed_by)
    VALUES ('records', NEW.id, 'INSERT',
            CONCAT('name:', NEW.name, ' type:', NEW.type, ' content:', NEW.content),
            USER());
END$$

CREATE TRIGGER records_audit_update AFTER UPDATE ON records
FOR EACH ROW BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
    VALUES ('records', NEW.id, 'UPDATE',
            CONCAT('name:', OLD.name, ' type:', OLD.type, ' content:', OLD.content),
            CONCAT('name:', NEW.name, ' type:', NEW.type, ' content:', NEW.content),
            USER());
END$$

CREATE TRIGGER records_audit_delete AFTER DELETE ON records
FOR EACH ROW BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_value, changed_by)
    VALUES ('records', OLD.id, 'DELETE',
            CONCAT('name:', OLD.name, ' type:', OLD.type, ' content:', OLD.content),
            USER());
END$$
DELIMITER ;

-- =============================================================================
-- NOTES
-- =============================================================================
--
-- To import this schema:
--   mysql -u pdns -p pdns < schema.sql
--
-- To check tables:
--   mysql -u pdns -p -e "SHOW TABLES;" pdns
--
-- To view SRV records:
--   mysql -u pdns -p -e "SELECT * FROM srv_records_view;" pdns
--
-- To view active policies:
--   mysql -u pdns -p -e "SELECT * FROM active_policies_view;" pdns
