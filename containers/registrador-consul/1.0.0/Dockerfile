FROM python:3.14-alpine

LABEL maintainer="Igor Ferreira"
LABEL description="Registrador Docker > Consul"
LABEL version="1.0.0"

WORKDIR /app

# Instalar dependências
RUN pip install --no-cache-dir docker requests

# Copiar código
COPY main.py .

# Variáveis de ambiente padrão
ENV IP="" \
    MODE="container" \
    CONSUL_URL="http://consul:8500" \
    RESYNC_INTERVAL="120" \
    DOCKER_SOCKET="" \
    DEREGISTER_RETRIES="3" \
    DEREGISTER_RETRY_DELAY="2"

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider ${CONSUL_URL}/v1/status/leader || exit 1

# Executar
ENTRYPOINT ["python", "-u", "main.py"]