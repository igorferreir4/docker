import os
import time
import threading
import logging
import docker
import requests

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

# ============================================
# CONFIGURAÇÕES VIA ENVIRONMENT VARIABLES
# ============================================

# IP para registrar serviços (se vazio, usa IP do container)
IP = os.getenv("IP", "")

# Se true: usa porta interna do container | false: usa porta exposta no host
USE_CONTAINER_PORT = os.getenv("USE_CONTAINER_PORT", "false").lower() == "true"

# URL do Consul
CONSUL_URL = os.getenv("CONSUL_URL", "http://consul:8500")

# Intervalo de resync em segundos
RESYNC_INTERVAL = int(os.getenv("RESYNC_INTERVAL", "120").strip('"'))

# Docker socket: se vazio usa /var/run/docker.sock, senão usa TCP
DOCKER_SOCKET = os.getenv("DOCKER_SOCKET", "").strip('"')

# Se true: registra label de porta como tag | false: ignora label de porta
USE_LABEL_PORT = os.getenv("USE_LABEL_PORT", "true").strip('"').lower() == "true"

# Configurações de retry
DEREGISTER_RETRIES = int(os.getenv("DEREGISTER_RETRIES", "3").strip('"'))
DEREGISTER_RETRY_DELAY = int(os.getenv("DEREGISTER_RETRY_DELAY", "2").strip('"'))

# ============================================
# INICIALIZAR CLIENTE DOCKER
# ============================================

if DOCKER_SOCKET:
    # Conectar via TCP (ex: tcp://192.168.1.100:2375)
    client = docker.DockerClient(base_url=DOCKER_SOCKET)
    logging.info(f"Conectando ao Docker via TCP: {DOCKER_SOCKET}")
else:
    # Conectar via socket local (mais seguro)
    client = docker.from_env()
    logging.info("Conectando ao Docker via socket local")

# ============================================
# FUNÇÕES AUXILIARES
# ============================================

def get_container_ip(container):
    """Obtém o IP do container na primeira rede disponível"""
    try:
        networks = container.attrs["NetworkSettings"]["Networks"]
        for network_name, network_info in networks.items():
            ip = network_info.get("IPAddress")
            if ip:
                return ip
    except Exception as e:
        logging.warning(f"Erro ao obter IP do container {container.short_id}: {e}")
    return None

def register(service_id, name, address, port, tags):
    """Registra um serviço no Consul"""
    try:
        payload = {
            "ID": service_id,
            "Name": name,
            "Address": address,
            "Port": port,
            "Tags": tags,
        }
        requests.put(
            f"{CONSUL_URL}/v1/agent/service/register",
            json=payload,
            timeout=5,
        )
        logging.info(f"✓ Registrado: {name} ({address}:{port}) [{service_id}]")
        return True
    except Exception as e:
        logging.error(f"✗ Erro ao registrar {service_id}: {e}")
        return False

def deregister(service_id):
    """Remove um serviço do Consul com retry"""
    for attempt in range(DEREGISTER_RETRIES):
        try:
            requests.put(
                f"{CONSUL_URL}/v1/agent/service/deregister/{service_id}",
                timeout=5,
            )
            logging.info(f"✓ Removido: {service_id}")
            return True
        except Exception as e:
            if attempt < DEREGISTER_RETRIES - 1:
                logging.warning(
                    f"⚠ Tentativa {attempt + 1}/{DEREGISTER_RETRIES} falhou para {service_id}: {e}"
                )
                time.sleep(DEREGISTER_RETRY_DELAY)
            else:
                logging.error(
                    f"✗ Falha definitiva ao remover {service_id}: {e}"
                )
    return False

# ============================================
# EXTRAÇÃO DE SERVIÇOS DE CONTAINERS
# ============================================

