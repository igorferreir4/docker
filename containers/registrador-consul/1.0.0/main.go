package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	consulapi "github.com/hashicorp/consul/api"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/events"
	"github.com/moby/moby/api/types/network"
	"github.com/moby/moby/client"
)

// ============================================
// CONFIGURAÇÃO
// ============================================

type Config struct {
	Mode                  string
	IP                    string
	ConsulURL             string
	ResyncInterval        int
	DockerSocket          string
	DeregisterRetries     int
	DeregisterRetryDelay  int
	RegistryID            string
}

func NewConfig() *Config {
	config := &Config{
		Mode:                 strings.Trim(getEnv("MODE", "container"), "\""),
		IP:                   strings.Trim(getEnv("IP", ""), "\""),
		ConsulURL:            strings.Trim(getEnv("CONSUL_URL", "http://consul:8500"), "\""),
		ResyncInterval:       getEnvAsInt("RESYNC_INTERVAL", 60),
		DockerSocket:         strings.Trim(getEnv("DOCKER_SOCKET", ""), "\""),
		DeregisterRetries:    getEnvAsInt("DEREGISTER_RETRIES", 3),
		DeregisterRetryDelay: getEnvAsInt("DEREGISTER_RETRY_DELAY", 2),
		RegistryID:           strings.Trim(getEnv("REGISTRADOR_ID", defaultRegistryID()), "\""),
	}

	config.Mode = strings.ToLower(config.Mode)
	config.validate()
	return config
}

func (c *Config) validate() {
	if c.Mode != "container" && c.Mode != "host" {
		log.Fatalf("MODE inválido: '%s'. Use 'container' ou 'host'", c.Mode)
	}

	if c.Mode == "host" && c.IP == "" {
		log.Fatal("MODE=host requer variável IP definida")
	}

	if c.ResyncInterval < 10 {
		log.Printf("RESYNC_INTERVAL muito baixo (%ds), usando 10s", c.ResyncInterval)
		c.ResyncInterval = 10
	}
}

func (c *Config) PrintConfig() {
	log.Println("╔══════════════════════════════════════════════════════╗")
	log.Println("║              Registrador Docker → Consul             ║")
	log.Println("╚══════════════════════════════════════════════════════╝")
	log.Println("")
	log.Println("Configuração:")
	log.Printf("  Modo: %s", strings.ToUpper(c.Mode))

	if c.Mode == "host" {
		log.Printf("  IP público: %s", c.IP)
		log.Println("  Porta: Host (mapeada)")
		log.Println("  Label port: Ignorada (não registra como tag)")
	} else {
		log.Println("  IP: Container (dinâmico)")
		log.Println("  Porta: Container (da label)")
		log.Println("  Label port: Incluída nas tags")
	}

	log.Printf("  Consul: %s", c.ConsulURL)
	log.Printf("  Resync: %ds", c.ResyncInterval)
	if c.RegistryID != "" {
		log.Printf("  Registrador ID: %s", c.RegistryID)
	}
	if c.DockerSocket != "" {
		log.Printf("  Docker: TCP %s", c.DockerSocket)
	} else {
		log.Println("  Docker: Socket local")
	}
	log.Printf("  Retry: %dx (delay %ds)", c.DeregisterRetries, c.DeregisterRetryDelay)
	log.Println("")
}

// ============================================
// CLIENTE DOCKER
// ============================================

type DockerClient struct {
	client *client.Client
	config *Config
}

func NewDockerClient(config *Config) *DockerClient {
	var cli *client.Client
	var err error

	if config.DockerSocket != "" {
		cli, err = client.NewClientWithOpts(
			client.WithHost(config.DockerSocket),
		)
		if err == nil {
			log.Printf("Conectado ao Docker via TCP: %s", config.DockerSocket)
		}
	} else {
		cli, err = client.NewClientWithOpts(
			client.FromEnv,
		)
		if err == nil {
			log.Println("Conectado ao Docker via socket local")
		}
	}

	if err != nil {
		log.Fatalf("Falha ao conectar no Docker: %v", err)
	}

	// Testa conectividade
	ctx := context.Background()
	_, err = cli.Ping(ctx, client.PingOptions{})
	if err != nil {
		log.Fatalf("Falha ao fazer ping no Docker: %v", err)
	}

	return &DockerClient{
		client: cli,
		config: config,
	}
}

