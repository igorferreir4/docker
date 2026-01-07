# Docker to Consul Service Registry

Registrador automático de containers Docker no Consul para uso com Traefik. Monitora containers com labels do Traefik e registra/remove serviços no Consul automaticamente.

## Funcionalidades

- ✅ Registro automático de containers Docker no Consul
- ✅ Leitura de labels do Traefik para configuração de serviços
- ✅ Remoção automática de serviços órfãos
- ✅ Suporte para IP fixo ou IP dinâmico do container
- ✅ Suporte para porta do container ou porta do host
- ✅ Resync periódico para garantir consistência
- ✅ Retry automático em falhas de comunicação

## Variáveis de Ambiente

| Variável | Obrigatório | Padrão | Descrição |
|----------|-------------|--------|-----------|
| `PUBLIC_IP` | Não* | - | IP público usado para registrar serviços. Se não definido, usa o IP do container |
| `CONSUL_URL` | Não | `http://127.0.0.1:8500` | URL do Consul |
| `RESYNC_INTERVAL` | Não | `120` | Intervalo em segundos para resync completo |
| `USE_CONTAINER_PORT` | Não | `false` | Se `true`, usa porta do container. Se `false`, usa porta publicada no host |
| `DEREGISTER_RETRIES` | Não | `3` | Número de tentativas ao remover um serviço |
| `DEREGISTER_RETRY_DELAY` | Não | `2` | Delay em segundos entre tentativas de remoção |

\* `PUBLIC_IP` é obrigatório quando `USE_CONTAINER_PORT=false`

## Como usar

### Requisitos nos containers

Os containers devem ter as labels do Traefik configuradas:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.example.com`)"
  - "traefik.http.services.myapp.loadbalancer.server.port=80"
```

A label `traefik.http.services.<nome>.loadbalancer.server.port` deve existir e ser igual a porta do container.

### Docker Compose - Cenário 1: IP fixo + Porta do host

Ideal para quando o Traefik acessa os serviços via IP público da VM.

```yaml
version: '3.8'

services:
  consul-registry:
    image: igorferreir4/consul-registry:latest
    container_name: consul-registry
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - PUBLIC_IP=192.168.1.100
      - CONSUL_URL=http://consul:8500
      - USE_CONTAINER_PORT=false
      - RESYNC_INTERVAL=120
    networks:
      - traefik

  # Exemplo de aplicação
  whoami:
    image: traefik/whoami
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.example.com`)"
      - "traefik.http.services.whoami.loadbalancer.server.port=80"
    ports:
      - "8080:80"
    networks:
      - traefik

networks:
  traefik:
    external: true
```

### Docker Compose - Cenário 2: IP do container + Porta do container

Ideal para quando o Traefik está na mesma rede Docker e acessa os containers diretamente.

```yaml
version: '3.8'

services:
  consul-registry:
    image: igorferreir4/consul-registry:latest
    container_name: consul-registry
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - CONSUL_URL=http://consul:8500
      - USE_CONTAINER_PORT=true
      - RESYNC_INTERVAL=120
    networks:
      - traefik

  # Exemplo de aplicação (sem necessidade de expor portas)
  whoami:
    image: traefik/whoami
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.example.com`)"
      - "traefik.http.services.whoami.loadbalancer.server.port=80"
    networks:
      - traefik

networks:
  traefik:
    external: true
```

### Múltiplas VMs

Para usar em múltiplas VMs registrando no mesmo Consul:

```yaml
# VM1 - 192.168.1.100
services:
  consul-registry:
    image: seu-usuario/docker-consul-registry:latest
    environment:
      - PUBLIC_IP=192.168.1.100
      - CONSUL_URL=http://consul.example.com:8500
      - USE_CONTAINER_PORT=false
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

# VM2 - 192.168.1.200
services:
  consul-registry:
    image: seu-usuario/docker-consul-registry:latest
    environment:
      - PUBLIC_IP=192.168.1.200
      - CONSUL_URL=http://consul.example.com:8500
      - USE_CONTAINER_PORT=false
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

Cada registrador gerencia apenas os serviços do seu próprio `PUBLIC_IP`, evitando conflitos.

## Como funciona

1. **Startup**: Faz um sync completo, registrando todos os containers ativos e removendo órfãos
2. **Eventos Docker**: Monitora eventos de start/stop/die/destroy e atualiza o Consul em tempo real
3. **Resync periódico**: A cada `RESYNC_INTERVAL` segundos, valida e limpa serviços órfãos

### Detecção de serviços órfãos

Um serviço é considerado órfão quando:
- Está registrado no Consul com o `PUBLIC_IP` desta instância
- Não existe mais nenhum container Docker ativo com aquele endpoint (IP:porta)

## Logs

O registrador fornece logs detalhados de suas operações:

```
2025-01-04 10:00:00 [INFO] Iniciando registrador Docker → Consul
2025-01-04 10:00:00 [INFO] Modo de endereço: IP FIXO (192.168.1.100)
2025-01-04 10:00:00 [INFO] Modo de porta: HOST
2025-01-04 10:00:00 [INFO] Intervalo de resync: 120s
2025-01-04 10:00:00 [INFO] Resync completo iniciado
2025-01-04 10:00:01 [INFO] Registrado: myapp (192.168.1.100:8080) [myapp-a1b2c3d4]
2025-01-04 10:00:01 [INFO] Encontrados 2 serviços órfãos para remover
2025-01-04 10:00:01 [INFO]   Órfão: oldapp-x9y8z7w6 (192.168.1.100:9090)
2025-01-04 10:00:01 [INFO] Removido: oldapp-x9y8z7w6
2025-01-04 10:00:01 [INFO] Resync completo finalizado (3 serviços ativos)
```
## Troubleshooting

### Serviços não estão sendo registrados

- Verifique se o container tem a label `traefik.enable=true`
- Verifique se existe a label `traefik.http.services.<nome>.loadbalancer.server.port`
- Verifique os logs do registrador para erros

### Serviços órfãos não são removidos

- Aguarde o próximo resync (padrão 120s)
- Verifique se o `PUBLIC_IP` está correto
- Para forçar um resync, reinicie o registrador

### Múltiplos registradores conflitando

- Certifique-se de que cada registrador tem um `PUBLIC_IP` único
- Não use o mesmo `PUBLIC_IP` em mais de uma VM
- Não use mais de 1 registrador com acesso ao mesmo docker socket