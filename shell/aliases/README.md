# aliases

Lista os aliases de shell configurados no `~/.bashrc`/`~/.zshrc` (+ os do
dev-toolbox) e os aliases de git, numa tabela indicando de onde cada um vem.

## Uso

```bash
aliases
aliases -r | --run
aliases --only-dev-toolbox
aliases -h | --help
```

## Descrição

Junta duas fontes numa tabela só:

- **Aliases de shell** (bash/zsh) - via `alias` (builtin).
- **Aliases de git** - via `git config --show-origin --get-regexp '^alias\.'`.

Colunas: `TIPO` (`shell`/`git`), `NOME`, `FONTE`, `COMANDO`.

### Coluna FONTE

- **git**: origem exata, sem heurística - `git config --show-origin` diz o
  arquivo real de onde o alias veio. Se for o `git/aliases.local.gitconfig`
  gerado pelo `install.sh`, aparece como `dev-toolbox`; senão, o path do
  `.gitconfig` real (útil pra achar duplicata entre `~/.gitconfig` e um
  `include.path` esquecido, por exemplo).
- **shell**: o builtin `alias` não guarda origem, então a fonte é melhor
  esforço - procura a definição só no `shell/aliases.local.sh` gerado pelo
  dev-toolbox, no `~/.bashrc` e no `~/.zshrc`. Se vier do arquivo gerado do
  dev-toolbox, aparece como `dev-toolbox`; se achar em `~/.bashrc`/`~/.zshrc`,
  mostra o path. Alias que não aparece em nenhum dos três (definido por
  plugin/framework, ex: oh-my-zsh) fica de fora da tabela - o objetivo é
  mostrar o que foi configurado nesses arquivos, não todo alias ativo na
  sessão.

## Menu executável (`-r`/`--run`)

Abre um seletor `fzf` com NOME + COMANDO de cada alias; ao escolher um e
apertar ENTER, executa na hora - alias `git` roda como `git <nome>`, alias
de shell roda via `eval` do comando (mesmo texto que aparece na tabela).
ESC cancela sem executar nada. Requer `fzf` instalado (ver `deps.sh`).

## `--only-dev-toolbox`

Filtra a tabela (ou o menu do `-r`/`--run`) só pros aliases com
FONTE=dev-toolbox, escondendo os de `~/.bashrc`/`~/.zshrc`/`~/.gitconfig`.

## Requisitos

Nenhuma dependência externa pra listagem - só `bash`/`zsh`, `awk` e `git`
(esse último só pra listar os aliases de git; sem ele, a tabela sai só com
os de shell). O `-r`/`--run` precisa de `fzf` instalado.

## Exemplo

```
$ aliases
TIPO   NOME     FONTE        COMANDO
shell  ll       dev-toolbox  ls -la
shell  gs       ~/.zshrc     git status
git    chain    dev-toolbox  !bash /home/user/.dev-toolbox/git/chain/script.sh
git    l        ~/.gitconfig log --oneline --graph
```
