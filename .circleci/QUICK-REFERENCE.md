# Build Matrix - Quick Reference 🚀

Referência rápida de commands e padrões do Build Matrix.

---

## 📦 Commands Disponíveis

### Login & Setup
```yaml
- docker-login                        # Login Docker Hub
- setup-buildx-with-qemu             # QEMU + Buildx + Login
```

### Build
```yaml
- build-cache:
    platform: "linux/amd64"          # ou linux/arm64/v8
    cache_tag: "app-1.0.0-amd64"
    builder_name: "app-builder"

- build-and-push-multi-arch:
    cache_amd64: "app-1.0.0-amd64"
    cache_arm64: "app-1.0.0-arm64"
    image_repo: "igorferreir4/app"
    image_tags: "1.0.0,latest"
```

### Verificação & Security
```yaml
- verify-images:
    image_repo: "igorferreir4/app"
    image_tags: "1.0.0,latest"

- install-trivy:
    version: "0.48.3"                # opcional

- trivy-scan:
    image: "igorferreir4/app:latest"
    severity: "HIGH,CRITICAL"        # opcional
    exit_code: 0                     # opcional
```

### Docker Hub & Deploy
```yaml
- update-dockerhub-readme:
    image_repo: "igorferreir4/app"
    readme_path: "../README.md"      # opcional

- deploy-notification:
    message: "App v1.0.0"
```

---

## 🎯 Executors

```yaml
executors:
  docker-small                       # Docker, small
  machine-amd64-medium               # Ubuntu, amd64, medium
  machine-amd64-large                # Ubuntu, amd64, large
  machine-arm64-medium               # Ubuntu, arm64, medium
  machine-arm64-large                # Ubuntu, arm64, large
```

---

## 📋 Template Mínimo

### Workflow Simples

```yaml
version: 2.1

executors:
  machine-amd64-large:
    machine:
      image: ubuntu-2204:current
    resource_class: large

parameters:
  build-and-push:
    type: boolean
    default: false

commands:
  docker-login:
    steps:
      - run: echo "$DOCKERHUB_PASSWORD" | docker login --username $DOCKERHUB_USERNAME --password-stdin

jobs:
  cache-amd64:
    executor: machine-amd64-large
    working_directory: ~/project/containers/app/1.0.0
    steps:
      - checkout:
          path: ~/project
      - docker-login
      - run:
          name: Build cache
          command: |
            docker buildx create --use --name builder || docker buildx use builder
            docker buildx build \
              --cache-from="igorferreir4/buildcaches:app-1.0.0-amd64" \
              --cache-to=type=registry,ref=igorferreir4/buildcaches:app-1.0.0-amd64,mode=max \
              --platform=linux/amd64 \
              .

workflows:
  app-v1_0_0:
    when: << pipeline.parameters.build-and-push >>
    jobs:
      - cache-amd64
```

---

## 🔧 Padrões de Nomenclatura

### Variáveis
```yaml
CACHE_REPO: igorferreir4/buildcaches
CACHE_TAG: app-1.0.0-amd64
IMAGE_REPO: igorferreir4/app
IMAGE_TAGS: 1.0.0,latest
```

### Jobs
```yaml
cache-amd64                          # Build cache AMD64
cache-arm64                          # Build cache ARM64
build-and-push                       # Build multi-arch e push
deploy                               # Notificação de deploy
post-build-tasks                     # Tasks pós-build
```

### Workflows
```yaml
app-v1_0_0                           # Underscores para versão
caddy-v2_7_6
php-8_3_7
```

### Builders
```yaml
app-100-amd64                        # <app>-<version>-<arch>
caddy-276-arm64
php-837-amd64
```

---

## 🚀 Uso Rápido

### Gerar novo workflow
```bash
./.circleci/scripts/generate-workflow.sh
```

### Copiar template
```bash
cp .circleci/containers/php-fpm/8.3.7-v2.yml \
   .circleci/containers/myapp/1.0.0.yml
```

### Validar YAML
```bash
circleci config validate .circleci/containers/app/version.yml
```

---

## 📚 Documentação Completa

- 📘 [BUILD-MATRIX.md](.circleci/BUILD-MATRIX.md) - Guia completo
- 📗 [shared-commands.yml](.circleci/shared-commands.yml) - Biblioteca
- 📙 [Exemplos](.circleci/examples/) - Casos práticos
- 📕 [CONTRIBUTING.md](../CONTRIBUTING.md) - Guia de contribuição

---

**Atualizado:** 2026-01-12