func (d *DockerClient) ListContainers() ([]container.Summary, error) {
	ctx := context.Background()
	result, err := d.client.ContainerList(ctx, client.ContainerListOptions{})
	if err != nil {
		log.Printf("Erro ao listar containers: %v", err)
		return []container.Summary{}, err
	}
	return result.Items, nil
}

func (d *DockerClient) GetContainer(containerID string) (*client.ContainerInspectResult, error) {
	ctx := context.Background()
	result, err := d.client.ContainerInspect(ctx, containerID, client.ContainerInspectOptions{})
	if err != nil {
		return nil, err
	}
	return &result, nil
}

func (d *DockerClient) ListenEvents(ctx context.Context) (<-chan events.Message, <-chan error) {
	result := d.client.Events(ctx, client.EventsListOptions{})
	eventsChan := make(chan events.Message)
	errorsChan := make(chan error, 1)

	go func() {
		defer close(eventsChan)
		defer close(errorsChan)

		for {
			select {
			case event := <-result.Messages:
				eventsChan <- event
			case err := <-result.Err:
				if err != nil {
					errorsChan <- err
					return
				}
			case <-ctx.Done():
				return
			}
		}
	}()

	return eventsChan, errorsChan
}

// ============================================
// CLIENTE CONSUL
// ============================================

type ConsulClient struct {
	client *consulapi.Client
	config *Config
}

func NewConsulClient(config *Config) *ConsulClient {
	consulConfig := consulapi.DefaultConfig()
	consulConfig.Address = strings.TrimPrefix(config.ConsulURL, "http://")
	consulConfig.Address = strings.TrimPrefix(consulConfig.Address, "https://")

	cli, err := consulapi.NewClient(consulConfig)
	if err != nil {
		log.Fatalf("Falha ao criar cliente Consul: %v", err)
	}

	// Testa conectividade
	_, err = cli.Status().Leader()
	if err != nil {
		log.Fatalf("Falha ao conectar no Consul: %v", err)
	}

	log.Printf("Conectado ao Consul: %s", config.ConsulURL)
	return &ConsulClient{
		client: cli,
		config: config,
	}
}

func (c *ConsulClient) RegistryTag() string {
	if c.config.RegistryID == "" {
		return ""
	}
	return "registrador_id=" + c.config.RegistryID
}

func (c *ConsulClient) RegisterService(serviceID, name, address string, port int, tags []string) bool {
	registryTag := c.RegistryTag()
	if registryTag != "" && !hasTag(tags, registryTag) {
		tags = append(tags, registryTag)
	}

	registration := &consulapi.AgentServiceRegistration{
		ID:      serviceID,
		Name:    name,
		Address: address,
		Port:    port,
		Tags:    tags,
	}

	err := c.client.Agent().ServiceRegister(registration)
	if err != nil {
		log.Printf("✗ Erro ao registrar %s: %v", serviceID, err)
		return false
	}

	log.Printf("✓ Registrado: %s (%s:%d) [%s]", name, address, port, serviceID)
	return true
}

func (c *ConsulClient) DeregisterService(serviceID string) bool {
	for attempt := 0; attempt < c.config.DeregisterRetries; attempt++ {
		err := c.client.Agent().ServiceDeregister(serviceID)
		if err == nil {
			log.Printf("✓ Removido: %s", serviceID)
			return true
		}

		if attempt < c.config.DeregisterRetries-1 {
			log.Printf("⚠ Tentativa %d/%d falhou para %s: %v",
				attempt+1, c.config.DeregisterRetries, serviceID, err)
			time.Sleep(time.Duration(c.config.DeregisterRetryDelay) * time.Second)
		} else {
			log.Printf("✗ Falha definitiva ao remover %s: %v", serviceID, err)
		}
	}
	return false
}

func (c *ConsulClient) GetServices() (map[string]*consulapi.AgentService, error) {
	services, err := c.client.Agent().Services()
	if err != nil {
		log.Printf("Erro ao listar serviços do Consul: %v", err)
		return map[string]*consulapi.AgentService{}, err
	}
	return services, nil
}

