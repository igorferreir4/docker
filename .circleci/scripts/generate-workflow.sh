#!/bin/bash

# ==========================================
# Generate CircleCI Workflow
# Gera novo workflow a partir do template build matrix
# ==========================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║       CircleCI Workflow Generator - Build Matrix       ║"
echo "╔════════════════════════════════════════════════════════╗"
echo -e "${NC}"

# ==========================================
# Validações
# ==========================================

if [ ! -f ".circleci/shared-commands.yml" ]; then
    echo -e "${RED}✗ Erro: Execute este script da raiz do repositório${NC}"
    exit 1
fi

# ==========================================
# Input do Usuário
# ==========================================

echo -e "${YELLOW}Informações do Container:${NC}"
echo ""

read -p "Nome do container (ex: nginx): " APP_NAME
read -p "Versão (ex: 1.25.3): " VERSION
read -p "Resource class (small/medium/large) [medium]: " RESOURCE_CLASS
RESOURCE_CLASS=${RESOURCE_CLASS:-medium}

read -p "Image tags (separadas por vírgula, ex: 1.25.3,1.25,latest): " IMAGE_TAGS
read -p "Incluir deploy notification? (y/n) [y]: " INCLUDE_DEPLOY
INCLUDE_DEPLOY=${INCLUDE_DEPLOY:-y}

# ==========================================
# Gerar Variáveis
# ==========================================

APP_SLUG=$(echo "$APP_NAME" | tr '.' '_' | tr '-' '_')
VERSION_SLUG=$(echo "$VERSION" | tr '.' '_' | tr '-' '_')
CACHE_TAG_BASE="${APP_NAME}-${VERSION}"
IMAGE_REPO="igorferreir4/${APP_NAME}"
WORKING_DIR="~/project/containers/${APP_NAME}/${VERSION}"

echo ""
echo -e "${BLUE}Configuração:${NC}"
echo "  App: $APP_NAME"
echo "  Versão: $VERSION"
echo "  Resource: $RESOURCE_CLASS"
echo "  Tags: $IMAGE_TAGS"
echo "  Deploy: $INCLUDE_DEPLOY"
echo ""

read -p "Confirma? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo -e "${RED}Cancelado${NC}"
    exit 1
fi

# ==========================================
# Criar Estrutura de Diretórios
# ==========================================

echo ""
echo -e "${BLUE}Criando estrutura...${NC}"

mkdir -p "containers/${APP_NAME}/${VERSION}"
mkdir -p ".circleci/containers/${APP_NAME}"

# ==========================================
# Gerar Workflow YAML
# ==========================================

OUTPUT_FILE=".circleci/containers/${APP_NAME}/${VERSION}.yml"

cat > "$OUTPUT_FILE" << EOF
version: 2.1

# Auto-generated workflow for ${APP_NAME} v${VERSION}
# Generated at: $(date +"%Y-%m-%d %H:%M:%S")
# Using: Build Matrix Template v2

# ==========================================
# EXECUTORS
# ==========================================

executors:
  machine-amd64-${RESOURCE_CLASS}:
    machine:
      image: ubuntu-2204:current
    resource_class: ${RESOURCE_CLASS}

  machine-arm64-${RESOURCE_CLASS}:
    machine:
      image: ubuntu-2204:current
    resource_class: arm.${RESOURCE_CLASS}

  machine-amd64-medium:
    machine:
      image: ubuntu-2204:current
    resource_class: medium

  docker-small:
    docker:
      - image: cimg/base:current
    resource_class: small

# ==========================================
# PARAMETERS
# ==========================================

parameters:
  build-and-push:
    type: boolean
    default: false
  run-all:
    type: boolean
    default: false

# ==========================================
# COMMANDS (from shared-commands.yml)
# ==========================================

