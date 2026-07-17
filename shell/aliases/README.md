# aliases

Lista os aliases de shell configurados no `~/.bashrc`/`~/.zshrc` (+ os do
dev-toolbox) e os aliases de git, numa tabela indicando de onde cada um vem.

## Uso

```bash
aliases
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

## Requisitos

Nenhuma dependência externa - só `bash`/`zsh`, `awk` e `git` (esse último só
pra listar os aliases de git; sem ele, a tabela sai só com os de shell).

## Exemplo

```
$ aliases
TIPO   NOME     FONTE        COMANDO
shell  ll       dev-toolbox  ls -la
shell  gs       ~/.zshrc     git status
git    chain    dev-toolbox  !bash /home/user/.dev-toolbox/git/chain/script.sh
git    l        ~/.gitconfig log --oneline --graph
```