// ============================================
// EXTRATOR DE SERVIÇOS
// ============================================

type ServiceExtractor struct {
	config *Config
}

type ServiceInfo struct {
	ID      string
	Name    string
	Address string
	Port    int
	Tags    []string
}

func NewServiceExtractor(config *Config) *ServiceExtractor {
	return &ServiceExtractor{config: config}
}

func (s *ServiceExtractor) GetContainerIP(containerInfo *client.ContainerInspectResult) string {
	if containerInfo.Container.NetworkSettings == nil {
		return ""
	}
	networks := containerInfo.Container.NetworkSettings.Networks
	for _, net := range networks {
		if net.IPAddress.IsValid() && !net.IPAddress.IsUnspecified() {
			return net.IPAddress.String()
		}
	}
	return ""
}

func (s *ServiceExtractor) GetHostPort(containerInfo *client.ContainerInspectResult, labelPort int) int {
	if containerInfo.Container.NetworkSettings == nil {
		return 0
	}
	ports := containerInfo.Container.NetworkSettings.Ports
	portKey, err := network.ParsePort(fmt.Sprintf("%d/tcp", labelPort))
	if err != nil {
		return 0
	}

	if bindings, exists := ports[portKey]; exists && len(bindings) > 0 {
		hostPort, err := strconv.Atoi(bindings[0].HostPort)
		if err == nil {
			return hostPort
		}
	}
	return 0
}

func (s *ServiceExtractor) ExtractTraefikServices(labels map[string]string) map[string]int {
	services := make(map[string]int)

	for key, value := range labels {
		// traefik.http.services.<SERVICE_NAME>.loadbalancer.server.port=80
		if strings.HasPrefix(key, "traefik.http.services.") &&
			strings.HasSuffix(key, ".loadbalancer.server.port") {

			parts := strings.Split(key, ".")
			if len(parts) >= 4 {
				serviceName := parts[3]
				port, err := strconv.Atoi(value)
				if err == nil {
					services[serviceName] = port
				} else {
					log.Printf("Label inválida: %s=%s - %v", key, value, err)
				}
			}
		}
	}

	return services
}

func (s *ServiceExtractor) BuildServiceTags(labels map[string]string, serviceName string) []string {
	var tags []string

	for key, value := range labels {
		if !strings.HasPrefix(key, "traefik.") {
			continue
		}

		// Labels globais
		if !strings.Contains(key, ".services.") && !strings.Contains(key, ".routers.") {
			tags = append(tags, fmt.Sprintf("%s=%s", key, value))
			continue
		}

		// Labels específicas deste serviço
		if strings.Contains(key, fmt.Sprintf(".services.%s.", serviceName)) ||
			strings.Contains(key, fmt.Sprintf(".routers.%s.", serviceName)) {

			// Em modo host: ignora label de porta
			if strings.HasSuffix(key, ".loadbalancer.server.port") {
				if s.config.Mode == "container" {
					tags = append(tags, fmt.Sprintf("%s=%s", key, value))
				}
			} else {
				tags = append(tags, fmt.Sprintf("%s=%s", key, value))
			}
		}
	}

	return tags
}

func (s *ServiceExtractor) ExtractServicesFromContainer(containerInfo *client.ContainerInspectResult) []ServiceInfo {
	if containerInfo.Container.Config == nil {
		return []ServiceInfo{}
	}
	labels := containerInfo.Container.Config.Labels
	if labels == nil {
		return []ServiceInfo{}
	}

	// Container deve ter traefik.enable=true
	if labels["traefik.enable"] != "true" {
		return []ServiceInfo{}
	}

	// Encontrar todos os serviços definidos
	services := s.ExtractTraefikServices(labels)

	if len(services) == 0 {
		return []ServiceInfo{}
	}

	var result []ServiceInfo

	for serviceName, labelPort := range services {
		var address string
		var port int

		if s.config.Mode == "host" {
			// Modo host
			address = s.config.IP
			port = s.GetHostPort(containerInfo, labelPort)

			if port == 0 {
				log.Printf("%s/%s: Porta %d não está mapeada no host",
					containerInfo.Container.Name, serviceName, labelPort)
				continue
			}
		} else {
			// Modo container
			address = s.GetContainerIP(containerInfo)

			if address == "" {
				log.Printf("%s: Não foi possível obter IP do container", containerInfo.Container.Name)
				continue
			}

			port = labelPort
		}

		// Construir tags
		tags := s.BuildServiceTags(labels, serviceName)

		// ID único
		shortID := containerInfo.Container.ID[:12]
		serviceID := fmt.Sprintf("%s-%s", serviceName, shortID)

		result = append(result, ServiceInfo{
			ID:      serviceID,
			Name:    serviceName,
			Address: address,
			Port:    port,
			Tags:    tags,
		})
	}

	return result
}