commands:
  docker-login:
    steps:
      - run:
          name: Login to Docker Hub
          command: |
            echo "\$DOCKERHUB_PASSWORD" | docker login --username \$DOCKERHUB_USERNAME --password-stdin

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
          name: Build cache (<< parameters.platform >>)
          command: |
            docker buildx create --use --name << parameters.builder_name >> --driver docker-container || docker buildx use << parameters.builder_name >>
            docker buildx build \\
              --build-arg BUILDKIT_INLINE_CACHE=0 \\
              --cache-from="igorferreir4/buildcaches:<< parameters.cache_tag >>" \\
              --cache-to=type=registry,ref=igorferreir4/buildcaches:<< parameters.cache_tag >>,mode=max \\
              --platform=<< parameters.platform >> \\
              .

  setup-buildx-with-qemu:
    steps:
      - run:
          name: Setup QEMU
          command: |
            docker run --privileged --rm tonistiigi/binfmt --install all
      - run:
          name: Create Buildx Builder
          command: |
            docker buildx create --name multi-arch-build --bootstrap --use
      - docker-login

  build-and-push-multi-arch:
    parameters:
      cache_amd64:
        type: string
      cache_arm64:
        type: string
      image_repo:
        type: string
      image_tags:
        type: string
    steps:
      - setup-buildx-with-qemu
      - run:
          name: Build and push multi-arch
          command: |
            TAGS=""
            for tag in \$(echo << parameters.image_tags >> | tr "," " "); do
              TAGS="\$TAGS -t << parameters.image_repo >>:\$tag"
            done
            
            docker buildx build \\
              --build-arg BUILDKIT_INLINE_CACHE=0 \\
              --cache-from="igorferreir4/buildcaches:<< parameters.cache_amd64 >>" \\
              --cache-from="igorferreir4/buildcaches:<< parameters.cache_arm64 >>" \\
              --push \\
              --platform=linux/amd64,linux/arm64/v8 \\
              \$TAGS .

  verify-images:
    parameters:
      image_repo:
        type: string
      image_tags:
        type: string
    steps:
      - run:
          name: Verify pushed images
          command: |
            for tag in \$(echo << parameters.image_tags >> | tr "," " "); do
              echo "Checking << parameters.image_repo >>:\$tag"
              docker manifest inspect << parameters.image_repo >>:\$tag > /dev/null
              if [ \$? -eq 0 ]; then
                echo "✓ << parameters.image_repo >>:\$tag exists"
              else
                echo "✗ << parameters.image_repo >>:\$tag not found"
                exit 1
              fi
            done

  update-dockerhub-readme:
    parameters:
      image_repo:
        type: string
    steps:
      - run:
          name: Update Docker Hub README
          command: |
            README_CONTENT=\$(jq -Rs '.' ../README.md)
            PAYLOAD="username=\$DOCKERHUB_USERNAME&password=\$DOCKERHUB_PASSWORD"
            JWT=\$(curl -s -d "\$PAYLOAD" https://hub.docker.com/v2/users/login/ | jq -r .token)
            
            if [ -z "\$JWT" ] || [ "\$JWT" = "null" ]; then
              echo "✗ Failed to authenticate"
              exit 1
            fi
            
            STATUS=\$(curl -s -o /dev/null -w '%{http_code}' \\
              -X PATCH \\
              -H "Authorization: JWT \$JWT" \\
              -H 'Content-type: application/json' \\
              --data "{\\"full_description\\": \$README_CONTENT}" \\
              https://hub.docker.com/v2/repositories/<< parameters.image_repo >>/)
            
            [ \$STATUS -eq 200 ] && echo "✓ README updated" || exit 1

  deploy-notification:
    parameters:
      message:
        type: string
    steps:
      - add_ssh_keys:
          fingerprints:
            - "SHA256:hLlCCj1OZj3pbBbgrGvfHjdTf20F4IYKyKvyJTMXC/A"
      - run:
          name: Deploy notification
          command: |
            ssh-keyscan \$SSH_HOST_IGOR_ARM >> ~/.ssh/known_hosts
            ssh \$SSH_USER@\$SSH_HOST_IGOR_ARM "echo 'Executado em '\$(date -d '-3 hours' +'%d/%m/%G - %Hh:%Mm:%Ss')' - << parameters.message >>' >> circleci-builds.txt"

# ==========================================
# JOBS
# ==========================================

jobs:
  cache-amd64:
    executor: machine-amd64-${RESOURCE_CLASS}
    working_directory: ${WORKING_DIR}
    steps:
      - checkout:
          path: ~/project
      - build-cache:
          platform: "linux/amd64"
          cache_tag: "${CACHE_TAG_BASE}-amd64"
          builder_name: "${APP_SLUG}-${VERSION_SLUG}-amd64"

  cache-arm64:
    executor: machine-arm64-${RESOURCE_CLASS}
    working_directory: ${WORKING_DIR}
    steps:
      - checkout:
          path: ~/project
      - build-cache:
          platform: "linux/arm64/v8"
          cache_tag: "${CACHE_TAG_BASE}-arm64"
          builder_name: "${APP_SLUG}-${VERSION_SLUG}-arm64"

  build-and-push:
    executor: machine-amd64-medium
    working_directory: ${WORKING_DIR}
    steps:
      - checkout:
          path: ~/project
      - build-and-push-multi-arch:
          cache_amd64: "${CACHE_TAG_BASE}-amd64"
          cache_arm64: "${CACHE_TAG_BASE}-arm64"
          image_repo: "${IMAGE_REPO}"
          image_tags: "${IMAGE_TAGS}"
      - verify-images:
          image_repo: "${IMAGE_REPO}"
          image_tags: "${IMAGE_TAGS}"
      - update-dockerhub-readme:
          image_repo: "${IMAGE_REPO}"
EOF

# Deploy job (condicional)
if [ "$INCLUDE_DEPLOY" = "y" ]; then
    cat >> "$OUTPUT_FILE" << EOF

  deploy:
    executor: docker-small
    steps:
      - deploy-notification:
          message: "${APP_NAME} v${VERSION}"
EOF
fi

# Workflow
cat >> "$OUTPUT_FILE" << EOF

# ==========================================
# WORKFLOW
# ==========================================

workflows:
  ${APP_SLUG}-v${VERSION_SLUG}:
    when:
      or:
        - << pipeline.parameters.build-and-push >>
        - << pipeline.parameters.run-all >>
    jobs:
      - cache-amd64
      - cache-arm64
      - build-and-push:
          requires:
            - cache-amd64
            - cache-arm64
EOF

if [ "$INCLUDE_DEPLOY" = "y" ]; then
    cat >> "$OUTPUT_FILE" << EOF
      - deploy:
          requires:
            - build-and-push
EOF
fi

# ==========================================
# Criar Dockerfile e README básicos
# ==========================================

if [ ! -f "containers/${APP_NAME}/${VERSION}/Dockerfile" ]; then
    cat > "containers/${APP_NAME}/${VERSION}/Dockerfile" << EOF
# Auto-generated Dockerfile for ${APP_NAME} v${VERSION}
# TODO: Customize this file

FROM alpine:latest

# TODO: Add your build steps here

WORKDIR /app

EXPOSE 8080

CMD ["/bin/sh"]
EOF
    echo -e "${GREEN}✓ Dockerfile criado (containers/${APP_NAME}/${VERSION}/Dockerfile)${NC}"
fi

if [ ! -f "containers/${APP_NAME}/${VERSION}/README.md" ]; then
    cat > "containers/${APP_NAME}/${VERSION}/README.md" << EOF
# Github Repository

- [CLICK](https://github.com/igorferreir4/docker/tree/main/containers)

## ${APP_NAME} v${VERSION}

TODO: Adicione descrição do container

### Features

- Feature 1
- Feature 2

### Docker Compose Example

\`\`\`yaml
version: '3.8'
services:
  ${APP_NAME}:
    image: ${IMAGE_REPO}:${VERSION}
    ports:
      - "8080:8080"
\`\`\`
EOF
    echo -e "${GREEN}✓ README criado (containers/${APP_NAME}/${VERSION}/README.md)${NC}"
fi

# ==========================================
# Atualizar mapping.conf
# ==========================================

MAPPING_LINE="containers/${APP_NAME}/${VERSION}/.* build-and-push true .circleci/containers/${APP_NAME}/${VERSION}.yml"

if ! grep -q "$MAPPING_LINE" .circleci/mapping.conf; then
    echo "" >> .circleci/mapping.conf
    echo "# ${APP_NAME}" >> .circleci/mapping.conf
    echo "$MAPPING_LINE" >> .circleci/mapping.conf
    echo -e "${GREEN}✓ mapping.conf atualizado${NC}"
else
    echo -e "${YELLOW}⚠ mapping.conf já contém entrada para este container${NC}"
fi

# ==========================================
# Resumo
# ==========================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  Workflow Criado! ✓                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Arquivos criados:${NC}"
echo "  ✓ $OUTPUT_FILE"
echo "  ✓ containers/${APP_NAME}/${VERSION}/Dockerfile"
echo "  ✓ containers/${APP_NAME}/${VERSION}/README.md"
echo ""
echo -e "${YELLOW}Próximos passos:${NC}"
echo "  1. Edite o Dockerfile em containers/${APP_NAME}/${VERSION}/"
echo "  2. Personalize o README em containers/${APP_NAME}/${VERSION}/"
echo "  3. Atualize containers/versions.yml"
echo "  4. Teste localmente: docker build containers/${APP_NAME}/${VERSION}/"
echo "  5. Commit e push para trigger do build"
echo ""
echo -e "${BLUE}Para adicionar ao run-all, adicione em mapping.conf:${NC}"
echo "  containers/0-run-all/.* run-all true .circleci/containers/${APP_NAME}/${VERSION}.yml"
echo ""
