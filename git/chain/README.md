# git chain

Mostra a cadeia de branches (stack de PRs) da branch atual até a `main`.

![exemplo do git chain](assets/chain.png)

## Uso

```bash
git chain [--no-color] [--inline] [--no-pr]
```

## Descrição

Percorre a branch atual até a branch raiz (`main`/`master`, ou a default
branch do remote), resolvendo o parent de cada branch pela base declarada da
PR (`gh pr view --json baseRefName`). Sem PR aberta, cai no fallback:
branch com merge-base mais recente que não seja a própria ponta da branch
atual (evita confundir filho/irmão com parent real).

Pra cada branch na cadeia mostra, quando aplicável:

| Marca | Significado |
|---|---|
| `#NNN` | número da PR, clicável em terminais com suporte a hyperlink OSC 8 (iTerm2, kitty, VSCode, gnome-terminal) |
| `▲N` | N commits locais não enviados pro remote (unpushed) |
| `▼N` | N commits no remote ainda não trazidos (não pulled) |
| `[X]` | branch sem remote (nunca deu push) |
| `[só remoto]` | branch só existe no remote, nunca teve checkout local (achada como parent via PR ou heurística) |
| `[draft]` | PR ainda em draft |
| `[merged]` | PR dessa branch já foi mergeada |
| `[closed sem merge]` | PR foi fechada sem merge (abandonada) |
| `[PR CONFLICTING]` | PR aberta tem conflito de merge |
| `[✓N]` | PR aberta tem N approvals (1 por revisor, só a revisão mais recente de cada um conta) |
| `[blocked]` | PR aberta bloqueada pra merge (checks/aprovação faltando, branch protection etc) |
| `[REBASE\|MERGE\|CHERRY-PICK\|BISECT IN PROGRESS]` | branch atual com uma dessas operações em andamento |
| `[dirty working tree]` | branch atual tem mudanças trackeadas não commitadas (untracked não conta) |

PR fechada sem merge (`CLOSED`) não é usada como fonte do parent na cadeia -
só PR aberta ou já mergeada são confiáveis pra isso; `CLOSED` cai no
fallback heurístico (a branch pode ter seguido outro rumo).

Roda `git fetch origin --quiet` antes de comparar ahead/behind, então os
números refletem o estado real do remoto no momento da execução.

Se a cadeia não conseguir chegar até a raiz (parent não resolvido nem por PR
nem pela heurística), imprime um aviso em stderr e mostra a cadeia truncada
até onde conseguiu.

Saída colorida (bold no HEAD/main, cyan no `#PR`, amarelo `▲`, vermelho
`▼`/`[X]`) quando rodado em terminal interativo; sem cor se a saída for
redirecionada/pipada. O link OSC 8 do `#PR` só é emitido em terminal
interativo (nunca em saída redirecionada/pipada, mesmo com cor).

## Opções

| Flag | Efeito |
|---|---|
| `-h` | mostra a ajuda embutida no script |
| `--no-color` | desabilita cores (mesmo efeito de `NO_COLOR=1`) |
| `--inline` | mostra a cadeia em uma linha só (com setas `→`) em vez do modo árvore (padrão, raiz no topo) |
| `--no-pr` | esconde tudo relacionado a PR (`#NNN`, draft, merged, closed, conflicting, approvals, blocked) - só a hierarquia de branches + ahead/behind/`[X]`. A cadeia continua usando o `gh` por baixo dos panos pra resolver o parent correto, só a exibição fica mais limpa |

> `git chain --help` não funciona - o git intercepta `--help` para qualquer
> alias e imprime só a definição dele, sem executar. Use `-h`.

## Requisitos

- **Obrigatório:** `git` (uso local do repo) e `bash`.
- **Opcional:** `gh` CLI autenticado + `jq` (usado só pra parsear a saída do
  `gh`). Sem os dois, `git chain` funciona igual, mostrando só a hierarquia
  local de branches (sem número/status de PR). Se `gh` estiver ausente, o
  script pula essas chamadas e nunca invoca `jq` - por isso os dois são
  opcionais juntos, não um sem o outro.

## Exemplos

```bash
$ git chain
main
└─ branch-base #767
   └─ minha-branch #768 (▼6)

# modo uma linha só (main primeiro, igual árvore)
$ git chain --inline
main (▼6) → branch-base #767 → minha-branch #768

# sem cores (--no-color equivale a NO_COLOR=1)
$ git chain --no-color
main
└─ branch-base #767
   └─ minha-branch #768 (▼6)
```
