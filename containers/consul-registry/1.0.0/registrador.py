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

PUBLIC_IP = os.getenv("PUBLIC_IP")  # Se None, usa IP do container
CONSUL = os.getenv("CONSUL_URL", "http://127.0.0.1:8500")
RESYNC_INTERVAL = int(os.getenv("RESYNC_INTERVAL", "120"))
USE_CONTAINER_PORT = os.getenv("USE_CONTAINER_PORT", "false").lower() == "true"
DEREGISTER_RETRIES = int(os.getenv("DEREGISTER_RETRIES", "3"))
DEREGISTER_RETRY_DELAY = int(os.getenv("DEREGISTER_RETRY_DELAY", "2"))

client = docker.from_env()

def get_container_ip(container):
    """Obtém o IP do container na rede bridge padrão"""
    try:
        networks = container.attrs["NetworkSettings"]["Networks"]
        # Tenta pegar o IP da primeira rede disponível
        for network_name, network_info in networks.items():
            ip = network_info.get("IPAddress")
            if ip:
                return ip
    except Exception as e:
        logging.warning(f"Erro ao obter IP do container {container.short_id}: {e}")
    return None

def register(service_id, name, address, port, tags):
    try:
        requests.put(
            f"{CONSUL}/v1/agent/service/register",
            json={
                "ID": service_id,
                "Name": name,
                "Address": address,
                "Port": port,
                "Tags": tags,
            },
            timeout=3,
        )
        logging.info(f"Registrado: {name} ({address}:{port}) [{service_id}]")
    except Exception as e:
        logging.error(f"Erro ao registrar {service_id}: {e}")

def deregister(service_id):
    for attempt in range(DEREGISTER_RETRIES):
        try:
            requests.put(
                f"{CONSUL}/v1/agent/service/deregister/{service_id}",
                timeout=3,
            )
            logging.info(f"Removido: {service_id}")
            return True
        except Exception as e:
            if attempt < DEREGISTER_RETRIES - 1:
                logging.warning(
                    f"Erro ao remover {service_id} (tentativa {attempt + 1}/{DEREGISTER_RETRIES}): {e}"
                )
                time.sleep(DEREGISTER_RETRY_DELAY)
            else:
                logging.error(
                    f"Falha ao remover {service_id} após {DEREGISTER_RETRIES} tentativas: {e}"
                )
    return False

def services_from_container(c):
    labels = c.labels

    if labels.get("traefik.enable") != "true":
        return []

    services = {
        k.split(".")[3]: int(v)
        for k, v in labels.items()
        if k.startswith("traefik.http.services.")
        and k.endswith(".loadbalancer.server.port")
    }

    ports = c.attrs["NetworkSettings"]["Ports"]
    result = []

    # Define o endereço a ser usado
    if PUBLIC_IP:
        address = PUBLIC_IP
    else:
        address = get_container_ip(c)
        if not address:
            logging.warning(f"{c.name}: não foi possível obter IP do container")
            return []

    for service_name, container_port in services.items():
        key = f"{container_port}/tcp"
        
        if USE_CONTAINER_PORT:
            # Usa a porta do container diretamente
            port_to_register = container_port
            logging.debug(f"{c.name}: usando porta do container {container_port}")
        else:
            # Usa a porta publicada no host
            if key not in ports or not ports[key]:
                logging.warning(
                    f"{c.name}: porta {container_port} não publicada no host"
                )
                continue
            
            port_to_register = int(ports[key][0]["HostPort"])
            logging.debug(f"{c.name}: usando porta do host {port_to_register}")

        tags = [
            f"{k}={v}"
            for k, v in labels.items()
            if k.startswith("traefik.")
        ]

        service_id = f"{service_name}-{c.short_id}"
        result.append((service_id, service_name, address, port_to_register, tags))

    return result

def get_all_active_endpoints():
    """Retorna um set de (address, port) de todos os containers ativos"""
    endpoints = set()
    for c in client.containers.list():
        for svc in services_from_container(c):
            # svc = (service_id, service_name, address, port, tags)
            endpoints.add((svc[2], svc[3]))  # (address, port)
    return endpoints

