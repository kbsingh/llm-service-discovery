//! DNS SRV-based LLM endpoint discovery client
//!
//! This library provides automatic discovery of LLM service endpoints
//! via DNS SRV records (RFC 2782).
//!
//! # Example
//!
//! ```no_run
//! use llm_discovery::{DiscoveryClient, Config};
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     let client = DiscoveryClient::new(Config {
//!         domain: "corp.example.com".to_string(),
//!         dns_server: Some("10.0.1.10".to_string()),
//!         dns_port: None,
//!         timeout_secs: 5,
//!     });
//!
//!     let endpoint = client.discover_chat(None).await?;
//!     println!("Discovered endpoint: {}", endpoint.base_url());
//!
//!     Ok(())
//! }
//! ```

use rand::Rng;
use std::collections::HashMap;
use std::net::IpAddr;
use trust_dns_resolver::config::{ResolverConfig, ResolverOpts};
use trust_dns_resolver::TokioAsyncResolver;
use trust_dns_resolver::proto::rr::RecordType;

/// Error types for LLM discovery
#[derive(Debug, thiserror::Error)]
pub enum DiscoveryError {
    #[error("DNS resolution failed: {0}")]
    DnsError(#[from] trust_dns_resolver::error::ResolveError),

    #[error("No endpoints found for service: {0}")]
    NoEndpointsFound(String),

    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),
}

/// Result type for discovery operations
pub type Result<T> = std::result::Result<T, DiscoveryError>;

/// Discovered LLM service endpoint
#[derive(Debug, Clone)]
pub struct Endpoint {
    pub hostname: String,
    pub port: u16,
    pub priority: u16,
    pub weight: u16,
    pub metadata: HashMap<String, String>,
}

impl Endpoint {
    /// Construct the base URL for this endpoint.
    /// Scheme precedence: a "scheme" TXT metadata value, then the
    /// port-443 heuristic.
    pub fn base_url(&self) -> String {
        let protocol = match self.metadata.get("scheme").map(String::as_str) {
            Some(s) => s.to_string(),
            None if self.port == 443 => "https".to_string(),
            None => "http".to_string(),
        };

        if (protocol == "https" && self.port == 443) || (protocol == "http" && self.port == 80) {
            format!("{}://{}", protocol, self.hostname)
        } else {
            format!("{}://{}:{}", protocol, self.hostname, self.port)
        }
    }
}

/// Configuration for the discovery client
#[derive(Debug, Clone)]
pub struct Config {
    /// Base domain for discovery (e.g., "corp.example.com")
    pub domain: String,

    /// Optional custom DNS server
    pub dns_server: Option<String>,

    /// Optional custom DNS port (default: 53)
    pub dns_port: Option<u16>,

    /// Query timeout in seconds (default: 5)
    pub timeout_secs: u64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            domain: String::new(),
            dns_server: None,
            dns_port: None,
            timeout_secs: 5,
        }
    }
}

/// Client for discovering LLM endpoints via DNS SRV
pub struct DiscoveryClient {
    domain: String,
    resolver: TokioAsyncResolver,
}

impl DiscoveryClient {
    /// Create a new discovery client with the given configuration
    pub fn new(config: Config) -> Self {
        let resolver = if let Some(dns_server) = config.dns_server {
            // Parse DNS server IP
            let ip: IpAddr = dns_server.parse().expect("Invalid DNS server IP");
            let port = config.dns_port.unwrap_or(53);

            // Create custom resolver config
            let mut resolver_config = ResolverConfig::new();
            let nameserver_config = trust_dns_resolver::config::NameServerConfig {
                socket_addr: std::net::SocketAddr::new(ip, port),
                protocol: trust_dns_resolver::config::Protocol::Udp,
                tls_dns_name: None,
                trust_negative_responses: false,
                bind_addr: None,
            };

            resolver_config.add_name_server(nameserver_config);

            TokioAsyncResolver::tokio(resolver_config, ResolverOpts::default())
        } else {
            // Use system resolver
            TokioAsyncResolver::tokio_from_system_conf()
                .expect("Failed to create system resolver")
        };

        Self {
            domain: config.domain,
            resolver,
        }
    }

