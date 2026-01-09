import os
import sys
import time
import threading
import logging
import docker
import requests

# ============================================
# CONFIGURAÇÃO DE LOGGING
# ============================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

# ============================================
# CONFIGURAÇÕES VIA ENVIRONMENT VARIABLES
# ============================================

class Config:
    """Configurações da aplicação"""
    
    def __init__(self):
        # Modo de operação: 'container' ou 'host'
        self.MODE = os.getenv("MODE", "container").lower().strip('"')
        
        # IP público (obrigatório apenas em modo host)
        self.IP = os.getenv("IP", "").strip('"')
        
        # URL do Consul
        self.CONSUL_URL = os.getenv("CONSUL_URL", "http://consul:8500").strip('"')
        
        # Intervalo de resync em segundos
        self.RESYNC_INTERVAL = int(os.getenv("RESYNC_INTERVAL", "60").strip('"'))
        
        # Docker socket: se vazio usa /var/run/docker.sock, senão usa TCP
        self.DOCKER_SOCKET = os.getenv("DOCKER_SOCKET", "").strip('"')
        
        # Configurações de retry para deregister
        self.DEREGISTER_RETRIES = int(os.getenv("DEREGISTER_RETRIES", "3").strip('"'))
        self.DEREGISTER_RETRY_DELAY = int(os.getenv("DEREGISTER_RETRY_DELAY", "2").strip('"'))
        
        # Validações
        self._validate()
    
    def _validate(self):
        """Valida configurações obrigatórias"""
        if self.MODE not in ["container", "host"]:
            log.error(f"MODE inválido: '{self.MODE}'. Use 'container' ou 'host'")
            sys.exit(1)
        
        if self.MODE == "host" and not self.IP:
            log.error("MODE=host requer variável IP definida")
            sys.exit(1)
        
        if self.RESYNC_INTERVAL < 10:
            log.warning(f"RESYNC_INTERVAL muito baixo ({self.RESYNC_INTERVAL}s), usando 10s")
            self.RESYNC_INTERVAL = 10
    
    def print_config(self):
        """Imprime configuração atual"""
        log.info("╔══════════════════════════════════════════════════════╗")
        log.info("║              Registrador Docker → Consul             ║")
        log.info("╚══════════════════════════════════════════════════════╝")
        log.info("")
        log.info("Configuração:")
        log.info(f"  Modo: {self.MODE.upper()}")
        
        if self.MODE == "host":
            log.info(f"  IP público: {self.IP}")
            log.info(f"  Porta: Host (mapeada)")
            log.info(f"  Label port: Ignorada (não registra como tag)")
        else:
            log.info(f"  IP: Container (dinâmico)")
            log.info(f"  Porta: Container (da label)")
            log.info(f"  Label port: Incluída nas tags")
        
        log.info(f"  Consul: {self.CONSUL_URL}")
        log.info(f"  Resync: {self.RESYNC_INTERVAL}s")
        log.info(f"  Docker: {'TCP ' + self.DOCKER_SOCKET if self.DOCKER_SOCKET else 'Socket local'}")
        log.info(f"  Retry: {self.DEREGISTER_RETRIES}x (delay {self.DEREGISTER_RETRY_DELAY}s)")
        log.info("")


# ============================================
# CLIENTE DOCKER
# ============================================

class DockerClient:
    """Gerenciador de conexão com Docker"""
    
    def __init__(self, config: Config):
        self.config = config
        try:
            if config.DOCKER_SOCKET:
                self.client = docker.DockerClient(base_url=config.DOCKER_SOCKET, timeout=10)
                log.info(f"Conectado ao Docker via TCP: {config.DOCKER_SOCKET}")
            else:
                self.client = docker.from_env(timeout=10)
                log.info("Conectado ao Docker via socket local")
            
            # Testa conectividade
            self.client.ping()
        except Exception as e:
            log.error(f"Falha ao conectar no Docker: {e}")
            sys.exit(1)
    
    def list_containers(self):
        """Retorna lista de containers em execução"""
        try:
            return self.client.containers.list()
        except Exception as e:
            log.error(f"Erro ao listar containers: {e}")
            return []
    
    def get_container(self, container_id):
        """Obtém container por ID"""
        try:
            return self.client.containers.get(container_id)
        except docker.errors.NotFound:
            return None
        except Exception as e:
            log.error(f"Erro ao obter container {container_id[:12]}: {e}")
            return None
    
    def listen_events(self):
        """Generator de eventos Docker"""
        return self.client.events(decode=True)