def sync_all():
    logging.info("Resync completo iniciado")
    registered = set()

    # Registra todos os serviços dos containers ativos
    for c in client.containers.list():
        for svc in services_from_container(c):
            register(*svc)
            registered.add(svc[0])

    # Obtém todos os endpoints ativos (address:port)
    active_endpoints = get_all_active_endpoints()
    
    # Remove serviços órfãos do Consul
    try:
        services = requests.get(
            f"{CONSUL}/v1/agent/services", timeout=3
        ).json()
        
        orphans = []
        for sid, svc in services.items():
            address = svc.get("Address")
            port = svc.get("Port")
            
            # Se PUBLIC_IP está definido, gerencia TODOS os serviços com esse IP
            if PUBLIC_IP and address == PUBLIC_IP:
                # Se o endpoint não está ativo, é órfão
                if (address, port) not in active_endpoints:
                    orphans.append((sid, address, port))
            
            # Se PUBLIC_IP não está definido, gerencia serviços com IPs de containers
            elif not PUBLIC_IP:
                # Verifica se é um IP de container e se não está ativo
                for endpoint_addr, endpoint_port in active_endpoints:
                    if address == endpoint_addr:
                        if (address, port) not in active_endpoints:
                            orphans.append((sid, address, port))
                        break
        
        if orphans:
            logging.info(f"Encontrados {len(orphans)} serviços órfãos para remover")
            for sid, addr, prt in orphans:
                logging.info(f"  Órfão: {sid} ({addr}:{prt})")
                deregister(sid)
        else:
            logging.info("Nenhum serviço órfão encontrado")
            
    except Exception as e:
        logging.error(f"Erro ao sincronizar Consul: {e}")

    logging.info(f"Resync completo finalizado ({len(registered)} serviços ativos)")

def handle_event(container_id, action):
    logging.info(f"Evento Docker: {action} {container_id[:12]}")

    try:
        c = client.containers.get(container_id)
    except docker.errors.NotFound:
        # Container não existe mais, tenta limpar pelo short_id
        if action in ("stop", "die", "destroy"):
            short_id = container_id[:12]
            try:
                services = requests.get(
                    f"{CONSUL}/v1/agent/services", timeout=3
                ).json()
                removed = []
                for sid, svc in services.items():
                    if sid.endswith(short_id):
                        if deregister(sid):
                            removed.append(sid)
                if removed:
                    logging.info(f"Removidos {len(removed)} serviços do container {short_id}")
            except Exception as e:
                logging.error(f"Erro ao limpar serviços do container {short_id}: {e}")
        return

    if action in ("start", "update"):
        time.sleep(1)  # evita race condition
        for svc in services_from_container(c):
            register(*svc)

    elif action in ("stop", "die", "destroy"):
        try:
            services = requests.get(
                f"{CONSUL}/v1/agent/services", timeout=3
            ).json()
            removed = []
            for sid, svc in services.items():
                if sid.endswith(c.short_id):
                    if deregister(sid):
                        removed.append(sid)
            if removed:
                logging.info(f"Removidos {len(removed)} serviços do container {c.short_id}")
        except Exception as e:
            logging.error(f"Erro ao limpar serviços: {e}")

def event_listener():
    while True:
        try:
            for event in client.events(decode=True):
                if event.get("Type") != "container":
                    continue

                action = event.get("Action")
                container_id = event.get("Actor", {}).get("ID")

                if not container_id:
                    logging.warning(f"Evento sem ID: {event}")
                    continue

                if action in (
                    "start",
                    "stop",
                    "die",
                    "destroy",
                    "update",
                ):
                    handle_event(container_id, action)

        except Exception as e:
            logging.error(f"Erro no stream de events: {e}")
            time.sleep(5)

def resync_loop():
    while True:
        time.sleep(RESYNC_INTERVAL)
        sync_all()

if __name__ == "__main__":
    logging.info("Iniciando registrador Docker → Consul")
    logging.info(f"Modo de endereço: {'IP FIXO (' + PUBLIC_IP + ')' if PUBLIC_IP else 'IP DO CONTAINER'}")
    logging.info(f"Modo de porta: {'CONTAINER' if USE_CONTAINER_PORT else 'HOST'}")
    logging.info(f"Intervalo de resync: {RESYNC_INTERVAL}s")
    logging.info(f"Tentativas de deregister: {DEREGISTER_RETRIES}")
    sync_all()

    threading.Thread(target=event_listener, daemon=True).start()
    threading.Thread(target=resync_loop, daemon=True).start()

    while True:
        time.sleep(3600)