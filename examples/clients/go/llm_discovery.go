// Package llmdiscovery provides DNS SRV-based LLM endpoint discovery
package llmdiscovery

import (
	"context"
	"fmt"
	"math/rand"
	"net"
	"sort"
	"strings"
	"time"
)

// Endpoint represents a discovered LLM service endpoint
type Endpoint struct {
	Hostname string
	Port     uint16
	Priority uint16
	Weight   uint16
	Metadata map[string]string
}

// BaseURL constructs the base URL for the endpoint.
// Scheme precedence: a "scheme" TXT metadata value, then the port-443 heuristic.
func (e *Endpoint) BaseURL() string {
	protocol := e.Metadata["scheme"]
	if protocol == "" {
		protocol = "http"
		if e.Port == 443 {
			protocol = "https"
		}
	}

	if (protocol == "https" && e.Port == 443) || (protocol == "http" && e.Port == 80) {
		return fmt.Sprintf("%s://%s", protocol, e.Hostname)
	}

	return fmt.Sprintf("%s://%s:%d", protocol, e.Hostname, e.Port)
}

// Client provides LLM service discovery via DNS SRV records
type Client struct {
	domain     string
	resolver   *net.Resolver
	timeout    time.Duration
	dnsServer  string
	dnsPort    string
}

// Config holds configuration for the discovery client
type Config struct {
	Domain    string        // Base domain (e.g., "corp.example.com")
	DNSServer string        // Custom DNS server (optional)
	DNSPort   string        // Custom DNS port (default "53")
	Timeout   time.Duration // Query timeout (default 5s)
}

// NewClient creates a new LLM discovery client
func NewClient(cfg Config) *Client {
	if cfg.Timeout == 0 {
		cfg.Timeout = 5 * time.Second
	}
	if cfg.DNSPort == "" {
		cfg.DNSPort = "53"
	}

	client := &Client{
		domain:    cfg.Domain,
		timeout:   cfg.Timeout,
		dnsServer: cfg.DNSServer,
		dnsPort:   cfg.DNSPort,
	}

	// Configure custom resolver if DNS server specified
	if cfg.DNSServer != "" {
		client.resolver = &net.Resolver{
			PreferGo: true,
			Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
				d := net.Dialer{Timeout: cfg.Timeout}
				return d.DialContext(ctx, network, net.JoinHostPort(cfg.DNSServer, cfg.DNSPort))
			},
		}
	} else {
		client.resolver = net.DefaultResolver
	}

	return client
}

// querySRV queries SRV records for a service
func (c *Client) querySRV(ctx context.Context, service string) ([]*Endpoint, error) {
	queryName := fmt.Sprintf("%s.%s", service, c.domain)

	_, srvs, err := c.resolver.LookupSRV(ctx, "", "", queryName)
	if err != nil {
		return nil, fmt.Errorf("failed to lookup SRV records for %s: %w", queryName, err)
	}

	if len(srvs) == 0 {
		return nil, fmt.Errorf("no SRV records found for %s", queryName)
	}

	endpoints := make([]*Endpoint, 0, len(srvs))
	for _, srv := range srvs {
		endpoint := &Endpoint{
			Hostname: strings.TrimSuffix(srv.Target, "."),
			Port:     srv.Port,
			Priority: srv.Priority,
			Weight:   srv.Weight,
			Metadata: make(map[string]string),
		}
		endpoints = append(endpoints, endpoint)
	}

	// Sort by priority (ascending), then weight (descending)
	sort.Slice(endpoints, func(i, j int) bool {
		if endpoints[i].Priority != endpoints[j].Priority {
			return endpoints[i].Priority < endpoints[j].Priority
		}
		return endpoints[i].Weight > endpoints[j].Weight
	})

	return endpoints, nil
}

// queryTXT queries TXT records for service metadata
func (c *Client) queryTXT(ctx context.Context, service string) (map[string]string, error) {
	queryName := fmt.Sprintf("%s.%s", service, c.domain)

	txts, err := c.resolver.LookupTXT(ctx, queryName)
	if err != nil {
		// TXT records are optional, return empty map on error
		return make(map[string]string), nil
	}

	metadata := make(map[string]string)
	for _, txt := range txts {
		// Parse key=value format
		if idx := strings.Index(txt, "="); idx > 0 {
			key := txt[:idx]
			value := txt[idx+1:]
			metadata[key] = value
		} else {
			// Store as flag
			metadata[txt] = "true"
		}
	}

	return metadata, nil
}