# ============================================
# CLIENTE CONSUL
# ============================================

class ConsulClient:
    """Gerenciador de comunicação com Consul"""
    
    def __init__(self, config: Config):
        self.config = config
        self.session = requests.Session()
        self.session.headers.update({"Content-Type": "application/json"})
        
        # Testa conectividade
        try:
            r = self.session.get(f"{config.CONSUL_URL}/v1/status/leader", timeout=5)
            r.raise_for_status()
            log.info(f"Conectado ao Consul: {config.CONSUL_URL}")
        except Exception as e:
            log.error(f"Falha ao conectar no Consul: {e}")
            sys.exit(1)
    
    def register_service(self, service_id, name, address, port, tags):
        """Registra um serviço no Consul"""
        try:
            payload = {
                "ID": service_id,
                "Name": name,
                "Address": address,
                "Port": port,
                "Tags": tags,
            }
            r = self.session.put(
                f"{self.config.CONSUL_URL}/v1/agent/service/register",
                json=payload,
                timeout=5,
            )
            r.raise_for_status()
            log.info(f"✓ Registrado: {name} ({address}:{port}) [{service_id}]")
            return True
        except Exception as e:
            log.error(f"✗ Erro ao registrar {service_id}: {e}")
            return False
    
    def deregister_service(self, service_id):
        """Remove um serviço do Consul com retry"""
        for attempt in range(self.config.DEREGISTER_RETRIES):
            try:
                r = self.session.put(
                    f"{self.config.CONSUL_URL}/v1/agent/service/deregister/{service_id}",
                    timeout=5,
                )
                r.raise_for_status()
                log.info(f"✓ Removido: {service_id}")
                return True
            except Exception as e:
                if attempt < self.config.DEREGISTER_RETRIES - 1:
                    log.warning(
                        f"⚠ Tentativa {attempt + 1}/{self.config.DEREGISTER_RETRIES} "
                        f"falhou para {service_id}: {e}"
                    )
                    time.sleep(self.config.DEREGISTER_RETRY_DELAY)
                else:
                    log.error(f"✗ Falha definitiva ao remover {service_id}: {e}")
        return False
    
    def get_services(self):
        """Retorna todos os serviços registrados no Consul"""
        try:
            r = self.session.get(
                f"{self.config.CONSUL_URL}/v1/agent/services",
                timeout=5
            )
            r.raise_for_status()
            return r.json()
        except Exception as e:
            log.error(f"Erro ao listar serviços do Consul: {e}")
            return {}


# ============================================
# EXTRATOR DE SERVIÇOS
# ============================================

