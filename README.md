# Docker Containers Monorepo 🐳

Repositório centralizado de imagens Docker customizadas multi-arquitetura (amd64 + arm64) com CI/CD automatizado via CircleCI.

[![CircleCI](https://img.shields.io/circleci/build/github/igorferreir4/docker)](https://circleci.com/gh/igorferreir4/docker)
[![Docker Hub](https://img.shields.io/badge/docker-hub-blue)](https://hub.docker.com/u/igorferreir4)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 📦 Containers Disponíveis

| Container | Versão Atual | Status | Docker Hub | Descrição |
|-----------|--------------|--------|------------|-----------|
| [**Caddy**](containers/caddy/) | 2.7.6 | ✅ Stable | [🐳](https://hub.docker.com/r/igorferreir4/caddy) | Proxy reverso com plugins customizados |
| [**PHP-FPM**](containers/php-fpm/) | 8.3.7 | ✅ Stable | [🐳](https://hub.docker.com/r/igorferreir4/php-fpm) | PHP-FPM Alpine com extensões |
| [**TS3AudioBot**](containers/ts3audiobot/) | 0.12.2 / 0.13.0-alpha41 | ✅ Stable / ⚠️ Alpha | [🐳](https://hub.docker.com/r/igorferreir4/ts3audiobot) | Bot de áudio para TeamSpeak 3 |
| [**Focalboard**](containers/focalboard/) | 7.11.4 | ✅ Stable | [🐳](https://hub.docker.com/r/igorferreir4/focalboard) | Mattermost Focalboard com suporte ARM64 |
| [**Registrador Consul**](containers/registrador-consul/) | 1.0.0 | ✅ Stable | [🐳](https://hub.docker.com/r/igorferreir4/registrador-consul) | Registra containers Docker automaticamente no Consul |
| [**Traefik HTTP Provider**](containers/traefik-http-provider/) | 1.0.0 | ✅ Stable | [🐳](https://hub.docker.com/r/igorferreir4/traefik-http-provider) | HTTP Provider para Traefik (distroless + alpine) |

---

## 🚀 Quick Start

### Usar uma imagem

```bash
# Pull da imagem
docker pull igorferreir4/<container>:<version>

# Executar
docker run -d igorferreir4/<container>:<version>
```

### Com Docker Compose

```yaml
version: '3.8'
services:
  app:
    image: igorferreir4/<container>:<version>
    ports:
      - "8080:8080"
    environment:
      - ENV_VAR=value
```

---

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────┐
│  GitHub Repository                               │
│  ├── containers/                                 │
│  │   ├── caddy/2.7.6/                           │
│  │   ├── php-fpm/8.3.7/                         │
│  │   └── ...                                     │
│  └── .circleci/                                  │
│      ├── config.yml (path filtering)            │
│      ├── mapping.conf                            │
│      └── containers/<app>/<version>.yml         │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  CircleCI (Build Pipeline)                       │
│  ├── Detecta mudanças (path filtering)          │
│  ├── Build cache (amd64 + arm64)                │
│  ├── Build multi-arch image                     │
│  ├── Security scan (Trivy)                      │
│  └── Push to Docker Hub                         │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  Docker Hub                                      │
│  └── igorferreir4/<container>:<tags>           │
│      └── Manifests: linux/amd64, linux/arm64   │
└─────────────────────────────────────────────────┘
```

---

## 🎯 Features

### ✨ Multi-Arquitetura
- ✅ AMD64 (x86_64)
- ✅ ARM64 (aarch64)
- ✅ Builds nativos (sem emulação QEMU)

### 🔒 Segurança
- ✅ Security scan com Trivy
- ✅ Usuário não-root
- ✅ Imagens base específicas (sem :latest)
- ✅ Vulnerabilidades monitoradas

### ⚡ Performance
- ✅ Cache distribuído (registry)
- ✅ Builds otimizados (30-40% mais rápidos)
- ✅ Multi-stage builds
- ✅ Layers minimizadas

### 🔄 CI/CD Automatizado
- ✅ Path filtering inteligente
- ✅ Build apenas do que mudou
- ✅ Deploy automático para Docker Hub
- ✅ README sync automático
- ✅ **Build Matrix** (62% menos código YAML)

### 🏗️ Build Matrix
- ✅ Commands reutilizáveis
- ✅ Job templates parametrizáveis
- ✅ Script gerador de workflows
- ✅ Adicionar versão em ~2 minutos
- ✅ Single source of truth

📖 **[Ver guia completo](.circleci/BUILD-MATRIX.md)**

---

## 📚 Documentação

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Guia completo de contribuição
- **[OPTIMIZATIONS.md](OPTIMIZATIONS.md)** - Otimizações aplicadas e resultados
- **[containers/versions.yml](containers/versions.yml)** - Manifesto de versões
- **[Container READMEs](containers/)** - Documentação específica de cada container

---

## 🛠️ Desenvolvimento

### Pré-requisitos

- Docker 20.10+
- Docker Buildx
- Git

### Adicionar novo container

```bash
# 1. Criar estrutura
mkdir -p containers/<app>/<version>

# 2. Criar Dockerfile
vim containers/<app>/<version>/Dockerfile

# 3. Criar README
vim containers/<app>/<version>/README.md

# 4. Criar workflow CircleCI
cp .circleci/containers/php-fpm/8.3.7.yml .circleci/containers/<app>/<version>.yml

# 5. Atualizar mapping.conf
vim .circleci/mapping.conf

# 6. Atualizar versions.yml
vim containers/versions.yml
```

📖 **[Ver guia completo de contribuição](CONTRIBUTING.md)**

### Testar localmente

```bash
# Build multi-arch
docker buildx build \
  --platform linux/amd64,linux/arm64/v8 \
  -t test:local \
  containers/<app>/<version>/

# Test
docker run --rm test:local
```

---

## 📊 Estatísticas

### Builds
- **Tempo médio de build:** ~5-8 minutos
- **Redução de tempo:** 36% (após otimizações)
- **Taxa de sucesso:** >95%

### Imagens
- **Total de containers:** 8
- **Total de versões mantidas:** 11
- **Arquiteturas:** 2 (amd64, arm64)
- **Total de imagens:** 22+

---

## 🔄 Versionamento

### Apps Terceiros
```
MAJOR.MINOR.PATCH (seguir upstream)
Tags: MAJOR.MINOR.PATCH, MAJOR.MINOR, latest
```

### Apps Internos
```
MAJOR.MINOR.PATCH (Semantic Versioning)
Tags: MAJOR.MINOR.PATCH, MAJOR.MINOR, MAJOR, latest
```

### Versões Alpha/Beta
```
MAJOR.MINOR.PATCH-PRERELEASE
Tags: MAJOR.MINOR.PATCH-PRERELEASE, MAJOR.MINOR-PRERELEASE, PRERELEASE
(sem 'latest')
```

📖 **[Ver estratégia completa de versionamento](CONTRIBUTING.md#estratégia-de-versionamento)**

---

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Leia o [CONTRIBUTING.md](CONTRIBUTING.md)
2. Fork o repositório
3. Crie uma branch (`git checkout -b feature/amazing-feature`)
4. Commit suas mudanças (`git commit -m 'Add amazing feature'`)
5. Push para a branch (`git push origin feature/amazing-feature`)
6. Abra um Pull Request

---

## 📝 Changelog

### Janeiro 2026
- ✅ Otimizações de build (30-40% mais rápido)
- ✅ Trivy otimizado (3-5x mais rápido)
- ✅ README update consolidado
- ✅ Documentação completa (CONTRIBUTING.md, versions.yml)
- ✅ Removido QEMU dos cache jobs nativos

### Dezembro 2025
- ✅ Implementação inicial do monorepo
- ✅ Path filtering com CircleCI
- ✅ Multi-arch builds (amd64 + arm64)
- ✅ Cache distribuído

---

## 🐛 Issues & Support

Encontrou um bug ou tem uma sugestão?

- 🐛 [Abra uma issue](https://github.com/igorferreir4/docker/issues)
- 💬 [Discussões](https://github.com/igorferreir4/docker/discussions)
- 📧 Contato: [Seu email]

---

## 📄 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

---

## 🙏 Agradecimentos

- [CircleCI](https://circleci.com/) - CI/CD Platform
- [Docker](https://docker.com/) - Containerization
- [Trivy](https://github.com/aquasecurity/trivy) - Security Scanner
- Comunidade Open Source

---

## 📈 Status do Projeto

![GitHub last commit](https://img.shields.io/github/last-commit/igorferreir4/docker)
![GitHub issues](https://img.shields.io/github/issues/igorferreir4/docker)
![GitHub pull requests](https://img.shields.io/github/issues-pr/igorferreir4/docker)

**Mantido por:** [@igorferreir4](https://github.com/igorferreir4)  
**Última atualização:** Janeiro 2026

---

<div align="center">

**⭐ Se este projeto foi útil, considere dar uma estrela!**

[🐳 Docker Hub](https://hub.docker.com/u/igorferreir4) • 
[📚 Documentação](CONTRIBUTING.md) • 
[🐛 Issues](https://github.com/igorferreir4/docker/issues) • 
[💬 Discussões](https://github.com/igorferreir4/docker/discussions)

</div>
