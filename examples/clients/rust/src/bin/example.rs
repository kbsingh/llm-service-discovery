use clap::Parser;
use llm_discovery::{Config, DiscoveryClient};

#[derive(Parser, Debug)]
#[command(name = "llm-discovery")]
#[command(about = "DNS SRV-based LLM endpoint discovery", long_about = None)]
struct Args {
    /// DNS domain for discovery
    #[arg(long, default_value = "dev.local")]
    domain: String,

    /// Custom DNS server
    #[arg(long, default_value = "127.0.0.1")]
    dns_server: String,

    /// Custom DNS port
    #[arg(long, default_value_t = 5353)]
    dns_port: u16,

    /// Capability to discover (chat, embedding, vision, code, audio, image-gen, rerank)
    #[arg(long, default_value = "chat")]
    capability: String,

    /// Policy subdomain (e.g., fast, smart, pii)
    #[arg(long)]
    subdomain: Option<String>,

    /// Query timeout in seconds
    #[arg(long, default_value_t = 5)]
    timeout: u64,

    /// Show all available endpoints
    #[arg(long)]
    all: bool,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    // Create discovery client
    let client = DiscoveryClient::new(Config {
        domain: args.domain.clone(),
        dns_server: Some(args.dns_server),
        dns_port: Some(args.dns_port),
        timeout_secs: args.timeout,
    });

    println!("🔍 Discovering {} endpoint...", args.capability);

    // Discover by capability (validated by the library)
    let endpoint = client
        .discover(&args.capability, args.subdomain.as_deref())
        .await?;

    // Print discovered endpoint
    println!("✅ Discovered endpoint:");
    println!("   Hostname: {}", endpoint.hostname);
    println!("   Port:     {}", endpoint.port);
    println!("   Priority: {}", endpoint.priority);
    println!("   Weight:   {}", endpoint.weight);
    println!("   URL:      {}", endpoint.base_url());

    if !endpoint.metadata.is_empty() {
        println!("   Metadata:");
        for (key, value) in &endpoint.metadata {
            println!("      {}: {}", key, value);
        }
    }

    // Show all endpoints if requested
    if args.all {
        println!("\n📋 All available endpoints:");

        let service = if let Some(ref subdomain) = args.subdomain {
            format!("_llm-{}._tcp.{}", args.capability, subdomain)
        } else {
            format!("_llm-{}._tcp", args.capability)
        };

        match client.all_endpoints(&service).await {
            Ok(endpoints) => {
                for (i, ep) in endpoints.iter().enumerate() {
                    println!(
                        "   {}. {}:{} (priority={}, weight={})",
                        i + 1,
                        ep.hostname,
                        ep.port,
                        ep.priority,
                        ep.weight
                    );
                }
            }
            Err(e) => {
                eprintln!("   Failed to fetch all endpoints: {}", e);
            }
        }
    }

    Ok(())
}