// ============================================
// GERENCIADOR DE SINCRONIZAÇÃO
// ============================================

type ServiceRegistry struct {
	config    *Config
	docker    *DockerClient
	consul    *ConsulClient
	extractor *ServiceExtractor
}

type Endpoint struct {
	Address string
	Port    int
}

func NewServiceRegistry(config *Config) *ServiceRegistry {
	return &ServiceRegistry{
		config:    config,
		docker:    NewDockerClient(config),
		consul:    NewConsulClient(config),
		extractor: NewServiceExtractor(config),
	}
}

func (sr *ServiceRegistry) GetActiveEndpoints() map[Endpoint]bool {
	endpoints := make(map[Endpoint]bool)

	containers, err := sr.docker.ListContainers()
	if err != nil {
		return endpoints
	}

	for _, cont := range containers {
		containerInfo, err := sr.docker.GetContainer(cont.ID)
		if err != nil {
			continue
		}

		services := sr.extractor.ExtractServicesFromContainer(containerInfo)
		for _, svc := range services {
			endpoints[Endpoint{Address: svc.Address, Port: svc.Port}] = true
		}
	}

	return endpoints
}

func (sr *ServiceRegistry) isManagedService(serviceInfo *consulapi.AgentService) bool {
	registryTag := sr.consul.RegistryTag()
	if registryTag == "" {
		return false
	}
	return hasTag(serviceInfo.Tags, registryTag)
}

func (sr *ServiceRegistry) SyncAll() {
	log.Println("═══ Iniciando resync completo ═══")
	registeredCount := 0
	activeServiceIDs := make(map[string]bool)

	// Fase 1: Registrar serviços ativos
	containers, err := sr.docker.ListContainers()
	if err == nil {
		log.Printf("Encontrados %d containers ativos", len(containers))

		for _, cont := range containers {
			containerInfo, err := sr.docker.GetContainer(cont.ID)
			if err != nil {
				continue
			}

			services := sr.extractor.ExtractServicesFromContainer(containerInfo)
			for _, svc := range services {
				activeServiceIDs[svc.ID] = true
				if sr.consul.RegisterService(svc.ID, svc.Name, svc.Address, svc.Port, svc.Tags) {
					registeredCount++
				}
			}
		}
	}

	// Fase 2: Remover serviços órfãos
	consulServices, err := sr.consul.GetServices()

	if err == nil {
		var orphans []struct {
			ID      string
			Address string
			Port    int
		}

		for serviceID, serviceInfo := range consulServices {
			// Verificar se este serviço é gerenciado por este registrador
			if sr.isManagedService(serviceInfo) && !activeServiceIDs[serviceID] {
				orphans = append(orphans, struct {
					ID      string
					Address string
					Port    int
				}{serviceID, serviceInfo.Address, serviceInfo.Port})
			}
		}

		if len(orphans) > 0 {
			log.Printf("Encontrados %d serviços órfãos", len(orphans))
			for _, orphan := range orphans {
				log.Printf("  Órfão: %s (%s:%d)", orphan.ID, orphan.Address, orphan.Port)
				sr.consul.DeregisterService(orphan.ID)
			}
		} else {
			log.Println("Nenhum serviço órfão encontrado")
		}
	}

	log.Printf("═══ Resync completo: %d serviços ativos ═══", registeredCount)
}