    /// Query SRV records for a service
    async fn query_srv(&self, service: &str) -> Result<Vec<Endpoint>> {
        let query_name = format!("{}.{}", service, self.domain);

        let response = self.resolver.lookup(query_name.as_str(), RecordType::SRV).await?;

        let mut endpoints = Vec::new();

        for record in response.iter() {
            if let Some(srv) = record.as_srv() {
                let endpoint = Endpoint {
                    hostname: srv.target().to_utf8().trim_end_matches('.').to_string(),
                    port: srv.port(),
                    priority: srv.priority(),
                    weight: srv.weight(),
                    metadata: HashMap::new(),
                };
                endpoints.push(endpoint);
            }
        }

        if endpoints.is_empty() {
            return Err(DiscoveryError::NoEndpointsFound(service.to_string()));
        }

        // Sort by priority (ascending), then weight (descending)
        endpoints.sort_by(|a, b| {
            match a.priority.cmp(&b.priority) {
                std::cmp::Ordering::Equal => b.weight.cmp(&a.weight),
                other => other,
            }
        });

        Ok(endpoints)
    }

    /// Query TXT records for service metadata
    async fn query_txt(&self, service: &str) -> HashMap<String, String> {
        let query_name = format!("{}.{}", service, self.domain);
        let mut metadata = HashMap::new();

        if let Ok(response) = self.resolver.lookup(query_name.as_str(), RecordType::TXT).await {
            for record in response.iter() {
                if let Some(txt) = record.as_txt() {
                    for txt_data in txt.iter() {
                        let text = String::from_utf8_lossy(txt_data);

                        // Parse key=value format
                        if let Some((key, value)) = text.split_once('=') {
                            metadata.insert(key.to_string(), value.to_string());
                        } else {
                            metadata.insert(text.to_string(), "true".to_string());
                        }
                    }
                }
            }
        }

        metadata
    }

    /// Select an endpoint using RFC 2782 weighted random algorithm
    fn select_endpoint(endpoints: &[Endpoint]) -> Option<&Endpoint> {
        if endpoints.is_empty() {
            return None;
        }

        // Get endpoints with lowest priority
        let min_priority = endpoints[0].priority;
        let candidates: Vec<&Endpoint> = endpoints
            .iter()
            .filter(|ep| ep.priority == min_priority)
            .collect();

        // Calculate total weight
        let total_weight: u16 = candidates.iter().map(|ep| ep.weight).sum();

        if total_weight == 0 {
            // All weights are 0, select randomly
            let idx = rand::thread_rng().gen_range(0..candidates.len());
            return Some(candidates[idx]);
        }

        // Weighted random selection
        let mut rng = rand::thread_rng();
        let r = rng.gen_range(0..total_weight);
        let mut cumulative = 0u16;

    for endpoint in &candidates {
        cumulative += endpoint.weight;
        if r < cumulative {
            return Some(*endpoint);
        }
    }

        candidates.last().copied()
    }

    /// Discover an endpoint by capability name, optionally scoped to a
    /// policy subdomain.
    ///
    /// Capability is one of the canonical set from SPECIFICATION.md:
    /// chat, embedding, vision, code, audio, image-gen, rerank.
    pub async fn discover(
        &self,
        capability: &str,
        subdomain: Option<&str>,
    ) -> Result<Endpoint> {
        let base = match capability {
            "chat" => "_llm-chat._tcp",
            "embedding" => "_llm-embedding._tcp",
            "vision" => "_llm-vision._tcp",
            "code" => "_llm-code._tcp",
            "audio" => "_llm-audio._tcp",
            "image-gen" => "_llm-image-gen._tcp",
            "rerank" => "_llm-rerank._tcp",
            other => {
                return Err(DiscoveryError::InvalidConfig(format!(
                    "unknown capability {other:?} (choose from: chat, embedding, vision, code, audio, image-gen, rerank)"
                )))
            }
        };

        let service = match subdomain {
            Some(sub) => format!("{base}.{sub}"),
            None => base.to_string(),
        };

        let endpoints = self.query_srv(&service).await?;
        let endpoint = Self::select_endpoint(&endpoints)
            .ok_or_else(|| DiscoveryError::NoEndpointsFound(service.clone()))?;

        let mut endpoint = endpoint.clone();
        endpoint.metadata = self.query_txt(&service).await;

        Ok(endpoint)
    }

