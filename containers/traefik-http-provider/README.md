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

### Docker Compose

```yaml
services:
  registrador:
    image: igorferreir4/registrador-consul:latest
    container_name: registrador
    environment:
    #  - IP=192.168.0.10
    #  - MODE=host
     - MODE=container
     - CONSUL_URL=http://192.168.0.50:8500
     - RESYNC_INTERVAL="60"
    # - DOCKER_SOCKET="tcp://docker-socket-proxy:2375"
     - DEREGISTER_RETRIES="3"
     - DEREGISTER_RETRY_DELAY="2"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    deploy:
      resources:
        limits:
          memory: 50M
    restart: unless-stopped

  # Exemplo de aplicação
  whoami:
    image: traefik/whoami
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.example.com`)"
      - "traefik.http.services.whoami.loadbalancer.server.port=80"
    ports:
      - "8080:80"
```