func (sr *ServiceRegistry) HandleContainerStart(containerID string) {
	containerInfo, err := sr.docker.GetContainer(containerID)
	if err != nil {
		return
	}

	// Aguardar um pouco para garantir que o container está pronto
	time.Sleep(1 * time.Second)

	services := sr.extractor.ExtractServicesFromContainer(containerInfo)
	for _, svc := range services {
		sr.consul.RegisterService(svc.ID, svc.Name, svc.Address, svc.Port, svc.Tags)
	}
}

func (sr *ServiceRegistry) HandleContainerStop(containerID string) {
	shortID := containerID[:12]

	consulServices, err := sr.consul.GetServices()
	if err != nil {
		return
	}

	removedCount := 0
	for serviceID, serviceInfo := range consulServices {
		if strings.HasSuffix(serviceID, shortID) && sr.isManagedService(serviceInfo) {
			if sr.consul.DeregisterService(serviceID) {
				removedCount++
			}
		}
	}

	if removedCount > 0 {
		log.Printf("Limpeza: %d serviços removidos", removedCount)
	}
}

func (sr *ServiceRegistry) HandleEvent(event events.Message) {
	if event.Type != events.ContainerEventType {
		return
	}

	action := event.Action
	containerID := event.Actor.ID

	if containerID == "" {
		return
	}

	// Filtrar apenas eventos relevantes
	relevantActions := map[events.Action]bool{
		"start":   true,
		"update":  true,
		"stop":    true,
		"die":     true,
		"destroy": true,
	}

	if !relevantActions[action] {
		return
	}

	log.Printf("→ Evento: %s [%s]", action, containerID[:12])

	if action == "start" || action == "update" {
		sr.HandleContainerStart(containerID)
	} else if action == "stop" || action == "die" || action == "destroy" {
		sr.HandleContainerStop(containerID)
	}
}

func (sr *ServiceRegistry) EventListener(ctx context.Context, wg *sync.WaitGroup) {
	defer wg.Done()
	log.Println("Listener de eventos Docker iniciado")

	for {
		eventsChan, errChan := sr.docker.ListenEvents(ctx)

		for {
			select {
			case event := <-eventsChan:
				sr.HandleEvent(event)
			case err := <-errChan:
				if err != nil {
					log.Printf("Erro no listener de eventos: %v", err)
					time.Sleep(5 * time.Second)
				}
				goto reconnect
			case <-ctx.Done():
				return
			}
		}

	reconnect:
		time.Sleep(1 * time.Second)
	}
}

func (sr *ServiceRegistry) ResyncLoop(ctx context.Context, wg *sync.WaitGroup) {
	defer wg.Done()
	log.Printf("Loop de resync iniciado (intervalo: %ds)", sr.config.ResyncInterval)

	ticker := time.NewTicker(time.Duration(sr.config.ResyncInterval) * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			sr.SyncAll()
		case <-ctx.Done():
			return
		}
	}
}

func (sr *ServiceRegistry) Run() {
	// Sincronização inicial
	sr.SyncAll()

	// Context para gerenciar goroutines
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var wg sync.WaitGroup

	// Iniciar goroutines de monitoramento
	wg.Add(2)
	go sr.EventListener(ctx, &wg)
	go sr.ResyncLoop(ctx, &wg)

	log.Println("✓ Registrador ativo e monitorando eventos")

	// Manter o programa rodando
	wg.Wait()
}

// ============================================
// UTILIDADES
// ============================================

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

func getEnvAsInt(key string, defaultValue int) int {
	valueStr := os.Getenv(key)
	if valueStr == "" {
		return defaultValue
	}
	valueStr = strings.Trim(valueStr, "\"")
	value, err := strconv.Atoi(valueStr)
	if err != nil {
		return defaultValue
	}
	return value
}

func defaultRegistryID() string {
	hostname, err := os.Hostname()
	if err != nil {
		return ""
	}
	return hostname
}

func hasTag(tags []string, tag string) bool {
	for _, t := range tags {
		if t == tag {
			return true
		}
	}
	return false
}

// ============================================
// MAIN
// ============================================

func main() {
	config := NewConfig()
	config.PrintConfig()

	registry := NewServiceRegistry(config)
	registry.Run()
}
