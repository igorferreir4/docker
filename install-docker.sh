#!/bin/bash

LOG_FILE="log-install-docker.txt"

# Função spinner com mensagem
spinner() {
    local pid=$1
    local msg="$2"
    local delay=0.1
    local spinstr='| / - \\'
    local start_time=$(date +%s%3N)

    tput civis
    while kill -0 "$pid" 2>/dev/null; do
        for c in $spinstr; do
            printf "\r$msg [%c] " "$c"
            sleep $delay
        done
    done

    # garante que o spinner aparece por ao menos 1s
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    if [ "$duration" -lt 800 ]; then
        sleep 0.3
    fi

    tput cnorm
    printf "\r$msg [✔️  - OK] \n"
}

# Executa um comando em segundo plano com log e spinner
run_step() {
    local msg=$1
    shift
    printf "%s... " "$msg"
    ("$@" >>"$LOG_FILE" 2>&1) &
    spinner $! "$msg..."
}

echo "📦  - Iniciando instalação do Docker. Isso pode levar alguns minutos..."
sleep 1

run_step "🌐  - Configurando timezone America/Sao_Paulo" \
  bash -c 'sudo timedatectl set-timezone America/Sao_Paulo && echo "🕒  - Data atual: $(date +%d/%m/%Y\ -\ %H:%M:%S)"'

run_step "🔁  - Removendo pacotes antigos do Docker" \
  bash -c 'for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y "$pkg" || true; done'

run_step "🔄  - Atualizando índices dos pacotes" \
  sudo apt-get update -y

run_step "⬆️  - Atualizando pacotes instalados" \
  sudo apt-get upgrade -y

run_step "📦  - Instalando dependências e programas padrões" \
  sudo apt-get install -y ca-certificates curl htop wget nano zip unzip iputils-ping

run_step "📁  - Criando diretório para chave GPG" \
  sudo install -m 0755 -d /etc/apt/keyrings

run_step "⬇️  - Baixando chave GPG do Docker" \
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

run_step "🔐  - Ajustando permissões da chave" \
  sudo chmod a+r /etc/apt/keyrings/docker.asc

run_step "📂  - Adicionando repositório Docker" \
  bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null'

run_step "🔄  - Atualizando lista de pacotes" \
  sudo apt-get update -y

run_step "🐳  - Instalando Docker e componentes" \
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

run_step "🌐  - Habilitando IPv6 no Docker" \
  bash -c 'echo -e "{\n  \"experimental\": true,\n  \"ip6tables\": true\n}" | sudo tee /etc/docker/daemon.json > /dev/null'

run_step "🚀  - Iniciando serviço Docker" \
  sudo service docker start

run_step "👥  - Criando grupo docker (se necessário)" \
  bash -c 'getent group docker >/dev/null || sudo groupadd docker'

run_step "➕  - Adicionando usuário '$USER' ao grupo docker" \
  sudo usermod -aG docker "$USER"

run_step "🔁  - Habilitando Docker e containerd no boot" \
  bash -c 'sudo systemctl enable docker.service && sudo systemctl enable containerd.service'

echo ""
echo "✅  - Instalação do Docker finalizada com sucesso!"
echo "📄  - Log salvo em $(realpath "$LOG_FILE")"
echo "⚠️  - Execute 'newgrp docker' ou reinicie sua sessão para usar Docker sem sudo."
