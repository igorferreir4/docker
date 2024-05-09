FROM alpine:latest

# Instala o FFMPEG
RUN apk add --no-cache ffmpeg

# Copia os scripts de entrada
COPY watch_folder.sh /scripts/watch_folder.sh

# Define o diretório de trabalho
WORKDIR /scripts

# Define o comando padrão a ser executado quando o container iniciar
CMD ["sh", "watch_folder.sh"]