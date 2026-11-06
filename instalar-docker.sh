#!/bin/sh

set -eu
if (set -o pipefail) 2>/dev/null; then
    set -o pipefail
fi

LOG_FILE="log-install.txt"
TARGET_USER="${SUDO_USER:-${USER:-}}"

restore_cursor() {
    printf '\033[?25h'
}

trap restore_cursor EXIT INT TERM

run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "ERRO: execute como root ou instale o sudo." >&2
        return 1
    fi
}

spinner() {
    spinner_pid=$1
    spinner_msg=$2
    spinner_chars='| / - \'

    printf '\033[?25l'
    while kill -0 "$spinner_pid" 2>/dev/null; do
        for spinner_char in $spinner_chars; do
            kill -0 "$spinner_pid" 2>/dev/null || break
            printf '\r%s [%s] ' "$spinner_msg" "$spinner_char"
            sleep 0.1
        done
    done
}

run_step() {
    step_msg=$1
    shift

    "$@" >>"$LOG_FILE" 2>&1 &
    step_pid=$!
    spinner "$step_pid" "$step_msg" &
    step_spinner_pid=$!

    if wait "$step_pid"; then
        step_status=0
    else
        step_status=$?
    fi

    wait "$step_spinner_pid" 2>/dev/null || true
    restore_cursor

    if [ "$step_status" -eq 0 ]; then
        printf '\r%s [OK]\033[K\n' "$step_msg"
        return 0
    fi

    printf '\r%s [FALHOU]\033[K\n' "$step_msg" >&2
    echo "Consulte o log: $(pwd)/$LOG_FILE" >&2
    return "$step_status"
}

detect_system() {
    if [ ! -r /etc/os-release ]; then
        echo "ERRO: não foi possível identificar o sistema operacional." >&2
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    SYSTEM_ID=${ID:-}

    case "$SYSTEM_ID" in
        ubuntu|alpine) ;;
        *)
            echo "ERRO: sistema não suportado: ${SYSTEM_ID:-desconhecido}." >&2
            return 1
            ;;
    esac
}

enable_alpine_community() {
    if grep -Eq '^[[:space:]]*[^#].*/community[[:space:]]*$' /etc/apk/repositories; then
        return 0
    fi

    if grep -Eq '^[[:space:]]*#[[:space:]]*[^#].*/community[[:space:]]*$' /etc/apk/repositories; then
        run_root sed -i '/\/community[[:space:]]*$/s/^[[:space:]]*#[[:space:]]*//' /etc/apk/repositories
        return 0
    fi

    alpine_main_repo=$(grep -E '^[[:space:]]*[^#].*/main[[:space:]]*$' /etc/apk/repositories | head -n 1 || true)
    if [ -z "$alpine_main_repo" ]; then
        echo "ERRO: repositório main do Alpine não encontrado." >&2
        return 1
    fi

    alpine_community_repo=$(printf '%s\n' "$alpine_main_repo" | sed 's|/main[[:space:]]*$|/community|')
    printf '%s\n' "$alpine_community_repo" | run_root tee -a /etc/apk/repositories >/dev/null
}

update_system() {
    case "$SYSTEM_ID" in
        ubuntu)
            run_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
            run_root env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
            ;;
        alpine)
            enable_alpine_community
            run_root apk update
            run_root apk upgrade
            ;;
    esac
}

install_dependencies() {
    case "$SYSTEM_ID" in
        ubuntu)
            run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
                ca-certificates curl htop wget nano zip unzip iputils-ping \
                fuse3 login openssh-server tzdata
            if ! command -v newgrp >/dev/null 2>&1; then
                run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y util-linux-extra
            fi
            ;;
        alpine)
            run_root apk add --no-cache \
                ca-certificates curl htop wget nano zip unzip iputils \
                fuse3 openssh shadow-login tzdata
            ;;
    esac
}

configure_timezone() {
    if [ "$SYSTEM_ID" = "ubuntu" ] && command -v timedatectl >/dev/null 2>&1; then
        run_root timedatectl set-timezone America/Sao_Paulo
    else
        run_root ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
        printf '%s\n' 'America/Sao_Paulo' | run_root tee /etc/timezone >/dev/null
    fi
}

