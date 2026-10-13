package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	discovery "github.com/example/dns-llm-discovery/go"
)

func main() {
	// Command-line flags
	domain := flag.String("domain", "dev.local", "DNS domain for discovery")
	dnsServer := flag.String("dns-server", "127.0.0.1", "DNS server address")
	dnsPort := flag.String("dns-port", "5353", "DNS server port")
	capability := flag.String("capability", "chat", "Capability to discover (chat, embedding, vision, code, audio, image-gen, rerank)")
	subdomain := flag.String("subdomain", "", "Policy subdomain (e.g., fast, smart, pii)")
	timeout := flag.Duration("timeout", 5*time.Second, "Query timeout")

	flag.Parse()

	// Create discovery client
	client := discovery.NewClient(discovery.Config{
		Domain:    *domain,
		DNSServer: *dnsServer,
		DNSPort:   *dnsPort,
		Timeout:   *timeout,
	})

	ctx := context.Background()

	fmt.Printf("🔍 Discovering %s endpoint...\n", *capability)

	endpoint, err := client.Discover(ctx, *capability, *subdomain)

	if err != nil {
		log.Fatalf("❌ Discovery failed: %v", err)
	}

	// Print discovered endpoint
	fmt.Printf("✅ Discovered endpoint:\n")
	fmt.Printf("   Hostname: %s\n", endpoint.Hostname)
	fmt.Printf("   Port:     %d\n", endpoint.Port)
	fmt.Printf("   Priority: %d\n", endpoint.Priority)
	fmt.Printf("   Weight:   %d\n", endpoint.Weight)
	fmt.Printf("   URL:      %s\n", endpoint.BaseURL())

	if len(endpoint.Metadata) > 0 {
		fmt.Printf("   Metadata:\n")
		for key, value := range endpoint.Metadata {
			fmt.Printf("      %s: %s\n", key, value)
		}
	}

	// Demonstrate fetching all endpoints
	fmt.Printf("\n📋 All available endpoints:\n")

	service := fmt.Sprintf("_llm-%s._tcp", *capability)
	if *subdomain != "" {
		service = fmt.Sprintf("_llm-%s._tcp.%s", *capability, *subdomain)
	}

	allEndpoints, err := client.AllEndpoints(ctx, service)
	if err != nil {
		log.Printf("   Failed to fetch all endpoints: %v", err)
		os.Exit(0)
	}

	for i, ep := range allEndpoints {
		fmt.Printf("   %d. %s:%d (priority=%d, weight=%d)\n",
			i+1, ep.Hostname, ep.Port, ep.Priority, ep.Weight)
	}
}
