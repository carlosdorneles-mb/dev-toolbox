# git check-remote-branches

Lista as branches remotas de um repo GitHub - via API (`gh`), sem clone ou
fetch local - com status de merge/PR, autoria e idade, e permite apagar as
encontradas.

## Uso

```bash
git check-remote-branches [org/repo|URL] [--delete [--yes]] [--stale-days N] [--only-merged] [--only-stale] [--json] [--no-color]
```

## Descrição

Pra cada branch remota do repo (exceto a branch default), resolve:

- **status de merge**: existe PR com `state=MERGED` apontando essa branch?
- **PR aberta**: existe PR com `state=OPEN` apontando essa branch?
- **autoria/idade**: primeiro commit único da branch (vs a default) = quem
  criou/quando (aproximado, via `compare` da API - o GitHub não expõe
  criação de branch diretamente); último commit = quem atualizou por
  último/quando.
- **stale**: último commit mais antigo que `--stale-days` (default: 90).

Em terminal (não `--json`), `BRANCH` e `[PR #N]`/`[PR aberta #N]` saem como
hyperlink clicável (OSC 8) - `BRANCH` abre a branch no GitHub, o PR abre a
página da PR. Terminal sem suporte a OSC 8 mostra o texto normal, sem
sequência de escape visível.

Complementa o `git check-local-branches` (que analisa branches *locais* já
mergeadas usando objetos git locais) - esse aqui cobre branches que existem
só no GitHub e nunca foram trazidas pro clone de ninguém.

### Resolução do repo

1. Argumento posicional (`org/repo` ou URL do GitHub).
2. Sem argumento, dentro de um repo git com remote GitHub - detecta pelo
   diretório atual.
3. Sem argumento e fora de um repo git (ou detecção falhou) - pergunta
   interativamente.

100% via API remota - nunca faz `git fetch`/`clone`/leitura de objetos git
locais, roda de qualquer diretório.

### Deleção

`--delete` apaga as branches candidatas: por padrão, mergeadas **ou**
stale sem PR aberta (união dos dois grupos). `--only-merged`/`--only-stale`
restringem a candidatura a só um dos grupos. Sem `--yes`, a seleção usa
`gum choose --no-limit` (espaço marca, enter confirma) seguido de
`gum confirm` pra confirmar a deleção - exige terminal interativo e `gum`
instalado, sem fallback (erro com instrução de instalação se faltar
qualquer um dos dois). `--yes`/`-y` pula seleção/confirmação e apaga
todas de uma vez, sem precisar de `gum`. Branch default e branches
`protected` nunca entram como candidatas.

## Opções

| Flag | Efeito |
|---|---|
| `--delete` | apaga as branches candidatas encontradas (seleção via `gum` - obrigatório sem `--yes`) |
| `--yes`, `-y` | junto com `--delete`, apaga todas sem seleção/confirmação |
| `--stale-days N` | idade em dias do último commit acima da qual marca "stale" (default: 90) |
| `--only-merged` | mostra/considera só branches mergeadas |
| `--only-stale` | mostra/considera só branches stale |
| `--no-color` | desabilita cores (mesmo efeito de `NO_COLOR=1`) |
| `--json` | array JSON com `{name, protected, merged, pr_number, pr_url, pr_state, created_by, created_at, updated_by, updated_at, stale}` por branch (exige `jq`) |
| `-h` | mostra a ajuda embutida |

## Exemplos

```bash
$ git check-remote-branches org/repo
STATUS               BRANCH             CRIADA POR  ATUALIZADA POR  IDADE            FLAGS
MERGED [PR #120]     fix/old-bugfix     joana       carlos          45 dias atrás
- [PR aberta #130]   feat/wip-thing     carlos      carlos          2 dias atrás
- [sem PR]           chore/abandoned    pedro       pedro           210 dias atrás   ⚠ stale

$ git check-remote-branches org/repo --only-merged --delete
STATUS            BRANCH          CRIADA POR  ATUALIZADA POR  IDADE
MERGED [PR #120]  fix/old-bugfix  joana       carlos          45 dias atrás
# abre gum choose - espaço marca, ENTER confirma, depois gum confirm
Deleted branch fix/old-bugfix (remote: org/repo).
```

## Dependências

`gh` (autenticado, `gh auth login`) e `jq` são dependências obrigatórias -
todo caminho de código parseia JSON de resposta da API. `gum` é
obrigatório em terminal interativo fora de `--json` - usado no spinner de
carregamento (`gum spin`) e, sem `--yes`, na seleção/confirmação do
`--delete` (`gum choose` + `gum confirm`), sem fallback pra nenhum dos
dois. `--json`/pipe e `--delete --yes` nunca chegam a precisar dele.
