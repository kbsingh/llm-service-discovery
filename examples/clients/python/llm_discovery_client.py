#!/usr/bin/env python3
"""
LLM Discovery Client - DNS SRV-based LLM endpoint discovery
Automatically discovers and connects to LLM services via DNS SRV records
"""

import dns.resolver
import random
import logging
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
import requests
from urllib.parse import urljoin

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Canonical capability set (SPECIFICATION.md)
CAPABILITY_SERVICES = {
    'chat': '_llm-chat._tcp',
    'embedding': '_llm-embedding._tcp',
    'vision': '_llm-vision._tcp',
    'code': '_llm-code._tcp',
    'audio': '_llm-audio._tcp',
    'image-gen': '_llm-image-gen._tcp',
    'rerank': '_llm-rerank._tcp',
}


@dataclass
class LLMEndpoint:
    """Represents a discovered LLM endpoint"""
    hostname: str
    port: int
    priority: int
    weight: int
    metadata: Dict[str, str] = None

    @property
    def base_url(self) -> str:
        """Construct base URL from hostname, port, and (optional) scheme metadata"""
        # Scheme precedence: TXT "scheme" value, then port-443 heuristic
        protocol = (self.metadata or {}).get('scheme') or \
            ("https" if self.port == 443 else "http")
        if (protocol == "https" and self.port == 443) or \
           (protocol == "http" and self.port == 80):
            return f"{protocol}://{self.hostname}"
        return f"{protocol}://{self.hostname}:{self.port}"

    def __repr__(self):
        return f"LLMEndpoint({self.hostname}:{self.port}, priority={self.priority}, weight={self.weight})"


