# kinfo

Mostra detalhes de um deployment no Kubernetes: namespace, env, versão e
quem/quando fez o último deploy.

## Uso

```bash
kinfo <ambiente> [nome-do-app]
kinfo -h | --help
```

- `<ambiente>` (obrigatório) - namespace do Kubernetes. Se omitido, cai no
  fallback da variável de ambiente `$K_ENV`; se nenhum dos dois existir e
  `gum` estiver instalado, pede via prompt (`gum input`).
- `[nome-do-app]` (opcional) - nome do deployment. Se omitido, cai no
  fallback de `$K_APP`; se nenhum dos dois existir e `gum` estiver
  instalado, abre um seletor com os deployments do namespace.
- `-h`/`--help` - mostra a ajuda embutida e sai (ignora `<ambiente>`).

## Descrição

1. Valida que o ambiente foi informado (direto, via `$K_ENV`, ou via prompt
   `gum input` se `gum` estiver instalado) - sem ele, sai com erro.
2. Mostra o `kubectl context` atual (`kubectl config current-context`), pra
   deixar claro em qual cluster a consulta vai rodar.
3. Resolve o app: informado direto, via `$K_APP`, ou escolhido num seletor
   `gum filter` alimentado por `kubectl get deployments -n <ambiente>`. Sem
   `gum` instalado e sem app informado, mostra um aviso com instrução de
   instalação e sai.
4. Busca via `kubectl get deployment <app> -n <ambiente> --request-timeout=10s
   -o jsonpath=...`: nome, namespace, variáveis de ambiente
   `OTEL_APP_ENV`/`OTEL_APP_VERSION` do primeiro container, e a annotation
   `last_deploy_by`. `Env`/`Version` mostram `<não configurado>` se a env
   var não existir no deployment.
5. Separa a annotation `last_deploy_by` (formato
   `<usuario>-<timestamp ISO8601>`, ex:
   `jefferson.silva-2026-03-12T19:49:17+0000`) em usuário e data/hora,
   convertendo a data pro formato `dd/mm/aaaa HH:MM:SS` (`date -j` no
   macOS, `date -d` no Linux - se a conversão falhar, mostra a data crua).
6. Imprime um resumo formatado e colorido com todos os campos acima.

Saída colorida só em terminal interativo (`[[ -t 1 ]]`) e sem `NO_COLOR`
setado - mesma convenção do resto do dev-toolbox (`deps.sh`, `install.sh`).

## Requisitos

- **Obrigatório:** `kubectl` configurado com acesso ao cluster/namespace
  consultado (contexto/kubeconfig já resolvido fora deste comando).
- **Opcional:** `gum` - usado pra pedir o ambiente (se omitido e sem
  `$K_ENV`) e pro seletor de app (se omitido e sem `$K_APP`). Sem `gum`,
  ambos os casos caem em erro/uso.

## Exemplo

```bash
$ kinfo staging minha-api

========== Detalhes do Deployment ==========
App:        minha-api
Namespace:  staging
Env:        staging
Version:    1.42.0
--------------------------------------------
Deployer:   jefferson.silva
Data/Hora:  12/03/2026 19:49:17 (BRT)
============================================
```

## Observações

- O campo `last_deploy_by` e as env vars `OTEL_APP_ENV`/`OTEL_APP_VERSION`
  são convenções específicas de quem usa este comando - deployments sem
  essa annotation/env vars aparecem com campos vazios, sem erro.
- `(BRT)` no output é só um rótulo fixo - a conversão de data usa o fuso
  local da máquina que roda o comando, não força `America/Sao_Paulo`.
