# Guia de Contribuição - Docker Monorepo

## 📋 Índice

- [Estrutura do Projeto](#estrutura-do-projeto)
- [Estratégia de Versionamento](#estratégia-de-versionamento)
- [Build Matrix](#build-matrix)
- [Como Adicionar um Novo Container](#como-adicionar-um-novo-container)
- [Como Atualizar uma Versão Existente](#como-atualizar-uma-versão-existente)
- [Otimizações de Build](#otimizações-de-build)
- [Testes e Validação](#testes-e-validação)
- [Deprecação de Versões](#deprecação-de-versões)

---

## 🏗️ Estrutura do Projeto

```
docker/
├── containers/
│   ├── versions.yml              # Manifesto central de versões
│   ├── 0-run-all/                # Trigger para build de todas as imagens
│   ├── <app-name>/
│   │   └── <version>/
│   │       ├── Dockerfile
│   │       └── README.md
│   └── ...
└── .circleci/
    ├── config.yml                # Configuração principal (path filtering)
    ├── mapping.conf              # Mapeamento de paths para workflows
    └── containers/
        └── <app-name>/
            └── <version>.yml     # Workflow específico da versão
```

---

## 📦 Estratégia de Versionamento

### Apps Terceiros (Caddy, PHP-FPM, TS3AudioBot, Focalboard)

**Padrão:** `MAJOR.MINOR.PATCH` (seguir a versão upstream)

**Tags Docker:**
```yaml
IMAGE_TAGS: "MAJOR.MINOR.PATCH,MAJOR.MINOR,latest"
# Exemplo: 8.3.7,8.3,latest
```

**Política de Manutenção:**
- Manter as últimas **2 minor versions**
- Exemplo: Se existem 8.3.6 e 8.3.7, remover 8.3.6 quando 8.4.0 for lançado

### Apps Internos (registrador-consul, traefik-http-provider)

**Padrão:** `MAJOR.MINOR.PATCH` (Semantic Versioning)

**Tags Docker:**
```yaml
IMAGE_TAGS: "MAJOR.MINOR.PATCH,MAJOR.MINOR,MAJOR,latest"
# Exemplo: 1.0.0,1.0,1,latest
```

**Para variantes (alpine, distroless):**
```yaml
IMAGE_TAGS: "MAJOR.MINOR.PATCH-VARIANT,MAJOR.MINOR-VARIANT,latest-VARIANT"
# Exemplo: 1.0.0-alpine,1.0-alpine,latest-alpine
```

### Versões Preview/Alpha/Beta

**Padrão:** `MAJOR.MINOR.PATCH-PRERELEASE`

**Tags Docker:**
```yaml
IMAGE_TAGS: "MAJOR.MINOR.PATCH-PRERELEASE,MAJOR.MINOR-PRERELEASE,PRERELEASE"
# Exemplo: 0.13.0-alpha41,0.13-alpha,alpha
```

**⚠️ IMPORTANTE:** Não incluir tag `latest` em versões instáveis!

---

## 🔄 Build Matrix

O repositório utiliza **Build Matrix** para reduzir duplicação de código YAML. Esta abordagem consolida comandos e templates reutilizáveis.

### Arquivos Principais

- **`.circleci/shared-commands.yml`** - Biblioteca de commands reutilizáveis
- **`.circleci/BUILD-MATRIX.md`** - Guia completo de implementação
- **`.circleci/examples/`** - Exemplos de uso

### Benefícios

- ✅ **62% menos código** (1.650 → 630 linhas)
- ✅ Atualizar lógica em **1 lugar**
- ✅ Adicionar versão: **~15 linhas** (vs ~150)
- ✅ Nomenclatura consistente
- ✅ Menos erros

### Uso Rápido

**Criar novo workflow usando templates:**

```yaml
version: 2.1

# Copiar commands necessários do shared-commands.yml
commands:
  docker-login: { }
  build-cache: { }
  build-and-push-multi-arch: { }

# Usar commands nos jobs
jobs:
  cache-amd64:
    steps:
      - build-cache:
          platform: "linux/amd64"
          cache_tag: "app-1.0.0-amd64"
```

📖 **[Ver guia completo](.circleci/BUILD-MATRIX.md)**

---

## ➕ Como Adicionar um Novo Container

### 1. Criar a estrutura de diretórios

```bash
mkdir -p containers/<app-name>/<version>
cd containers/<app-name>/<version>
```

### 2. Criar o Dockerfile

**Boas práticas:**

```dockerfile
# Use versões específicas (não use :latest)
FROM alpine:3.19

# Minimize camadas - combine comandos RUN
RUN apk add --no-cache \
    package1 \
    package2 \
    package3

# Use multi-stage builds quando possível
FROM builder AS build
# ... build steps ...

FROM alpine:3.19
COPY --from=build /app /app

# Use usuário não-root
USER nobody

# Defina WORKDIR
WORKDIR /app

# Documente portas expostas
**Opção A: Usar template otimizado (recomendado)**

```bash
cp .circleci/containers/php-fpm/8.3.7-v2.yml .circleci/containers/<app-name>/<version>.yml
```

**Opção B: Usar template tradicional**

# Use ENTRYPOINT + CMD para flexibilidade
ENTRYPOINT ["/app/server"]
CMD ["--help"]
```

### 3. Criar README.md

```markdown
# Github Repository

- [CLICK](https://github.com/igorferreir4/docker/tree/main/containers)

## <App Name> v<version>

<Descrição breve do que o container faz>

### Features

- Feature 1
- Feature 2

### Docker Compose Example

\`\`\`yaml
services:
  app:
    image: igorferreir4/<app-name>:<version>
    ports:
      - "8080:8080"
    environment:
      - VAR1=value1
\`\`\`

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| VAR1     | Description | value   |
```

### 4. Criar arquivo CircleCI

Copie um template existente:

```bash
cp .circleci/containers/php-fpm/8.3.7.yml .circleci/containers/<app-name>/<version>.yml
```

**Ajuste as variáveis:**

```yaml
environment:
  CACHE_REPO: igorferreir4/buildcaches
  CACHE_TAG: <app-name>-<version>-amd64  # ou arm64
  IMAGE_REPO: igorferreir4/<app-name>
  IMAGE_TAGS: <version>,latest  # Ou outras tags apropriadas
```

**Nomes dos jobs devem ser únicos:**

```yaml
jobs:
  <app>-v<version>-cache-amd64:
  <app>-v<version>-cache-arm64:
  <app>-v<version>-build-multi-arch:
```

### 5. Adicionar ao mapping.conf

```bash
# <App Name>
containers/<app-name>/<version>/.* build-and-push true .circleci/containers/<app-name>/<version>.yml

# Adicionar ao RUN ALL
containers/0-run-all/.* run-all true .circleci/containers/<app-name>/<version>.yml
```

### 6. Atualizar versions.yml

```yaml
<app-name>:
  current: <version>
  track: "<major.minor>"
  type: third-party  # ou internal
  status: stable     # ou alpha, beta
  base_image: alpine:3.19
  tags: [<version>, latest]
  deprecated_versions: []
```

---

## 🔄 Como Atualizar uma Versão Existente

### Cenário 1: Nova Patch Version (8.3.7 → 8.3.8)

1. Copiar diretório da versão anterior:
```bash
cp -r containers/php-fpm/8.3.7 containers/php-fpm/8.3.8
```

2. Atualizar Dockerfile:
```dockerfile
FROM php:8.3.8-fpm-alpine3.19  # Atualizar versão
```

3. Criar novo workflow CircleCI:
```bash
cp .circleci/containers/php-fpm/8.3.7.yml .circleci/containers/php-fpm/8.3.8.yml
```

4. Atualizar variáveis no workflow:
```yaml
CACHE_TAG: php-8.3.8-amd64
IMAGE_TAGS: 8.3.8,8.3,latest  # 8.3 e latest movem para nova versão
```

5. Atualizar mapping.conf:
```bash
# Adicionar nova versão
containers/php-fpm/8.3.8/.* build-and-push true .circleci/containers/php-fpm/8.3.8.yml
containers/0-run-all/.* run-all true .circleci/containers/php-fpm/8.3.8.yml
```

6. Atualizar versions.yml:
```yaml
php-fpm:
  current: 8.3.8
  deprecated_versions: [8.3.7]  # Marcar versão anterior
```

### Cenário 2: Nova Minor Version (8.3.x → 8.4.0)

Seguir os mesmos passos, mas:

1. Manter versão anterior stable por 14 dias
2. Atualizar tags apropriadamente:
```yaml
# 8.4.0 (novo)
IMAGE_TAGS: 8.4.0,8.4,latest

# 8.3.7 (antigo - remover 'latest')
IMAGE_TAGS: 8.3.7,8.3
```

3. Após período de graça, deprecar 8.3.6:
```yaml
deprecated_versions: [8.3.6]
```

---

## ⚡ Otimizações de Build

### Jobs de Cache (Já implementado)

✅ **Otimizações aplicadas:**

```yaml
jobs:
  <app>-cache-amd64:
    steps:
      - checkout
      # ✅ Login direto (sem QEMU desnecessário)
      - run: docker login
      # ✅ Builder nativo
      - run: docker buildx create --use
      # ✅ Build sem --load (só cache)
      - run: docker buildx build --cache-to=...
```

**Benefícios:**
- ~30-40% mais rápido
- Menos uso de CPU/memória
- Custos reduzidos

### Security Scan (Trivy otimizado)

✅ **Método otimizado:**

```yaml
- run:
    name: Security scan with Trivy
    command: |
      # Download binário direto (3-5x mais rápido que apt)
      wget -qO trivy.tar.gz https://github.com/aquasecurity/trivy/releases/download/v0.48.3/trivy_0.48.3_Linux-64bit.tar.gz
      tar zxf trivy.tar.gz
      sudo mv trivy /usr/local/bin/
      
      trivy image --severity HIGH,CRITICAL --exit-code 0 $IMAGE_REPO:latest
```

### README Updates (Consolidado)

Para apps com múltiplas variantes (alpine, distroless), consolide o README update em um único job que roda após todos os builds.

---

## ✅ Testes e Validação

### Antes de Fazer Commit

1. **Validar Dockerfile:**
```bash
docker build -t test:local containers/<app>/<version>/
docker run --rm test:local --version
```

2. **Validar sintaxe CircleCI:**
```bash
circleci config validate .circleci/containers/<app>/<version>.yml
```

3. **Testar localmente com buildx:**
```bash
docker buildx build \
  --platform linux/amd64,linux/arm64/v8 \
  -t test:multi \
  containers/<app>/<version>/
```

### Após Build no CircleCI

1. **Verificar imagens publicadas:**
```bash
docker manifest inspect igorferreir4/<app>:<version>
```

2. **Testar image multi-arch:**
```bash
docker run --rm --platform linux/amd64 igorferreir4/<app>:<version>
docker run --rm --platform linux/arm64 igorferreir4/<app>:<version>
```

3. **Scan de vulnerabilidades local:**
```bash
trivy image igorferreir4/<app>:<version>
```

---

## 🗑️ Deprecação de Versões

### Critérios para Deprecação

- Versão tem 30+ dias
- Nova minor version está stable por 14+ dias
- Não é a versão `current`

### Processo de Deprecação

1. **Marcar como deprecated em versions.yml:**
```yaml
deprecated_versions: [8.3.6]
deprecation_note: "Será removida em 2026-02-15"
```

2. **Aguardar período de graça (30 dias)**
### Documentação Interna
- [Build Matrix Guide](.circleci/BUILD-MATRIX.md) - Sistema de templates reutilizáveis
- [Shared Commands](.circleci/shared-commands.yml) - Biblioteca de commands
- [Examples](.circleci/examples/) - Exemplos práticos
- [Optimizations](OPTIMIZATIONS.md) - Otimizações aplicadas
- [versions.yml](containers/versions.yml) - Manifesto de versões

### Documentação Externa
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [CircleCI Optimization](https://circleci.com/docs/optimization-cookbook/)
- [CircleCI Reusing Config](https://circleci.com/docs/reusing-config
```bash
# Remover diretório do container
rm -rf containers/<app>/<old-version>/

# Remover workflow CircleCI
rm .circleci/containers/<app>/<old-version>.yml
```

4. **Atualizar mapping.conf:**
```bash
# Remover linhas da versão antiga
```

5. **Atualizar versions.yml:**
```yaml
deprecated_versions: []  # Limpar lista
```

6. **(Opcional) Remover imagens do Docker Hub:**
```bash
# Não remover automaticamente - usuários podem depender
# Apenas parar de atualizar
```

---

## 🎯 Checklist para Nova Versão

```markdown
- [ ] Criar diretório `containers/<app>/<version>/`
- [ ] Criar Dockerfile com versão específica
- [ ] Criar README.md com documentação
- [ ] Criar workflow `.circleci/containers/<app>/<version>.yml`
- [ ] Adicionar ao `mapping.conf`
- [ ] Atualizar `versions.yml`
- [ ] Validar Dockerfile localmente
- [ ] Validar sintaxe CircleCI
- [ ] Commit e push
- [ ] Monitorar build no CircleCI
- [ ] Verificar imagens no Docker Hub
- [ ] Testar container publicado
- [ ] Atualizar documentação (se necessário)
```

---

## 📚 Recursos Adicionais

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [CircleCI Optimization](https://circleci.com/docs/optimization-cookbook/)
- [Semantic Versioning](https://semver.org/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)

---

## 💡 Dicas Extras

### Performance

- Use `.dockerignore` para excluir arquivos desnecessários
- Aproveite o cache de layers (comandos que mudam menos no topo)
- Use `--cache-from` e `--cache-to` para cache distribuído

### Segurança

- Sempre use versões específicas de base images
- Execute containers como usuário não-root
- Scan de vulnerabilidades em cada build
- Minimize o número de pacotes instalados

### Manutenibilidade

- Documente environment variables no README
- Use labels no Dockerfile (org.opencontainers.image.*)
- Mantenha versions.yml sempre atualizado
- Siga convenções de nomenclatura consistentes

---

**Última atualização:** 2026-01-12  
**Mantido por:** @igorferreir4
