# Build Matrix - Guia de Implementação

## 📋 Índice

1. [Visão Geral](#visão-geral)
2. [Benefícios](#benefícios)
3. [Arquivos Criados](#arquivos-criados)
4. [Migração Passo a Passo](#migração-passo-a-passo)
5. [Comparação Antes/Depois](#comparação-antesdepois)
6. [Exemplos de Uso](#exemplos-de-uso)
7. [Melhores Práticas](#melhores-práticas)

---

## 🎯 Visão Geral

O **Build Matrix** é uma abordagem para reduzir duplicação de código YAML nos workflows do CircleCI através de:

- ✅ **Commands reutilizáveis** - Lógica compartilhada entre todos os containers
- ✅ **Job templates** - Estruturas parametrizáveis
- ✅ **Executors padronizados** - Configurações de recursos centralizadas
- ✅ **Matrix workflows** - Múltiplas versões com código mínimo

---

## 💎 Benefícios

### Redução de Código
```
Antes: ~150 linhas por versão × 11 versões = 1.650 linhas
Depois: ~300 linhas base + ~30 linhas/versão = 630 linhas
Redução: ~62% (1.020 linhas)
```

### Manutenibilidade
- ✅ Atualizar lógica em **1 lugar** (vs 11 lugares)
- ✅ Adicionar versão: **~15 linhas** (vs ~150 linhas)
- ✅ Menos erros de copy-paste
- ✅ Nomenclatura consistente

### Performance
- ✅ Mesma velocidade de build
- ✅ Melhor reuso de cache
- ✅ Triggers seletivos (build apenas versão específica)

### Flexibilidade
- ✅ Build versão específica via parâmetro
- ✅ Build todas as versões com `run-all`
- ✅ Fácil adicionar novas arquiteturas
- ✅ Suporta variantes (alpine, distroless)

---

## 📦 Arquivos Criados

### 1. `shared-commands.yml`
**Localização:** `.circleci/shared-commands.yml`

**Conteúdo:**
- Executors padronizados (small, medium, large para amd64/arm64)
- Commands reutilizáveis (docker-login, build-cache, etc)
- Job templates genéricos
- ~350 linhas de código reutilizável

**Uso:** Base para todos os workflows

### 2. `php-fpm/8.3.7-v2.yml` (Exemplo Simplificado)
**Localização:** `.circleci/containers/php-fpm/8.3.7-v2.yml`

**Demonstra:**
- Como usar commands compartilhados
- Workflow com código reduzido
- ~100 linhas (vs ~150 original)

### 3. `examples/php-fpm-matrix.yml` (Exemplo Avançado)
**Localização:** `.circleci/examples/php-fpm-matrix.yml`

**Demonstra:**
- Matrix para múltiplas versões
- Parâmetros condicionais
- Build seletivo por versão
- ~150 linhas para 2 versões (vs ~300 original)

---

## 🔄 Migração Passo a Passo

### Fase 1: Preparação (Concluída ✅)

1. **Criar shared-commands.yml** ✅
   ```bash
   .circleci/shared-commands.yml
   ```

2. **Criar exemplos de referência** ✅
   ```bash
   .circleci/containers/php-fpm/8.3.7-v2.yml
   .circleci/examples/php-fpm-matrix.yml
   ```

3. **Documentar abordagem** ✅
   ```bash
   .circleci/BUILD-MATRIX.md (este arquivo)
   ```

### Fase 2: Migração Gradual (Próximos Passos)

#### Opção A: Migração Individual (Conservadora)

**Para cada container:**

1. **Copiar arquivo original:**
   ```bash
   cp .circleci/containers/caddy/2.7.6.yml .circleci/containers/caddy/2.7.6.bak.yml
   ```

2. **Criar versão v2:**
   ```bash
   cp .circleci/containers/php-fpm/8.3.7-v2.yml .circleci/containers/caddy/2.7.6-v2.yml
   ```

3. **Ajustar parâmetros:**
   ```yaml
   # Substituir valores específicos do PHP por valores do Caddy
   version: "2.7.6"
   image_repo: "igorferreir4/caddy"
   cache_tag: "caddy-2.7.6-amd64"
   tags: "2.7.6,2.7,latest"
   working_directory: ~/project/containers/caddy/2.7.6
   ```

4. **Testar nova versão:**
   ```bash
   # Atualizar mapping.conf para usar -v2.yml
   vim .circleci/mapping.conf
   
   # Fazer commit e monitorar build
   git add .
   git commit -m "refactor(caddy): migrate to build matrix v2"
   git push
   ```

5. **Após validação, substituir original:**
   ```bash
   mv .circleci/containers/caddy/2.7.6-v2.yml .circleci/containers/caddy/2.7.6.yml
   rm .circleci/containers/caddy/2.7.6.bak.yml
   ```

**Containers para migrar:**
- [x] php-fpm/8.3.7 (exemplo criado)
- [ ] php-fpm/8.3.6
- [ ] caddy/2.7.6
- [ ] ts3audiobot/0.12.2
- [ ] ts3audiobot/0.13.0-alpha41
- [ ] focalboard/7.11.4
- [ ] registrador-consul/1.0.0
- [ ] traefik-http-provider/1.0.0

#### Opção B: Matrix Consolidado (Avançada)

**Para containers com múltiplas versões (PHP-FPM, TS3AudioBot):**

1. **Criar arquivo matrix unificado:**
   ```bash
   # Para PHP-FPM
   cp .circleci/examples/php-fpm-matrix.yml .circleci/containers/php-fpm/matrix.yml
   ```

2. **Atualizar mapping.conf:**
   ```bash
   # Substituir entradas individuais:
   # containers/php-fpm/8.3.6/.* build-and-push true .circleci/containers/php-fpm/8.3.6.yml
   # containers/php-fpm/8.3.7/.* build-and-push true .circleci/containers/php-fpm/8.3.7.yml
   
   # Por entrada única:
   containers/php-fpm/.*/.* build-and-push true .circleci/containers/php-fpm/matrix.yml
   ```

3. **Testar build específico:**
   ```bash
   # Modificar arquivo em 8.3.7 apenas
   echo "# test" >> containers/php-fpm/8.3.7/Dockerfile
   git commit -am "test: php 8.3.7 matrix"
   
   # Deve buildar apenas 8.3.7
   ```

4. **Testar run-all:**
   ```bash
   # Modificar trigger
   echo "Run: 12" > containers/0-run-all/run-all
   
   # Deve buildar todas as versões
   ```

### Fase 3: Limpeza (Final)

1. **Remover arquivos antigos:**
   ```bash
   # Após validar todos os migrados
   rm .circleci/containers/*/*.bak.yml
   ```

2. **Atualizar documentação:**
   ```bash
   # Atualizar CONTRIBUTING.md com novos padrões
   vim CONTRIBUTING.md
   ```

3. **Criar script de geração:**
   ```bash
   # Script para gerar novo workflow a partir de template
   .circleci/scripts/generate-workflow.sh
   ```

---

## 📊 Comparação Antes/Depois

### Antes (Arquivo Original)

```yaml
version: 2.1

executors:
  docker-executor:
    docker:
      - image: cimg/base:current
    resource_class: small
    
  machine-executor-amd64:
    machine:
      image: ubuntu-2204:current
    resource_class: large

  machine-executor-arm64:
    machine:
      image: ubuntu-2204:current
    resource_class: arm.large

parameters:
  build-and-push:
    type: boolean
    default: false
  run-all:
    type: boolean
    default: false

commands:
  setup-qemu:
    steps:
      - run:
          name: Setup Qemu
          command: |
            docker run --privileged --rm tonistiigi/binfmt --install all
      - run:
          name: Create builder
          command: |
            docker buildx create --name multi-arch-build --bootstrap --use
      - run:
          name: Login to Docker Hub
          command: |
            echo "$DOCKERHUB_PASSWORD" | docker login --username $DOCKERHUB_USERNAME --password-stdin

jobs:
  phpfpm-v8_3_7-cache-amd64:
    executor: machine-executor-amd64
    environment:
      CACHE_REPO: igorferreir4/buildcaches
      CACHE_TAG: php-8.3.7-amd64
      CACHE_TAG_OLD: php-8.3.7-amd64
    working_directory: ~/project/containers/php-fpm/8.3.7
    steps:
      - checkout:
          path: ~/project
      - run:
          name: Login to Docker Hub
          command: |
            echo "$DOCKERHUB_PASSWORD" | docker login --username $DOCKERHUB_USERNAME --password-stdin
      - run:
          name: Build docker image (amd64 cache)
          command: |
            docker buildx create --use --name php-837-amd64-builder --driver docker-container || docker buildx use php-837-amd64-builder
            docker buildx build \
              --build-arg BUILDKIT_INLINE_CACHE=0 \
              --cache-from="$CACHE_REPO:$CACHE_TAG_OLD" \
              --cache-from="$CACHE_REPO:$CACHE_TAG" \
              --cache-to=type=registry,ref=$CACHE_REPO:$CACHE_TAG,mode=max \
              --platform=linux/amd64 \
              .

  phpfpm-v8_3_7-cache-arm64:
    executor: machine-executor-arm64
    # ... mesmo padrão repetido ...

  phpfpm-v8_3_7-build-multi-arch:
    executor: machine-executor-amd64
    # ... mais código repetido ...
    
  phpfpm-v8_3_7-deploy:
    # ... mais código ...

workflows:
  php-8_3_7:
    jobs:
      - phpfpm-v8_3_7-cache-amd64
      - phpfpm-v8_3_7-cache-arm64
      - phpfpm-v8_3_7-build-multi-arch:
          requires:
            - phpfpm-v8_3_7-cache-amd64
            - phpfpm-v8_3_7-cache-arm64
      - phpfpm-v8_3_7-deploy:
          requires:
            - phpfpm-v8_3_7-build-multi-arch

# Total: ~150-160 linhas
```

### Depois (Com Build Matrix)

```yaml
version: 2.1

# Import shared commands (conceitual)
# Na prática, copiamos os commands necessários

executors:
  machine-amd64-large:
    machine:
      image: ubuntu-2204:current
    resource_class: large
  # ... outros executors ...

parameters:
  build-and-push:
    type: boolean
    default: false
  run-all:
    type: boolean
    default: false

commands:
  # Commands copiados do shared-commands.yml
  docker-login:
    steps:
      - run: echo "$DOCKERHUB_PASSWORD" | docker login --username $DOCKERHUB_USERNAME --password-stdin

  build-cache:
    parameters:
      platform:
        type: string
      cache_tag:
        type: string
      builder_name:
        type: string
    steps:
      - docker-login
      - run:
          command: |
            docker buildx create --use --name << parameters.builder_name >> || docker buildx use << parameters.builder_name >>
            docker buildx build \
              --cache-from="igorferreir4/buildcaches:<< parameters.cache_tag >>" \
              --cache-to=type=registry,ref=igorferreir4/buildcaches:<< parameters.cache_tag >>,mode=max \
              --platform=<< parameters.platform >> \
              .
  # ... outros commands ...

jobs:
  cache-amd64:
    executor: machine-amd64-large
    working_directory: ~/project/containers/php-fpm/8.3.7
    steps:
      - checkout:
          path: ~/project
      - build-cache:
          platform: "linux/amd64"
          cache_tag: "php-8.3.7-amd64"
          builder_name: "php-837-amd64"

  cache-arm64:
    # Similar, usando command
    
  build-and-push:
    # Usa command build-and-push-multi-arch
    
  deploy:
    # Usa command deploy-notification

workflows:
  php-8_3_7:
    jobs:
      - cache-amd64
      - cache-arm64
      - build-and-push:
          requires:
            - cache-amd64
            - cache-arm64
      - deploy:
          requires:
            - build-and-push

# Total: ~100 linhas (redução de 33%)
```

### Depois (Com Matrix Consolidado - 2+ versões)

```yaml
# php-fpm-matrix.yml - gerencia 8.3.6 e 8.3.7

# Total: ~150 linhas para 2 versões
# vs ~300 linhas (2 arquivos separados)
# Redução: 50%
```

---

## 💡 Exemplos de Uso

### Build de Versão Específica

```bash
# Via API do CircleCI
curl -X POST \
  --header "Content-Type: application/json" \
  --header "Circle-Token: $CIRCLECI_TOKEN" \
  -d '{
    "parameters": {
      "build-and-push": true,
      "version": "8.3.7"
    }
  }' \
  https://circleci.com/api/v2/project/github/igorferreir4/docker/pipeline
```

### Build de Todas as Versões

```bash
# Modificar arquivo run-all
echo "Run: 13" > containers/0-run-all/run-all
git commit -am "trigger: run all builds"
git push

# Ou via API
curl -X POST \
  --header "Content-Type: application/json" \
  --header "Circle-Token: $CIRCLECI_TOKEN" \
  -d '{
    "parameters": {
      "run-all": true
    }
  }' \
  https://circleci.com/api/v2/project/github/igorferreir4/docker/pipeline
```

### Adicionar Nova Versão (Matrix)

```yaml
# No arquivo matrix.yml, adicionar:

workflows:
  php-8_3_8:  # Nova versão
    when:
      and:
        - or:
            - << pipeline.parameters.build-and-push >>
            - << pipeline.parameters.run-all >>
        - or:
            - equal: [ "8.3.8", << pipeline.parameters.version >> ]
            - equal: [ "all", << pipeline.parameters.version >> ]
    jobs:
      - cache-build:
          name: php-8.3.8-cache-amd64
          version: "8.3.8"
          arch: "amd64"
          platform: "linux/amd64"
          executor: machine-amd64-large
      
      - cache-build:
          name: php-8.3.8-cache-arm64
          version: "8.3.8"
          arch: "arm64"
          platform: "linux/arm64/v8"
          executor: machine-arm64-large
      
      - multi-arch-build:
          name: php-8.3.8-build
          version: "8.3.8"
          tags: "8.3.8,8.3,latest"
          requires:
            - php-8.3.8-cache-amd64
            - php-8.3.8-cache-arm64

# Total adicionado: ~25 linhas
# vs ~150 linhas (arquivo separado)
```

---

## ✅ Melhores Práticas

### 1. Nomenclatura Consistente

```yaml
# Commands: verbo-substantivo
docker-login
build-cache
setup-buildx-with-qemu
verify-images

# Jobs: substantivo-ação
cache-amd64
cache-arm64
build-and-push
post-build-tasks

# Workflows: app-versao
php-8_3_7
caddy-2_7_6
```

### 2. Parâmetros Consistentes

```yaml
# Sempre use mesmos nomes
cache_repo: "igorferreir4/buildcaches"
image_repo: "igorferreir4/app-name"
cache_tag: "app-version-arch"
platform: "linux/amd64" ou "linux/arm64/v8"
```

### 3. Documentação Inline

```yaml
commands:
  build-cache:
    description: "Build de cache nativo otimizado"  # ✅ Sempre documente
    parameters:
      platform:
        type: string
        description: "Plataforma alvo"  # ✅ Descreva parâmetros
```

### 4. Defaults Sensatos

```yaml
parameters:
  cache_repo:
    type: string
    default: "igorferreir4/buildcaches"  # ✅ Default comum
  dockerfile:
    type: string
    default: "Dockerfile"  # ✅ Assume padrão
```

### 5. Validação

```yaml
# Sempre valide resultados críticos
- verify-images:
    image_repo: "igorferreir4/app"
    image_tags: "1.0.0,latest"

# Exit codes apropriados
trivy image --exit-code 0  # Não falhar em vulnerabilidades
```

### 6. Logging Claro

```yaml
- run:
    name: Build cache (linux/amd64)  # ✅ Nome descritivo
    command: |
      echo "Building for linux/amd64..."  # ✅ Log informativo
      docker buildx build ...
      echo "✓ Cache created successfully"  # ✅ Feedback de sucesso
```

---

## 🚀 Próximos Passos

### Curto Prazo
- [ ] Validar php-fpm/8.3.7-v2.yml em build real
- [ ] Migrar 1-2 containers para v2 (caddy, ts3audiobot)
- [ ] Criar script de geração de workflow
- [ ] Atualizar CONTRIBUTING.md

### Médio Prazo
- [ ] Migrar todos os containers individuais
- [ ] Consolidar PHP-FPM em matrix
- [ ] Consolidar TS3AudioBot em matrix
- [ ] Criar CI lint para validar workflows

### Longo Prazo
- [ ] Publicar como CircleCI Orb público
- [ ] Adicionar testes automatizados de workflows
- [ ] Dynamic matrix baseado em versions.yml
- [ ] Auto-geração de workflows a partir de metadata

---

## 📞 Suporte

Dúvidas sobre build matrix:

1. Consulte [shared-commands.yml](.circleci/shared-commands.yml)
2. Veja exemplos em [.circleci/examples/](.circleci/examples/)
3. Revise [CONTRIBUTING.md](../CONTRIBUTING.md)
4. Verifique documentação do [CircleCI](https://circleci.com/docs/reusing-config/)

---

**Criado:** 2026-01-12  
**Status:** ✅ Implementado (Fase 1 - Base e Exemplos)  
**Próxima Fase:** Migração Gradual