// selectEndpoint selects an endpoint using RFC 2782 algorithm
func selectEndpoint(endpoints []*Endpoint) *Endpoint {
	if len(endpoints) == 0 {
		return nil
	}

	// Get endpoints with lowest priority
	minPriority := endpoints[0].Priority
	candidates := make([]*Endpoint, 0)
	for _, ep := range endpoints {
		if ep.Priority == minPriority {
			candidates = append(candidates, ep)
		}
	}

	// Calculate total weight
	var totalWeight uint16
	for _, ep := range candidates {
		totalWeight += ep.Weight
	}

	if totalWeight == 0 {
		// All weights are 0, select randomly
		return candidates[rand.Intn(len(candidates))]
	}

	// Weighted random selection
	r := uint16(rand.Intn(int(totalWeight)))
	var cumulative uint16

	for _, ep := range candidates {
		cumulative += ep.Weight
		if r < cumulative {
			return ep
		}
	}

	return candidates[len(candidates)-1]
}

// capabilityServices maps canonical capability names to service names
// (SPECIFICATION.md capability set).
var capabilityServices = map[string]string{
	"chat":       "_llm-chat._tcp",
	"embedding":  "_llm-embedding._tcp",
	"vision":     "_llm-vision._tcp",
	"code":       "_llm-code._tcp",
	"audio":      "_llm-audio._tcp",
	"image-gen":  "_llm-image-gen._tcp",
	"rerank":     "_llm-rerank._tcp",
}

// Discover discovers an endpoint by capability name, optionally scoped
// to a policy subdomain.
func (c *Client) Discover(ctx context.Context, capability, subdomain string) (*Endpoint, error) {
	service, ok := capabilityServices[capability]
	if !ok {
		return nil, fmt.Errorf("unknown capability %q (choose from: chat, embedding, vision, code, audio, image-gen, rerank)", capability)
	}
	if subdomain != "" {
		service = fmt.Sprintf("%s.%s", service, subdomain)
	}

	endpoints, err := c.querySRV(ctx, service)
	if err != nil {
		return nil, err
	}

	endpoint := selectEndpoint(endpoints)
	if endpoint == nil {
		return nil, fmt.Errorf("no suitable endpoint found")
	}

	metadata, _ := c.queryTXT(ctx, service)
	endpoint.Metadata = metadata

	return endpoint, nil
}

// DiscoverChat discovers chat completion endpoints
func (c *Client) DiscoverChat(ctx context.Context, subdomain string) (*Endpoint, error) {
	service := "_llm-chat._tcp"
	if subdomain != "" {
		service = fmt.Sprintf("_llm-chat._tcp.%s", subdomain)
	}

	endpoints, err := c.querySRV(ctx, service)
	if err != nil {
		return nil, err
	}

	endpoint := selectEndpoint(endpoints)
	if endpoint == nil {
		return nil, fmt.Errorf("no suitable endpoint found")
	}

	// Fetch metadata
	metadata, _ := c.queryTXT(ctx, service)
	endpoint.Metadata = metadata

	return endpoint, nil
}

// DiscoverEmbedding discovers embedding endpoints
func (c *Client) DiscoverEmbedding(ctx context.Context) (*Endpoint, error) {
	service := "_llm-embedding._tcp"

	endpoints, err := c.querySRV(ctx, service)
	if err != nil {
		return nil, err
	}

	endpoint := selectEndpoint(endpoints)
	if endpoint == nil {
		return nil, fmt.Errorf("no suitable endpoint found")
	}

	metadata, _ := c.queryTXT(ctx, service)
	endpoint.Metadata = metadata

	return endpoint, nil
}

// DiscoverVision discovers vision/multimodal endpoints
func (c *Client) DiscoverVision(ctx context.Context) (*Endpoint, error) {
	service := "_llm-vision._tcp"

	endpoints, err := c.querySRV(ctx, service)
	if err != nil {
		return nil, err
	}

	endpoint := selectEndpoint(endpoints)
	if endpoint == nil {
		return nil, fmt.Errorf("no suitable endpoint found")
	}

	metadata, _ := c.queryTXT(ctx, service)
	endpoint.Metadata = metadata

	return endpoint, nil
}

// DiscoverCode discovers code-specialized endpoints
func (c *Client) DiscoverCode(ctx context.Context) (*Endpoint, error) {
	service := "_llm-code._tcp"

	endpoints, err := c.querySRV(ctx, service)
	if err != nil {
		return nil, err
	}

	endpoint := selectEndpoint(endpoints)
	if endpoint == nil {
		return nil, fmt.Errorf("no suitable endpoint found")
	}

	metadata, _ := c.queryTXT(ctx, service)
	endpoint.Metadata = metadata

	return endpoint, nil
}

// AllEndpoints returns all discovered endpoints for a service (for manual selection)
func (c *Client) AllEndpoints(ctx context.Context, service string) ([]*Endpoint, error) {
	endpoints, err := c.querySRV(ctx, service)
	if err != nil {
		return nil, err
	}

	// Fetch metadata for each endpoint
	metadata, _ := c.queryTXT(ctx, service)

	// Apply metadata to all endpoints
	for _, ep := range endpoints {
		ep.Metadata = metadata
	}

	return endpoints, nil
}