    /// Discover chat completion endpoint
    pub async fn discover_chat(&self, subdomain: Option<&str>) -> Result<Endpoint> {
        let service = if let Some(sub) = subdomain {
            format!("_llm-chat._tcp.{}", sub)
        } else {
            "_llm-chat._tcp".to_string()
        };

        let endpoints = self.query_srv(&service).await?;
        let endpoint = Self::select_endpoint(&endpoints)
            .ok_or_else(|| DiscoveryError::NoEndpointsFound(service.clone()))?;

        let mut endpoint = endpoint.clone();
        endpoint.metadata = self.query_txt(&service).await;

        Ok(endpoint)
    }

    /// Discover embedding endpoint
    pub async fn discover_embedding(&self) -> Result<Endpoint> {
        let service = "_llm-embedding._tcp";

        let endpoints = self.query_srv(service).await?;
        let endpoint = Self::select_endpoint(&endpoints)
            .ok_or_else(|| DiscoveryError::NoEndpointsFound(service.to_string()))?;

        let mut endpoint = endpoint.clone();
        endpoint.metadata = self.query_txt(service).await;

        Ok(endpoint)
    }

    /// Discover vision/multimodal endpoint
    pub async fn discover_vision(&self) -> Result<Endpoint> {
        let service = "_llm-vision._tcp";

        let endpoints = self.query_srv(service).await?;
        let endpoint = Self::select_endpoint(&endpoints)
            .ok_or_else(|| DiscoveryError::NoEndpointsFound(service.to_string()))?;

        let mut endpoint = endpoint.clone();
        endpoint.metadata = self.query_txt(service).await;

        Ok(endpoint)
    }

    /// Discover code-specialized endpoint
    pub async fn discover_code(&self) -> Result<Endpoint> {
        let service = "_llm-code._tcp";

        let endpoints = self.query_srv(service).await?;
        let endpoint = Self::select_endpoint(&endpoints)
            .ok_or_else(|| DiscoveryError::NoEndpointsFound(service.to_string()))?;

        let mut endpoint = endpoint.clone();
        endpoint.metadata = self.query_txt(service).await;

        Ok(endpoint)
    }

    /// Get all endpoints for a service (for manual selection)
    pub async fn all_endpoints(&self, service: &str) -> Result<Vec<Endpoint>> {
        let mut endpoints = self.query_srv(service).await?;
        let metadata = self.query_txt(service).await;

        // Apply metadata to all endpoints
        for endpoint in &mut endpoints {
            endpoint.metadata = metadata.clone();
        }

        Ok(endpoints)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_endpoint_selection() {
        let endpoints = vec![
            Endpoint {
                hostname: "host1".to_string(),
                port: 8080,
                priority: 10,
                weight: 100,
                metadata: HashMap::new(),
            },
            Endpoint {
                hostname: "host2".to_string(),
                port: 8080,
                priority: 20,
                weight: 100,
                metadata: HashMap::new(),
            },
        ];

        let selected = DiscoveryClient::select_endpoint(&endpoints);
        assert!(selected.is_some());
        // Should select priority 10
        assert_eq!(selected.unwrap().priority, 10);
    }

    #[test]
    fn test_base_url_scheme_precedence() {
        // Port 443 infers https and omits the port
        let ep = Endpoint {
            hostname: "api.example.com".to_string(),
            port: 443,
            priority: 10,
            weight: 100,
            metadata: HashMap::new(),
        };
        assert_eq!(ep.base_url(), "https://api.example.com");

        // Non-standard port keeps the port (http by default)
        let ep = Endpoint {
            hostname: "llm".to_string(),
            port: 8080,
            priority: 10,
            weight: 100,
            metadata: HashMap::new(),
        };
        assert_eq!(ep.base_url(), "http://llm:8080");

        // scheme metadata overrides the port heuristic (8443 TLS endpoint)
        let mut metadata = HashMap::new();
        metadata.insert("scheme".to_string(), "https".to_string());
        let ep = Endpoint {
            hostname: "llm-secure.internal".to_string(),
            port: 8443,
            priority: 10,
            weight: 100,
            metadata,
        };
        assert_eq!(ep.base_url(), "https://llm-secure.internal:8443");
    }
}