class LLMDiscoveryClient:
    """
    Client for discovering and connecting to LLM services via DNS SRV records

    Example usage:
        client = LLMDiscoveryClient("corp.example.com")
        endpoint = client.discover_chat()
        response = client.chat(endpoint, "Hello, world!")
    """

    def __init__(
        self,
        domain: str,
        dns_server: Optional[str] = None,
        dns_port: int = 53,
        timeout: float = 5.0
    ):
        """
        Initialize LLM discovery client

        Args:
            domain: Base domain for service discovery (e.g., "corp.example.com")
            dns_server: Custom DNS server (e.g., "127.0.0.1" for local dnsmasq)
            dns_port: DNS server port (default 53, use 5353 for dnsmasq)
            timeout: Connection timeout in seconds
        """
        self.domain = domain
        self.timeout = timeout

        # Configure DNS resolver
        self.resolver = dns.resolver.Resolver()
        if dns_server:
            self.resolver.nameservers = [dns_server]
        if dns_port != 53:
            self.resolver.port = dns_port

        logger.info(f"Initialized LLM discovery for domain: {domain}")
        if dns_server:
            logger.info(f"Using custom DNS server: {dns_server}:{dns_port}")

    def _query_srv(self, service: str) -> List[LLMEndpoint]:
        """
        Query SRV records for a service

        Args:
            service: Service name (e.g., "_llm-chat._tcp")

        Returns:
            List of LLMEndpoint objects sorted by priority and weight
        """
        query_name = f"{service}.{self.domain}"
        logger.info(f"Querying SRV records for: {query_name}")

        try:
            answers = self.resolver.resolve(query_name, 'SRV')
        except dns.resolver.NXDOMAIN:
            logger.error(f"No SRV records found for {query_name}")
            return []
        except dns.resolver.NoAnswer:
            logger.error(f"DNS query returned no answer for {query_name}")
            return []
        except Exception as e:
            logger.error(f"DNS query failed: {e}")
            return []

        endpoints = []
        for rdata in answers:
            endpoint = LLMEndpoint(
                hostname=str(rdata.target).rstrip('.'),
                port=rdata.port,
                priority=rdata.priority,
                weight=rdata.weight
            )
            endpoints.append(endpoint)
            logger.debug(f"Found endpoint: {endpoint}")

        # Sort by priority (ascending), then weight (descending)
        endpoints.sort(key=lambda x: (x.priority, -x.weight))
        return endpoints

    def _query_txt(self, service: str) -> Dict[str, str]:
        """
        Query TXT records for service metadata

        Args:
            service: Service name (e.g., "_llm-chat._tcp")

        Returns:
            Dictionary of metadata key-value pairs
        """
        query_name = f"{service}.{self.domain}"
        metadata = {}

        try:
            answers = self.resolver.resolve(query_name, 'TXT')
            for rdata in answers:
                # TXT record is a list of byte strings
                for txt_string in rdata.strings:
                    txt = txt_string.decode('utf-8')
                    # Parse key=value or just store as-is
                    if '=' in txt:
                        key, value = txt.split('=', 1)
                        metadata[key] = value
                    else:
                        # Store as flag
                        metadata[txt] = "true"

            logger.debug(f"Metadata for {query_name}: {metadata}")
        except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer):
            logger.debug(f"No TXT records found for {query_name}")
        except Exception as e:
            logger.warning(f"Failed to query TXT records: {e}")

        return metadata

    def _select_endpoint(self, endpoints: List[LLMEndpoint]) -> Optional[LLMEndpoint]:
        """
        Select an endpoint using SRV priority and weight algorithm

        RFC 2782 algorithm:
        1. Group by priority
        2. Within priority group, select randomly weighted by weight field
        3. Try endpoints in order until one succeeds

        Args:
            endpoints: List of endpoints (should be sorted)

        Returns:
            Selected endpoint or None
        """
        if not endpoints:
            return None

        # Get all endpoints with lowest priority
        min_priority = endpoints[0].priority
        candidates = [ep for ep in endpoints if ep.priority == min_priority]

        # Calculate total weight
        total_weight = sum(ep.weight for ep in candidates)

        if total_weight == 0:
            # All weights are 0, select randomly
            return random.choice(candidates)

        # Weighted random selection
        r = random.randint(0, total_weight - 1)
        cumulative = 0

        for endpoint in candidates:
            cumulative += endpoint.weight
            if r < cumulative:
                return endpoint

        return candidates[-1]  # Fallback

    def _discover(self, service: str, subdomain: Optional[str] = None) -> Optional[LLMEndpoint]:
        """
        Discover an endpoint for a service, optionally scoped to a
        policy subdomain (e.g. "fast", "smart", "pii").

        Args:
            service: Service name (e.g., "_llm-chat._tcp")
            subdomain: Optional policy subdomain

        Returns:
            Selected endpoint (with metadata) or None
        """
        if subdomain:
            service = f"{service}.{subdomain}"

        endpoints = self._query_srv(service)
        if not endpoints:
            logger.warning(f"No endpoints found for {service}.{self.domain}")
            return None

        endpoint = self._select_endpoint(endpoints)
        endpoint.metadata = self._query_txt(service)
        return endpoint

    def discover(self, capability: str, subdomain: Optional[str] = None) -> Optional[LLMEndpoint]:
        """
        Discover an endpoint by capability name.

        Args:
            capability: One of the canonical capabilities
                (chat, embedding, vision, code, audio, image-gen, rerank)
            subdomain: Optional policy subdomain

        Returns:
            Selected endpoint (with metadata) or None
        """
        try:
            service = CAPABILITY_SERVICES[capability]
        except KeyError:
            raise ValueError(
                f"Unknown capability: {capability!r} "
                f"(choose from: {', '.join(sorted(CAPABILITY_SERVICES))})"
            ) from None
        return self._discover(service, subdomain)

    def discover_chat(self, subdomain: Optional[str] = None) -> Optional[LLMEndpoint]:
        """Discover chat completion endpoint (optionally via a policy subdomain)"""
        return self._discover("_llm-chat._tcp", subdomain)

    def discover_embedding(self, subdomain: Optional[str] = None) -> Optional[LLMEndpoint]:
        """Discover embedding endpoint (optionally via a policy subdomain)"""
        return self._discover("_llm-embedding._tcp", subdomain)

    def discover_vision(self, subdomain: Optional[str] = None) -> Optional[LLMEndpoint]:
        """Discover vision/multimodal endpoint (optionally via a policy subdomain)"""
        return self._discover("_llm-vision._tcp", subdomain)

    def discover_code(self, subdomain: Optional[str] = None) -> Optional[LLMEndpoint]:
        """Discover code-specialized endpoint (optionally via a policy subdomain)"""
        return self._discover("_llm-code._tcp", subdomain)

    def health_check(self, endpoint: LLMEndpoint) -> bool:
        """
        Check if endpoint is healthy

        Args:
            endpoint: Endpoint to check

        Returns:
            True if healthy, False otherwise
        """
        try:
            # Try common health check endpoints
            for path in ['/health', '/healthz', '/ping', '/']:
                url = urljoin(endpoint.base_url, path)
                response = requests.get(url, timeout=self.timeout)
                if response.status_code < 500:
                    logger.debug(f"Health check passed for {endpoint.hostname}")
                    return True
        except Exception as e:
            logger.warning(f"Health check failed for {endpoint.hostname}: {e}")
            return False

        return False

    def chat(
        self,
        endpoint: LLMEndpoint,
        message: str,
        model: Optional[str] = None,
        api_key: Optional[str] = None
    ) -> Dict:
        """
        Send a chat completion request

        Args:
            endpoint: LLM endpoint to use
            message: User message
            model: Model name (optional, uses metadata default if not specified)
            api_key: API key for authentication

        Returns:
            Response dictionary
        """
        # Get path from metadata or use default
        path = endpoint.metadata.get('path', '/v1/messages') if endpoint.metadata else '/v1/messages'
        url = urljoin(endpoint.base_url, path)

        # Use model from metadata if not specified
        if not model and endpoint.metadata:
            model = endpoint.metadata.get('model', 'default')

        headers = {}
        if api_key:
            headers['Authorization'] = f'Bearer {api_key}'

        # OpenAI-compatible format
        payload = {
            "model": model or "default",
            "messages": [{"role": "user", "content": message}]
        }

        logger.info(f"Sending chat request to {url}")

        try:
            response = requests.post(
                url,
                json=payload,
                headers=headers,
                timeout=self.timeout
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Chat request failed: {e}")
            raise


def main():
    """Example usage"""
    import argparse

    parser = argparse.ArgumentParser(description='LLM Discovery Client Example')
    parser.add_argument('--domain', default='dev.local', help='DNS domain')
    parser.add_argument('--dns-server', default='127.0.0.1', help='DNS server')
    parser.add_argument('--dns-port', type=int, default=5353, help='DNS port')
    parser.add_argument('--message', default='Hello, world!', help='Test message')
    parser.add_argument('--capability', default='chat', choices=sorted(CAPABILITY_SERVICES))
    parser.add_argument('--subdomain', help='Policy subdomain (e.g., fast, smart, pii)')
    parser.add_argument('--verbose', action='store_true', help='Verbose logging')

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Initialize client
    client = LLMDiscoveryClient(
        domain=args.domain,
        dns_server=args.dns_server,
        dns_port=args.dns_port
    )

    # Discover endpoint
    print(f"\n🔍 Discovering {args.capability} endpoint...")

    endpoint = client.discover(args.capability, subdomain=args.subdomain)

    if not endpoint:
        print(f"❌ No {args.capability} endpoint found")
        return 1

    print(f"✅ Discovered endpoint: {endpoint}")
    print(f"   URL: {endpoint.base_url}")

    if endpoint.metadata:
        print(f"   Metadata:")
        for key, value in endpoint.metadata.items():
            print(f"      {key}: {value}")

    # Health check
    print(f"\n🏥 Checking endpoint health...")
    if client.health_check(endpoint):
        print("✅ Endpoint is healthy")
    else:
        print("⚠️  Endpoint health check failed (this is expected for mock servers)")

    print(f"\n📝 Sending test message: '{args.message}'")
    print(f"   (This will fail if no mock server is running on {endpoint.hostname}:{endpoint.port})")

    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
