# Novo
FROM python:3.14-slim

WORKDIR /app

RUN pip install --no-cache-dir docker requests

COPY registrador.py .

CMD ["python", "registrador.py"]