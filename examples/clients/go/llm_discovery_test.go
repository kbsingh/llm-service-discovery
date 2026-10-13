package llmdiscovery

import "testing"

func TestBaseURLSchemePrecedence(t *testing.T) {
	cases := []struct {
		name     string
		endpoint Endpoint
		want     string
	}{
		{
			name:     "port 443 infers https and omits the port",
			endpoint: Endpoint{Hostname: "api.example.com", Port: 443},
			want:     "https://api.example.com",
		},
		{
			name:     "port 80 infers http and omits the port",
			endpoint: Endpoint{Hostname: "api.example.com", Port: 80},
			want:     "http://api.example.com",
		},
		{
			name:     "non-standard port keeps the port",
			endpoint: Endpoint{Hostname: "llm", Port: 8080},
			want:     "http://llm:8080",
		},
		{
			name: "scheme metadata overrides port heuristic (8443 TLS)",
			endpoint: Endpoint{
				Hostname: "llm-secure.internal",
				Port:     8443,
				Metadata: map[string]string{"scheme": "https"},
			},
			want: "https://llm-secure.internal:8443",
		},
		{
			name: "scheme metadata overrides port 443 too",
			endpoint: Endpoint{
				Hostname: "weird",
				Port:     443,
				Metadata: map[string]string{"scheme": "http"},
			},
			want: "http://weird:443",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.endpoint.BaseURL()
			if got != tc.want {
				t.Fatalf("BaseURL() = %q, want %q", got, tc.want)
			}
		})
	}
}
