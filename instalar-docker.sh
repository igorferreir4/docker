#!/bin/bash

LOG_FILE="log-install.txt"

# ===============================
# Função spinner com mensagem
# ===============================
spinner() {
    local pid=$1
    local msg="$2"
    local delay=0.1
    local spinstr='| / - \'
    local start_time=$(date +%s%3N)

    tput civis
    while kill -0 "$pid" 2>/dev/null; do
        for c in $spinstr; do
            printf "\r%s [%c] " "$msg" "$c"
            sleep $delay
        done
    done

    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    if [ "$duration" -lt 800 ]; then
        sleep 0.3
    fi

    tput cnorm
    printf "\r%s [✔ OK]\n" "$msg"
}

# ===============================
# Executa passo com spinner + log
# ===============================
run_step() {
    local msg="$1"
    shift
    printf "%s... " "$msg"
    ("$@" >>"$LOG_FILE" 2>&1) &
    spinner $! "$msg"
}

echo "📦  - Iniciando instalação do Docker..."
sleep 1

# ===============================
# Timezone
# ===============================
run_step "🌐  - Configurando timezone America/Sao_Paulo" \
  bash -c 'sudo timedatectl set-timezone America/Sao_Paulo && echo "🕒  - Data atual: $(date +%d/%m/%Y\ -\ %H:%M:%S)"'

# ===============================
# Remoção de versões antigas
# ===============================
run_step "🧹  - Removendo pacotes antigos do Docker" \
  bash -c 'sudo apt remove -y $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null | cut -f1) || true'

# ===============================
# Atualização do sistema
# ===============================
run_step "🔄  - Atualizando índices dos pacotes" \
  sudo apt update -y

run_step "⬆  - Atualizando pacotes instalados" \
  sudo apt upgrade -y

# ===============================
# Dependências básicas
# ===============================
run_step "📦  - Instalando dependências" \
  sudo apt install -y ca-certificates curl htop wget nano zip unzip iputils-ping

# ===============================
# Chave GPG do Docker
# ===============================
run_step "📁  - Criando diretório de keyrings" \
  sudo install -m 0755 -d /etc/apt/keyrings

run_step "🔑  - Baixando chave GPG do Docker" \
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

run_step "🔐  - Ajustando permissões da chave" \
  sudo chmod a+r /etc/apt/keyrings/docker.asc

# ===============================
# Repositório Docker (novo padrão .sources)
# ===============================
run_step "📂  - Adicionando repositório oficial do Docker" \
  bash -c 'sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF'

# ===============================
# Instalação do Docker
# ===============================
run_step "🔄  - Atualizando lista de pacotes (Docker)" \
  sudo apt update -y

run_step "🐳  - Instalando Docker e componentes" \
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ===============================
# Serviço Docker
# ===============================
run_step "🚀  - Iniciando serviço Docker" \
  sudo systemctl start docker

run_step "🔁  - Habilitando Docker e containerd no boot" \
  bash -c 'sudo systemctl enable docker.service && sudo systemctl enable containerd.service'

# ===============================
# Permissões do usuário
# ===============================
run_step "👥  - Criando grupo docker (se necessário)" \
  bash -c 'getent group docker >/dev/null || sudo groupadd docker'

run_step "➕  - Adicionando usuário ao grupo docker" \
  sudo usermod -aG docker "$USER"

# ===============================
# Finalização
# ===============================
echo ""
echo "✅  - Instalação do Docker finalizada com sucesso!"
echo "📄  - Log salvo em: $(realpath "$LOG_FILE")"
echo "⚠️  - Execute 'newgrp docker' ou reinicie a sessão para usar Docker sem sudo."