def services_from_container(container):
    """
    Extrai serviços de um container baseado em labels do Traefik.
    Retorna lista de tuplas: (service_id, service_name, address, port, tags)
    """
    labels = container.labels

    # Container deve ter traefik.enable=true
    if labels.get("traefik.enable") != "true":
        return []

    # Encontrar todos os serviços definidos nas labels
    # Label: traefik.http.services.<SERVICE_NAME>.loadbalancer.server.port=80
    services = {}
    for key, value in labels.items():
        if (key.startswith("traefik.http.services.") and 
            key.endswith(".loadbalancer.server.port")):
            service_name = key.split(".")[3]
            services[service_name] = int(value)

    if not services:
        logging.debug(f"{container.name}: Sem serviços Traefik definidos")
        return []

    result = []
    ports = container.attrs["NetworkSettings"]["Ports"]

    # Determinar endereço a ser usado
    if IP:
        address = IP
    else:
        address = get_container_ip(container)
        if not address:
            logging.warning(f"{container.name}: Não foi possível obter IP")
            return []

    # Processar cada serviço encontrado
    for service_name, label_port in services.items():
        
        # Determinar porta a ser registrada
        if USE_CONTAINER_PORT:
            # Modo 1: Usar porta interna do container (da label)
            port_to_register = label_port
            logging.debug(f"{container.name}/{service_name}: Porta do container: {label_port}")
        else:
            # Modo 2: Usar porta exposta no host
            # Procura qualquer porta mapeada no host (ignora qual porta interna)
            port_to_register = None
            
            for port_key, port_bindings in ports.items():
                if port_bindings and len(port_bindings) > 0:
                    host_port = int(port_bindings[0]["HostPort"])
                    port_to_register = host_port
                    logging.debug(f"{container.name}/{service_name}: Porta do host: {host_port}")
                    break
            
            if not port_to_register:
                logging.warning(
                    f"{container.name}/{service_name}: Nenhuma porta exposta no host"
                )
                continue

        # Coletar tags do Traefik
        tags = []
        for key, value in labels.items():
            if key.startswith("traefik."):
                # Decidir se inclui ou não a label de porta
                if key.endswith(".loadbalancer.server.port"):
                    if USE_LABEL_PORT:
                        tags.append(f"{key}={value}")
                    else:
                        logging.debug(f"{container.name}: Ignorando label de porta: {key}")
                else:
                    tags.append(f"{key}={value}")

        # Criar ID único do serviço
        service_id = f"{service_name}-{container.short_id}"
        
        result.append((service_id, service_name, address, port_to_register, tags))

    return result

# ============================================
# SINCRONIZAÇÃO COM CONSUL
# ============================================

def get_all_active_endpoints():
    """
    Retorna um set de (address, port) de todos os serviços ativos.
    Usado para identificar serviços órfãos no Consul.
    """
    endpoints = set()
    try:
        for container in client.containers.list():
            for svc in services_from_container(container):
                # svc = (service_id, service_name, address, port, tags)
                endpoints.add((svc[2], svc[3]))  # (address, port)
    except Exception as e:
        logging.error(f"Erro ao coletar endpoints ativos: {e}")
    return endpoints

def sync_all():
    """
    Sincronização completa:
    1. Registra todos os serviços de containers ativos
    2. Remove serviços órfãos do Consul
    """
    logging.info("═══ Iniciando resync completo ═══")
    registered_ids = set()
    registered_count = 0

    # Fase 1: Registrar serviços ativos
    try:
        containers = client.containers.list()
        logging.info(f"Encontrados {len(containers)} containers ativos")
        
        for container in containers:
            services = services_from_container(container)
            for svc in services:
                if register(*svc):
                    registered_ids.add(svc[0])
                    registered_count += 1
    except Exception as e:
        logging.error(f"Erro ao registrar serviços: {e}")

    # Fase 2: Remover serviços órfãos
    try:
        active_endpoints = get_all_active_endpoints()
        consul_services = requests.get(
            f"{CONSUL_URL}/v1/agent/services",
            timeout=5
        ).json()
        
        orphans = []
        for service_id, service_info in consul_services.items():
            service_address = service_info.get("Address")
            service_port = service_info.get("Port")
            
            # Verificar se este serviço pertence a este registrador
            if IP:
                # Se IP fixo está definido, gerenciar apenas serviços com esse IP
                is_managed = (service_address == IP)
            else:
                # Se IP não está definido, gerenciar serviços com IPs de containers ativos
                is_managed = any(service_address == ep[0] for ep in active_endpoints)
            
            # Se é gerenciado por nós e não está ativo, é órfão
            if is_managed and (service_address, service_port) not in active_endpoints:
                orphans.append((service_id, service_address, service_port))
        
        if orphans:
            logging.info(f"Encontrados {len(orphans)} serviços órfãos")
            for service_id, addr, port in orphans:
                logging.info(f"  Órfão: {service_id} ({addr}:{port})")
                deregister(service_id)
        else:
            logging.info("Nenhum serviço órfão encontrado")
            
    except Exception as e:
        logging.error(f"Erro ao limpar serviços órfãos: {e}")

    logging.info(f"═══ Resync completo: {registered_count} serviços ativos ═══")