configure_sshd() {
    run_root install -d -m 0755 /etc/ssh/sshd_config.d /run/sshd

    run_root tee /etc/ssh/sshd_config.d/99-minhaconfig.conf >/dev/null <<'EOF'
PermitRootLogin prohibit-password
AllowTcpForwarding yes
TCPKeepAlive yes
Compression delayed
ClientAliveInterval 30
ClientAliveCountMax 3
UseDNS no
EOF

    if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
        run_root sed -i '1iInclude /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
    fi

    sshd_path=$(command -v sshd)
    run_root "$sshd_path" -t

    case "$SYSTEM_ID" in
        ubuntu)
            if run_root systemctl is-active --quiet ssh; then
                run_root systemctl reload ssh
            else
                run_root systemctl enable --now ssh
            fi
            ;;
        alpine)
            run_root rc-update add sshd default
            if run_root rc-service sshd status >/dev/null 2>&1; then
                run_root rc-service sshd reload
            else
                run_root rc-service sshd start
            fi
            ;;
    esac
}

configure_fuse() {
    if grep -Eq '^[[:space:]]*user_allow_other([[:space:]]|$)' /etc/fuse.conf; then
        return 0
    fi

    if grep -Eq '^[[:space:]]*#[[:space:]]*user_allow_other([[:space:]]|$)' /etc/fuse.conf; then
        run_root sed -i 's/^[[:space:]]*#[[:space:]]*user_allow_other/user_allow_other/' /etc/fuse.conf
    else
        printf '%s\n' 'user_allow_other' | run_root tee -a /etc/fuse.conf >/dev/null
    fi
}

remove_old_ubuntu_docker() {
    old_packages=""
    for package in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            old_packages="$old_packages $package"
        fi
    done

    if [ -n "$old_packages" ]; then
        # A expansão é intencional: contém somente nomes fixos de pacotes.
        # shellcheck disable=SC2086
        run_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y $old_packages
    fi
}

install_docker_ubuntu() {
    remove_old_ubuntu_docker
    run_root install -m 0755 -d /etc/apt/keyrings
    run_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    run_root chmod a+r /etc/apt/keyrings/docker.asc

    ubuntu_codename=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
    if [ -z "$ubuntu_codename" ]; then
        echo "ERRO: codinome da versão do Ubuntu não encontrado." >&2
        return 1
    fi
    ubuntu_architecture=$(dpkg --print-architecture)

    run_root tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $ubuntu_codename
Components: stable
Architectures: $ubuntu_architecture
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    run_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_alpine() {
    run_root apk add --no-cache docker docker-cli-compose
}

install_docker() {
    case "$SYSTEM_ID" in
        ubuntu) install_docker_ubuntu ;;
        alpine) install_docker_alpine ;;
    esac
}

enable_docker() {
    case "$SYSTEM_ID" in
        ubuntu)
            run_root systemctl enable --now docker.service containerd.service
            ;;
        alpine)
            run_root rc-update add docker default
            run_root rc-service docker start
            ;;
    esac
}

configure_docker_user() {
    case "$TARGET_USER" in
        ""|root)
            echo "Nenhum usuário comum identificado; grupo docker não alterado."
            return 0
            ;;
    esac

    if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
        return 0
    fi

    case "$SYSTEM_ID" in
        ubuntu) run_root usermod -aG docker "$TARGET_USER" ;;
        alpine) run_root addgroup "$TARGET_USER" docker ;;
    esac
}

verify_docker() {
    run_root docker info >/dev/null
    docker compose version
    docker buildx version
}

: >"$LOG_FILE"
detect_system

echo "Iniciando instalação no sistema: $SYSTEM_ID"

run_step "Atualizando o sistema" update_system
run_step "Instalando dependências" install_dependencies
run_step "Configurando timezone America/Sao_Paulo" configure_timezone
echo "Data atual: $(date '+%d/%m/%Y - %H:%M:%S')"
run_step "Configurando SSHD" configure_sshd
run_step "Configurando FUSE para Rclone" configure_fuse
run_step "Instalando Docker e componentes" install_docker
run_step "Habilitando e iniciando Docker" enable_docker
run_step "Configurando usuário no grupo docker" configure_docker_user
run_step "Validando Docker, Compose e Buildx" verify_docker

echo ""
echo "Instalação do Docker finalizada com sucesso."
echo "Log salvo em: $(pwd)/$LOG_FILE"
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    echo "Execute 'newgrp docker' ou reinicie a sessão para usar Docker sem sudo."
fi
