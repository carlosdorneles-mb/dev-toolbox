# dev-toolbox

Aliases de git e de shell (bash/zsh) compartilhados entre devs. Clone único
local + `git pull` pra atualizar - sem copiar arquivo, sem reinstalar pacote.

## Instalar

### Via curl (recomendado)

```bash
curl -fsSL https://raw.githubusercontent.com/carlosdorneles-mb/dev-toolbox/main/bootstrap.sh | bash
```

Clona o repo em `~/.dev-toolbox` (ou `$DEV_TOOLBOX_DIR`, se setado) e abre um
menu pra escolher quais itens instalar.

**Com [`fzf`](https://github.com/junegunn/fzf) instalado** (mesmo binário em
mac - `brew install fzf` - e linux - `apt`/`pacman`/etc.), o menu vira um
checklist navegável:

```
dev-toolbox> 
> chain                          Shows the branch chain (PR stack) from current to main
  2/2
TAB: marca/desmarca | CTRL-A: marca tudo | CTRL-D: desmarca tudo | ENTER: confirma | ESC: mantem selecao atual
```

Navega com as setas, `TAB` marca/desmarca, `CTRL-A`/`CTRL-D` marca/desmarca
tudo, `ENTER` confirma, `ESC` cancela (mantém a seleção anterior).

**Sem `fzf`**, cai num prompt simples por número:

```
dev-toolbox - itens disponíveis:

   1) chain      Shows the branch chain (PR stack) from current to main

Números dos itens que deseja instalar (separados por vírgula):
```

Digite os números desejados (`1 3` ou `1,3`), ou só `enter` pra manter a
seleção atual (na primeira instalação, tudo vem pré-marcado).

Rodar o mesmo comando de novo no futuro **atualiza** (git pull) e reabre a
seleção - serve tanto pra sincronizar quanto pra ligar/desligar itens.

### Local (clone próprio, sem curl)

```bash
git clone git@github.com:carlosdorneles-mb/dev-toolbox.git ~/.dev-toolbox
cd ~/.dev-toolbox
./install.sh --interactive   # ou sem a flag pra instalar tudo direto
```

## O que o install faz

- **git**: gera `git/aliases.local.gitconfig` (gitignored) só com os aliases
  selecionados e registra ele via `include.path` no seu `~/.gitconfig` global.
  Rodar `install.sh` de novo regenera esse arquivo - ligar/desligar alias é só
  mudar a seleção e rodar de novo.
- **shell**: adiciona um `source` condicional dos arquivos de `shell/`
  selecionados no `~/.bashrc` e `~/.zshrc` (idempotente, não duplica linha).

## Itens disponíveis

| id      | tipo | descrição                                                        |
|---------|------|-------------------------------------------------------------------|
| `chain` | git  | `git chain` - mostra a cadeia de branches (stack de PRs) até main. Requer `gh` autenticado pra exibir número/status de PR (funciona sem, só com hierarquia de branches). Ver [`git/chain/README.md`](git/chain/README.md). |

`MANIFEST` é a fonte da verdade que o install lê (em inglês, formato fixo).

## Estrutura

Cada alias/script mora no próprio diretório, com implementação, fragment de
config e README dedicado lado a lado:

```
dev-toolbox/
├── bootstrap.sh                  # entrypoint do curl - clona/atualiza + chama install.sh
├── install.sh                    # instala/atualiza (local ou via bootstrap), --interactive p/ seleção
├── MANIFEST                      # catálogo dos itens instaláveis (id|type|path|entry|description)
├── git/
│   ├── aliases.local.gitconfig   # GERADO, gitignored - não editar a mão
│   └── chain/                    # um dir por alias git
│       ├── script.sh             # implementação
│       ├── alias.gitconfig       # `chain = !bash {{ROOT}}/git/chain/script.sh`
│       └── README.md             # doc dedicada do alias
└── shell/
    └── <id>/                     # (a criar) mesmo padrão: script.sh/aliases.sh + README.md
```

## Adicionar um alias novo

**git:**
1. Criar `git/<id>/` com `script.sh` (implementação) e `README.md` (doc do alias).
2. `git/<id>/alias.gitconfig` com `<nome> = !bash {{ROOT}}/git/<id>/script.sh`.
3. Linha nova em `MANIFEST`: `<id>|git|git/<id>/alias.gitconfig|<nome>|<description>`.
4. `./install.sh` pra sincronizar local (ou pull + `./install.sh --interactive` em outra máquina).

**shell:**
1. Criar `shell/<id>/` com `aliases.sh` (funções/aliases) e `README.md`.
2. Linha nova em `MANIFEST`: `<id>|shell|shell/<id>/aliases.sh|<nome>|<description>`.
3. `./install.sh` de novo.

> Limitação conhecida: desmarcar um item **shell** já instalado não remove a
> linha de `source` do `.bashrc`/`.zshrc` sozinho (o item git some do arquivo
> gerado automaticamente, o shell hoje não). Remover a mão se precisar - sem
> uso real disso ainda, revisitar quando houver mais de um item shell.
