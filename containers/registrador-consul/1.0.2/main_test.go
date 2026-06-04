package main

import (
	"net/netip"
	"strconv"
	"testing"

	containerapi "github.com/moby/moby/api/types/container"
	networkapi "github.com/moby/moby/api/types/network"
	"github.com/moby/moby/client"
)

func TestExtractServicesFromContainerHostModeValidatesLabelAgainstHostPort(t *testing.T) {
	inspected := newInspectResult(t, inspectOptions{
		labels: map[string]string{
			"traefik.enable": "true",
			"traefik.http.services.app.loadbalancer.server.port": "8080",
		},
		internalPorts: []int{80},
		hostPorts: map[int][]int{
			80: {8080},
		},
	})
	extractor := NewServiceExtractor(&Config{Mode: "host", IP: "192.0.2.10"})

	got := extractor.ExtractServicesFromContainer(inspected)

	if len(got) != 1 {
		t.Fatalf("ExtractServicesFromContainer(host label=8080 host=8080 internal=80) returned %d services, want 1", len(got))
	}
	if got[0].Address != "192.0.2.10" {
		t.Errorf("ExtractServicesFromContainer(host).Address = %q, want %q", got[0].Address, "192.0.2.10")
	}
	if got[0].Port != 8080 {
		t.Errorf("ExtractServicesFromContainer(host).Port = %d, want %d", got[0].Port, 8080)
	}
}

func TestExtractServicesFromContainerHostModeRejectsMissingHostPort(t *testing.T) {
	inspected := newInspectResult(t, inspectOptions{
		labels: map[string]string{
			"traefik.enable": "true",
			"traefik.http.services.app.loadbalancer.server.port": "8080",
		},
		internalPorts: []int{8080},
		hostPorts: map[int][]int{
			8080: {18080},
		},
	})
	extractor := NewServiceExtractor(&Config{Mode: "host", IP: "192.0.2.10"})

	got := extractor.ExtractServicesFromContainer(inspected)

	if len(got) != 0 {
		t.Fatalf("ExtractServicesFromContainer(host label=8080 host=18080) returned %d services, want 0", len(got))
	}
}

func TestExtractServicesFromContainerContainerModeValidatesLabelAgainstInternalPort(t *testing.T) {
	inspected := newInspectResult(t, inspectOptions{
		labels: map[string]string{
			"traefik.enable": "true",
			"traefik.http.services.app.loadbalancer.server.port": "8080",
		},
		internalPorts: []int{8080},
	})
	extractor := NewServiceExtractor(&Config{Mode: "container"})

	got := extractor.ExtractServicesFromContainer(inspected)

	if len(got) != 1 {
		t.Fatalf("ExtractServicesFromContainer(container label=8080 internal=8080) returned %d services, want 1", len(got))
	}
	if got[0].Address != "172.20.0.2" {
		t.Errorf("ExtractServicesFromContainer(container).Address = %q, want %q", got[0].Address, "172.20.0.2")
	}
	if got[0].Port != 8080 {
		t.Errorf("ExtractServicesFromContainer(container).Port = %d, want %d", got[0].Port, 8080)
	}
}

func TestExtractServicesFromContainerContainerModeRejectsMissingInternalPort(t *testing.T) {
	inspected := newInspectResult(t, inspectOptions{
		labels: map[string]string{
			"traefik.enable": "true",
			"traefik.http.services.app.loadbalancer.server.port": "8080",
		},
		internalPorts: []int{80},
		hostPorts: map[int][]int{
			80: {8080},
		},
	})
	extractor := NewServiceExtractor(&Config{Mode: "container"})

	got := extractor.ExtractServicesFromContainer(inspected)

	if len(got) != 0 {
		t.Fatalf("ExtractServicesFromContainer(container label=8080 internal=80) returned %d services, want 0", len(got))
	}
}

type inspectOptions struct {
	labels        map[string]string
	internalPorts []int
	hostPorts     map[int][]int
}

func newInspectResult(t *testing.T, opts inspectOptions) *client.ContainerInspectResult {
	t.Helper()

	ports := networkapi.PortMap{}
	exposedPorts := networkapi.PortSet{}

	for _, internalPort := range opts.internalPorts {
		port := mustPort(t, internalPort)
		ports[port] = nil
		exposedPorts[port] = struct{}{}
	}

	for internalPort, hostPorts := range opts.hostPorts {
		port := mustPort(t, internalPort)
		for _, hostPort := range hostPorts {
			ports[port] = append(ports[port], networkapi.PortBinding{
				HostPort: portString(hostPort),
			})
		}
	}

	return &client.ContainerInspectResult{
		Container: containerapi.InspectResponse{
			ID:   "0123456789abcdef",
			Name: "/app",
			Config: &containerapi.Config{
				Labels:       opts.labels,
				ExposedPorts: exposedPorts,
			},
			NetworkSettings: &containerapi.NetworkSettings{
				Ports: ports,
				Networks: map[string]*networkapi.EndpointSettings{
					"web": {
						IPAddress: netip.MustParseAddr("172.20.0.2"),
					},
				},
			},
		},
	}
}

func mustPort(t *testing.T, port int) networkapi.Port {
	t.Helper()

	parsed, err := networkapi.ParsePort(portString(port) + "/tcp")
	if err != nil {
		t.Fatalf("ParsePort(%d/tcp) error = %v, want nil", port, err)
	}
	return parsed
}

func portString(port int) string {
	return strconv.Itoa(port)
}
