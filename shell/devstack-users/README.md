# devstack-users

Visualiza e edita detalhes de usuários no devstack via port-forward direto
aos bancos do namespace Kubernetes. Navega usuários (MySQL), subwallets e
saldos por ativo (PostgreSQL) em interface fzf interativa.

## Uso

```bash
devstack-users [namespace] [filtro]
devstack-users -n <namespace> [-f <filtro>]
devstack-users -h | --help
```

## Argumentos

| Argumento   | Descrição                                                    |
|-------------|---------------------------------------------------------------|
| `namespace` | Namespace Kubernetes (ex.: `mbpay-uat`). Interativo se omitido. |
| `filtro`    | Pré-filtra a lista de usuários ao abrir. Opcional.             |

## Flags

| Flag                | Descrição                     |
|---------------------|--------------------------------|
| `-n`, `--namespace`  | Namespace Kubernetes.          |
| `-f`, `--filter`     | Filtro inicial do fzf.         |
| `-h`, `--help`       | Mostra esta ajuda.             |

## Variáveis de ambiente

| Variável     | Equivalente a          |
|--------------|-------------------------|
| `NAMESPACE`  | argumento `namespace`   |
| `USER_INPUT` | argumento `filtro`      |

## Navegação

**Nível 1 — Usuários**
- `ENTER` — abre subwallets do usuário selecionado
- `CTRL-E` — edita Nome / Email / PIN / Palavra Segura do usuário (`UPDATE` no MySQL)
- `ESC` — encerra o comando

**Nível 2 — Subwallets**
- `ENTER` — exibe saldos da subwallet selecionada
- `ESC` — volta para usuários

**Nível 3 — Saldos**
- `CTRL-E` — edita o saldo do ativo selecionado (`UPDATE` no PostgreSQL)
- `ESC` — volta para subwallets

Todos os níveis suportam busca incremental por qualquer campo visível.

## Requisitos

- `kubectl` configurado para o contexto `gke_mb-dev-277014_us-east4-a_mb-dev-gke`.
- `psql` (cliente PostgreSQL, conecta em `127.0.0.1:5433`).
- `mysql` (cliente MySQL, conecta em `127.0.0.1:3307`).
- `fzf` — obrigatório pro dev-toolbox como um todo (`deps.sh` instala/atualiza
  junto com jq/gum/glow, sem perguntar).
- Portas locais `5433` e `3307` livres antes de executar (o comando sobe
  `kubectl port-forward` nelas e derruba ao sair).

## Observações

- Comando específico do devstack MB (credenciais fixas de banco de dev:
  `postgres:secret` no PostgreSQL, `root:secret` no MySQL) — não aponta
  pra nenhum ambiente de produção.
- `dtb_check_cluster` (`shell/_lib/kubernetes.sh`) recusa rodar fora do
  contexto kubectl do devstack (`gke_mb-dev-277014_us-east4-a_mb-dev-gke`),
  como trava de segurança contra apontar sem querer pra outro cluster.
- Checagens de `kubectl`/cluster/namespace vêm de `shell/_lib/kubernetes.sh`
  e de cliente psql/mysql de `shell/_lib/db-clients.sh` - compartilhadas,
  não duplicadas em `impl.sh`.
- A lógica roda em `impl.sh` como processo separado (não sourced) — os
  dois `kubectl port-forward` ficam em background durante toda a sessão
  fzf, e `trap cleanup EXIT` garante que morrem ao sair (normal, erro ou
  Ctrl-C). Ver comentário no topo de `script.sh` pro porquê disso.
