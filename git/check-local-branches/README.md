# git check-local-branches

Lista branches locais já mergeadas no remote (`origin` por padrão), com
opção de apagar as encontradas.

## Uso

```bash
git check-local-branches [--delete [--yes]] [--no-fetch] [--no-color] [--json]
```

## Descrição

Pra cada branch local (exceto a raiz `main`/`master`), verifica se o
conteúdo dela já foi integrado na branch raiz do remote, por 3 métodos
(qualquer um confirma merge):

1. **ancestor** - branch é ancestral direto da raiz (merge normal, merge
   `--ff-only`, ou merge commit preservando histórico).
2. **sem diff local** - `git cherry` mostra que todo commit da branch já
   tem equivalente (mesmo patch-id) na raiz - cobre merge via rebase que
   reaplica commit a commit.
3. **PR merged** - PR da branch (via `gh`) está com `state=MERGED` - único
   jeito confiável de detectar squash merge (1 commit novo na raiz, sem
   ancestral nem patch-id batendo com nenhum commit da branch).

Sem `gh`/`jq` instalados (ou sem login), o método 3 é pulado - branch
squash-mergeada pode aparecer como "não mergeada" nesse caso (avisa 1x em
stderr, mesmo aviso do `git chain`).

Branch com upstream remoto sumido (`git branch -vv` mostra `[gone]`) é
sinal extra, mostrado na coluna `NOTA` (não em `MOTIVO`) - não é usado
sozinho pra decidir merge, só reforça o resultado dos 3 métodos acima.

`DEFASAGEM` mostra quantos commits a branch está atrás da raiz
(`git rev-list --count <branch>..<raiz>`) - "em dia" quando 0, útil pra
saber se uma branch não-mergeada só está velha ou já ficou pra trás de
verdade.

`--delete` remove (`git branch -D`) as branches identificadas como
mergeadas. Sem `--yes`, a seleção usa `gum choose --no-limit` (espaço
marca, enter confirma) seguido de `gum confirm` pra confirmar a
deleção - exige terminal interativo e `gum` instalado, sem fallback
(erro com instrução de instalação se faltar qualquer um dos dois).
`--yes`/`-y` pula seleção/confirmação e apaga todas de uma vez, sem
precisar de `gum`. Nunca deleta a branch raiz nem a branch com checkout
no momento (protegida pelo próprio git contra deleção).

Enquanto verifica (fetch + consulta PR por branch), mostra um spinner
via `gum spin` com o texto "verificando branches locais..." (só em
terminal interativo, sem `--json`).

Roda `git fetch --all --quiet --prune` antes de comparar, a menos que
`--no-fetch` seja passado (usa o que já está local - mais rápido, pode
estar desatualizado).

## Opções

| Flag | Efeito |
|---|---|
| `--delete` | apaga as branches mergeadas encontradas (seleção via `gum` - obrigatório sem `--yes`) |
| `--yes`, `-y` | junto com `--delete`, apaga todas sem seleção/confirmação |
| `--no-fetch` | pula o `git fetch` antes de comparar |
| `--no-color` | desabilita cores (mesmo efeito de `NO_COLOR=1`) |
| `--json` | array JSON com `{name, merged, reasons, gone}` por branch (exige `jq`) |
| `-h` | mostra a ajuda embutida |

## Exemplos

```bash
$ git check-local-branches
STATUS  BRANCH                                       MOTIVO       ÚLTIMO COMMIT  DEFASAGEM         NOTA
MERGED  fix/promotions-mail-push-campaign-exclusion  [PR merged]  3 weeks ago    em dia            upstream sumiu
MERGED  chore/bump-deps                              [ancestor]   2 months ago   em dia
-       feat/promotions-autonomous-process           -            2 days ago     12 commits atrás  branch atual

$ git check-local-branches --delete
STATUS  BRANCH                                       MOTIVO
MERGED  fix/promotions-mail-push-campaign-exclusion  [PR merged] (upstream sumiu)
MERGED  chore/bump-deps                              [ancestor]
# abre gum choose - espaço marca, ENTER confirma, depois gum confirm
Deleted branch fix/promotions-mail-push-campaign-exclusion (was 621e441).

$ git check-local-branches --delete --yes
STATUS  BRANCH                                       MOTIVO
MERGED  fix/promotions-mail-push-campaign-exclusion  [PR merged] (upstream sumiu)
# --yes apaga direto, sem seleção/confirmação
Deleted branch fix/promotions-mail-push-campaign-exclusion (was 621e441).

$ git check-local-branches --json
[
  {"name": "fix/promotions-mail-push-campaign-exclusion", "merged": true,
   "reasons": ["PR merged"], "gone": true},
  {"name": "feat/promotions-autonomous-process", "merged": false,
   "reasons": [], "gone": false}
]
```

## Dependências

Reaproveita `git/chain/lib/` (`provider.sh`, `git.sh`) pra resolver a
branch raiz e consultar PR via `gh`+`jq` - mesma dependência opcional do
`git chain` (funciona sem, só perde o método 3).

`gum` é obrigatório em terminal interativo fora de `--json` - usado no
spinner de carregamento (`gum spin`) e, sem `--yes`, na
seleção/confirmação do `--delete` (`gum choose` + `gum confirm`), sem
fallback pra nenhum dos dois. `--json`/pipe e `--delete --yes` nunca
chegam a precisar dele.
