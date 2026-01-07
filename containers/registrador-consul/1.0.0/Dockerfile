FROM python:3.14-slim

LABEL maintainer="Igor Ferreira"
LABEL description="Docker to Consul Service Registry"
LABEL version="1.0.0"

WORKDIR /app

# Instalar dependências
RUN pip install --no-cache-dir docker requests

# Copiar código
COPY registrador-consul.py .

# Variáveis de ambiente padrão
ENV IP="" \
    USE_CONTAINER_PORT="false" \
    USE_LABEL_PORT="true" \
    CONSUL_URL="http://consul:8500" \
    RESYNC_INTERVAL="120" \
    DOCKER_SOCKET="" \
    DEREGISTER_RETRIES="3" \
    DEREGISTER_RETRY_DELAY="2"

# Executar
CMD ["python", "-u", "registrador-consul.py"]