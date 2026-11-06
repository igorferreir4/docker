# Pipeline dinâmico

O CircleCI descobre automaticamente os diretórios `containers/<app>/<versão>` que possuem `Dockerfile*`.

Para adicionar uma versão comum, crie somente:

```text
containers/<app>/<versão>/Dockerfile
```

Por padrão, serão publicados `<versão>` e `latest` para `linux/amd64` e `linux/arm64/v8`.

## Configuração opcional

Crie `build.conf` no diretório do app para todas as versões ou dentro da versão para sobrescrever somente aquela versão:

```ini
RESOURCE_CLASS=large
MACHINE_IMAGE=ubuntu-2404:current
TAGS=1.2.3,stable
NOTIFY=true
SCAN=true
```

Todos os campos são opcionais. Arquivos como `Dockerfile.alpine` são descobertos como variantes e recebem automaticamente as tags `<versão>-alpine` e `latest-alpine`.

Alterar `containers/0-run-all/run-all` ou iniciar a pipeline com `run-all=true` executa todos os builds.

## Teste local da configuração gerada

```bash
bash .circleci/scripts/generate-config.sh --all /tmp/continue.yml
```