class ServiceExtractor:
    """Extrai configurações de serviços dos containers Docker"""
    
    def __init__(self, config: Config):
        self.config = config
    
    def get_container_ip(self, container):
        """Obtém o IP do container na primeira rede disponível"""
        try:
            networks = container.attrs["NetworkSettings"]["Networks"]
            for network_name, network_info in networks.items():
                ip = network_info.get("IPAddress")
                if ip:
                    return ip
        except Exception as e:
            log.warning(f"Erro ao obter IP do container {container.short_id}: {e}")
        return None
    
    def get_host_port(self, container, label_port):
        """Obtém porta mapeada no host para a porta interna especificada"""
        try:
            ports = container.attrs["NetworkSettings"]["Ports"]
            port_key = f"{label_port}/tcp"
            
            if port_key in ports and ports[port_key] and len(ports[port_key]) > 0:
                return int(ports[port_key][0]["HostPort"])
        except Exception as e:
            log.warning(f"Erro ao obter porta do host para {container.short_id}: {e}")
        return None
    
    def extract_traefik_services(self, labels):
        """
        Extrai serviços definidos nas labels do Traefik
        Retorna dict: {service_name: port}
        """
        services = {}
        for key, value in labels.items():
            # Label: traefik.http.services.<SERVICE_NAME>.loadbalancer.server.port=80
            if (key.startswith("traefik.http.services.") and 
                key.endswith(".loadbalancer.server.port")):
                try:
                    service_name = key.split(".")[3]
                    port = int(value)
                    services[service_name] = port
                except (IndexError, ValueError) as e:
                    log.warning(f"Label inválida: {key}={value} - {e}")
        return services
    
    def build_service_tags(self, labels, service_name):
        """
        Constrói lista de tags para o serviço no Consul
        Em modo host: ignora label de porta
        Em modo container: inclui todas as labels relevantes
        """
        tags = []
        
        for key, value in labels.items():
            if not key.startswith("traefik."):
                continue
            
            # Labels globais (sem nome de serviço específico)
            if ".services." not in key and ".routers." not in key:
                tags.append(f"{key}={value}")
                continue
            
            # Labels específicas deste serviço
            if f".services.{service_name}." in key or f".routers.{service_name}." in key:
                # Em modo host: ignora label de porta
                if key.endswith(".loadbalancer.server.port"):
                    if self.config.MODE == "container":
                        tags.append(f"{key}={value}")
                    else:
                        log.debug(f"Modo host: ignorando label de porta {key}")
                else:
                    tags.append(f"{key}={value}")
        
        return tags
    
    def extract_services_from_container(self, container):
        """
        Extrai todos os serviços de um container
        Retorna lista de tuplas: (service_id, service_name, address, port, tags)
        """
        labels = container.labels
        
        # Container deve ter traefik.enable=true
        if labels.get("traefik.enable") != "true":
            return []
        
        # Encontrar todos os serviços definidos
        services = self.extract_traefik_services(labels)
        
        if not services:
            log.debug(f"{container.name}: Sem serviços Traefik definidos")
            return []
        
        result = []
        
        # Processar cada serviço
        for service_name, label_port in services.items():
            # Determinar endereço e porta baseado no modo
            if self.config.MODE == "host":
                # Modo host: IP público + porta mapeada no host
                address = self.config.IP
                port = self.get_host_port(container, label_port)
                
                if not port:
                    log.warning(
                        f"{container.name}/{service_name}: "
                        f"Porta {label_port} não está mapeada no host"
                    )
                    continue
                
                log.debug(
                    f"{container.name}/{service_name}: "
                    f"Modo host - porta {label_port} → {port}"
                )
            
            else:  # mode == container
                # Modo container: IP interno + porta da label
                address = self.get_container_ip(container)
                
                if not address:
                    log.warning(f"{container.name}: Não foi possível obter IP do container")
                    continue
                
                port = label_port
                log.debug(
                    f"{container.name}/{service_name}: "
                    f"Modo container - IP {address}:{port}"
                )
            
            # Construir tags
            tags = self.build_service_tags(labels, service_name)
            
            # ID único: service_name-container_short_id
            service_id = f"{service_name}-{container.short_id}"
            
            result.append((service_id, service_name, address, port, tags))
        
        return result


# ============================================
# GERENCIADOR DE SINCRONIZAÇÃO
# ============================================