# ============================================
# MONITORAMENTO DE EVENTOS DOCKER
# ============================================

def handle_event(container_id, action):
    """Trata eventos específicos de containers"""
    logging.info(f"→ Evento: {action} [{container_id[:12]}]")

    try:
        container = client.containers.get(container_id)
    except docker.errors.NotFound:
        # Container não existe mais
        if action in ("stop", "die", "destroy"):
            # Tentar limpar pelo short_id
            short_id = container_id[:12]
            try:
                consul_services = requests.get(
                    f"{CONSUL_URL}/v1/agent/services",
                    timeout=5
                ).json()
                
                removed = []
                for service_id in consul_services.keys():
                    if service_id.endswith(short_id):
                        if deregister(service_id):
                            removed.append(service_id)
                
                if removed:
                    logging.info(f"Limpeza: {len(removed)} serviços removidos")
            except Exception as e:
                logging.error(f"Erro ao limpar serviços do container {short_id}: {e}")
        return

    # Container existe, processar evento
    if action in ("start", "update"):
        # Aguardar um pouco para evitar race conditions
        time.sleep(1)
        services = services_from_container(container)
        for svc in services:
            register(*svc)
    
    elif action in ("stop", "die", "destroy"):
        # Remover serviços deste container
        try:
            consul_services = requests.get(
                f"{CONSUL_URL}/v1/agent/services",
                timeout=5
            ).json()
            
            removed = []
            for service_id in consul_services.keys():
                if service_id.endswith(container.short_id):
                    if deregister(service_id):
                        removed.append(service_id)
            
            if removed:
                logging.info(f"Limpeza: {len(removed)} serviços removidos")
        except Exception as e:
            logging.error(f"Erro ao limpar serviços: {e}")

def event_listener():
    """Thread que monitora eventos Docker em tempo real"""
    logging.info("Listener de eventos Docker iniciado")
    
    while True:
        try:
            for event in client.events(decode=True):
                if event.get("Type") != "container":
                    continue

                action = event.get("Action")
                container_id = event.get("Actor", {}).get("ID")

                if not container_id:
                    continue

                if action in ("start", "stop", "die", "destroy", "update"):
                    handle_event(container_id, action)

        except Exception as e:
            logging.error(f"Erro no listener de eventos: {e}")
            time.sleep(5)

def resync_loop():
    """Thread que executa resync periódico"""
    logging.info(f"Loop de resync iniciado (intervalo: {RESYNC_INTERVAL}s)")
    
    while True:
        time.sleep(RESYNC_INTERVAL)
        sync_all()

# ============================================
# MAIN
# ============================================

if __name__ == "__main__":
    logging.info("╔══════════════════════════════════════════════════════╗")
    logging.info("║   Docker → Consul Service Registry                  ║")
    logging.info("╚══════════════════════════════════════════════════════╝")
    logging.info("")
    logging.info("Configuração:")
    logging.info(f"  IP: {IP if IP else 'IP do container (dinâmico)'}")
    logging.info(f"  Porta: {'Container' if USE_CONTAINER_PORT else 'Host'}")
    logging.info(f"  Consul: {CONSUL_URL}")
    logging.info(f"  Resync: {RESYNC_INTERVAL}s")
    logging.info(f"  Docker: {'TCP ' + DOCKER_SOCKET if DOCKER_SOCKET else 'Socket local'}")
    logging.info(f"  Label de porta: {'Incluída' if USE_LABEL_PORT else 'Ignorada'}")
    logging.info("")

    # Sincronização inicial
    sync_all()

    # Iniciar threads de monitoramento
    threading.Thread(target=event_listener, daemon=True).start()
    threading.Thread(target=resync_loop, daemon=True).start()

    # Manter o programa rodando
    logging.info("✓ Registrador ativo e monitorando eventos")
    
    while True:
        time.sleep(3600)