class ServiceRegistry:
    """Gerenciador principal de sincronização Docker ↔ Consul"""
    
    def __init__(self, config: Config):
        self.config = config
        self.docker = DockerClient(config)
        self.consul = ConsulClient(config)
        self.extractor = ServiceExtractor(config)
    
    def get_active_endpoints(self):
        """
        Retorna set de (address, port) de todos os serviços ativos no Docker
        Usado para identificar serviços órfãos no Consul
        """
        endpoints = set()
        try:
            for container in self.docker.list_containers():
                for svc in self.extractor.extract_services_from_container(container):
                    # svc = (service_id, service_name, address, port, tags)
                    endpoints.add((svc[2], svc[3]))  # (address, port)
        except Exception as e:
            log.error(f"Erro ao coletar endpoints ativos: {e}")
        return endpoints
    
    def sync_all(self):
        """
        Sincronização completa:
        1. Registra todos os serviços de containers ativos
        2. Remove serviços órfãos do Consul
        """
        log.info("═══ Iniciando resync completo ═══")
        registered_count = 0
        
        # Fase 1: Registrar serviços ativos
        try:
            containers = self.docker.list_containers()
            log.info(f"Encontrados {len(containers)} containers ativos")
            
            for container in containers:
                services = self.extractor.extract_services_from_container(container)
                for svc in services:
                    if self.consul.register_service(*svc):
                        registered_count += 1
        except Exception as e:
            log.error(f"Erro ao registrar serviços: {e}")
        
        # Fase 2: Remover serviços órfãos
        try:
            active_endpoints = self.get_active_endpoints()
            consul_services = self.consul.get_services()
            
            orphans = []
            for service_id, service_info in consul_services.items():
                service_address = service_info.get("Address")
                service_port = service_info.get("Port")
                
                # Verificar se este serviço é gerenciado por este registrador
                if self.config.MODE == "host":
                    # Modo host: gerenciar apenas serviços com o IP configurado
                    is_managed = (service_address == self.config.IP)
                else:
                    # Modo container: gerenciar serviços com IPs dos containers ativos
                    is_managed = any(service_address == ep[0] for ep in active_endpoints)
                
                # Se é gerenciado e não está ativo, é órfão
                if is_managed and (service_address, service_port) not in active_endpoints:
                    orphans.append((service_id, service_address, service_port))
            
            if orphans:
                log.info(f"Encontrados {len(orphans)} serviços órfãos")
                for service_id, addr, port in orphans:
                    log.info(f"  Órfão: {service_id} ({addr}:{port})")
                    self.consul.deregister_service(service_id)
            else:
                log.info("Nenhum serviço órfão encontrado")
        
        except Exception as e:
            log.error(f"Erro ao limpar serviços órfãos: {e}")
        
        log.info(f"═══ Resync completo: {registered_count} serviços ativos ═══")
    
    def handle_container_start(self, container_id):
        """Trata evento de container iniciando"""
        container = self.docker.get_container(container_id)
        if not container:
            return
        
        # Aguardar um pouco para garantir que o container está pronto
        time.sleep(1)
        
        services = self.extractor.extract_services_from_container(container)
        for svc in services:
            self.consul.register_service(*svc)
    
    def handle_container_stop(self, container_id):
        """Trata evento de container parando"""
        short_id = container_id[:12]
        
        try:
            consul_services = self.consul.get_services()
            removed_count = 0
            
            for service_id in consul_services.keys():
                if service_id.endswith(short_id):
                    if self.consul.deregister_service(service_id):
                        removed_count += 1
            
            if removed_count > 0:
                log.info(f"Limpeza: {removed_count} serviços removidos")
        
        except Exception as e:
            log.error(f"Erro ao limpar serviços do container {short_id}: {e}")
    
    def handle_event(self, event):
        """Processa evento Docker"""
        if event.get("Type") != "container":
            return
        
        action = event.get("Action")
        container_id = event.get("Actor", {}).get("ID")
        
        if not container_id:
            return
        
        # Filtrar apenas eventos relevantes (ignora exec_*, health_status, etc)
        if action not in ("start", "update", "stop", "die", "destroy"):
            return
        
        log.info(f"→ Evento: {action} [{container_id[:12]}]")
        
        if action in ("start", "update"):
            self.handle_container_start(container_id)
        elif action in ("stop", "die", "destroy"):
            self.handle_container_stop(container_id)
    
    def event_listener(self):
        """Thread que monitora eventos Docker em tempo real"""
        log.info("Listener de eventos Docker iniciado")
        
        while True:
            try:
                for event in self.docker.listen_events():
                    self.handle_event(event)
            except Exception as e:
                log.error(f"Erro no listener de eventos: {e}")
                time.sleep(5)
    
    def resync_loop(self):
        """Thread que executa resync periódico"""
        log.info(f"Loop de resync iniciado (intervalo: {self.config.RESYNC_INTERVAL}s)")
        
        while True:
            time.sleep(self.config.RESYNC_INTERVAL)
            self.sync_all()
    
    def run(self):
        """Inicia o registrador de serviços"""
        # Sincronização inicial
        self.sync_all()
        
        # Iniciar threads de monitoramento
        threading.Thread(target=self.event_listener, daemon=True).start()
        threading.Thread(target=self.resync_loop, daemon=True).start()
        
        # Manter o programa rodando
        log.info("✓ Registrador ativo e monitorando eventos")
        
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            log.info("Encerrando aplicação")


# ============================================
# MAIN
# ============================================

if __name__ == "__main__":
    try:
        config = Config()
        config.print_config()
        
        registry = ServiceRegistry(config)
        registry.run()
    
    except KeyboardInterrupt:
        log.info("Aplicação encerrada pelo usuário")
        sys.exit(0)
    except Exception as e:
        log.error(f"Erro fatal: {e}", exc_info=True)
        sys.exit(1)