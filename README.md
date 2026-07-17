# dev-toolbox

Aliases de git e de shell (bash/zsh) compartilhados entre devs. Clone único
local + `git pull` pra atualizar - sem copiar arquivo, sem reinstalar pacote.

## Instalar

### Via curl (recomendado)

```bash
curl -fsSL https://raw.githubusercontent.com/carlosdorneles-mb/dev-toolbox/main/bootstrap.sh | bash
```

Pra instalar **tudo direto, sem menu** (ex: provisionamento automatizado):

```bash
curl -fsSL https://raw.githubusercontent.com/carlosdorneles-mb/dev-toolbox/main/bootstrap.sh | bash -s -- --all
```

Clona o repo em `~/.dev-toolbox` (ou `$DEV_TOOLBOX_DIR`, se setado) e abre um
menu pra escolher quais itens instalar.

**Com [`fzf`](https://github.com/junegunn/fzf) instalado** (mesmo binário em
mac - `brew install fzf` - e linux - `apt`/`pacman`/etc.), o menu vira um
checklist navegável:

```
dev-toolbox> 
> chain                          Shows the branch chain (PR stack) from current to main
  aliases                        Lists all shell and git aliases in a table, showing their source
  update                         Updates system packages and installed dev tools (apt/brew/uv/poetry/mise/flatpak/snap/aqua/gcloud/rustup/pipx/cursor/vscode/sublime/podman/gh+extensions/docker desktop/mas), cross-platform Ubuntu+macOS via uname detection, plus apt autoremove/autoclean cleanup, skipping any not installed
  kinfo                          Shows Kubernetes deployment details (namespace, env, version, last deployer+timestamp) for an app, with an fzf picker when the app name is omitted
  fix-network                    Fixes network instability, cross-platform Ubuntu+macOS via uname detection: optionally disables IPv6 (nmcli/networksetup) and flushes DNS cache (resolvectl/dscacheutil), restarts NetworkManager and Netskope (stagentd) if present (Linux only)
  5/5
TAB: marca/desmarca | CTRL-A: marca tudo | CTRL-D: desmarca tudo | ENTER: confirma | ESC: mantem selecao atual
```

Navega com as setas, `TAB` marca/desmarca, `CTRL-A`/`CTRL-D` marca/desmarca
tudo, `ENTER` confirma, `ESC` cancela (mantém a seleção anterior).

**Sem `fzf`**, cai num prompt simples por número:

```
dev-toolbox - itens disponíveis:

   1) chain      Shows the branch chain (PR stack) from current to main
   2) aliases    Lists all shell and git aliases in a table, showing their source
   3) update     Updates system packages and installed dev tools (apt/brew/uv/poetry/mise/flatpak/snap/aqua/gcloud/rustup/pipx/cursor/vscode/sublime/podman/gh+extensions/docker desktop/mas), cross-platform Ubuntu+macOS via uname detection, plus apt autoremove/autoclean cleanup, skipping any not installed
   4) kinfo      Shows Kubernetes deployment details (namespace, env, version, last deployer+timestamp) for an app, with an fzf picker when the app name is omitted
   5) fix-network Fixes network instability, cross-platform Ubuntu+macOS via uname detection: optionally disables IPv6 (nmcli/networksetup) and flushes DNS cache (resolvectl/dscacheutil), restarts NetworkManager and Netskope (stagentd) if present (Linux only)

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

## Desinstalar

```bash
./uninstall.sh   # ou: make uninstall
```

Remove do `~/.gitconfig` o `include.path` deste clone, a linha de source do
`~/.bashrc`/`~/.zshrc`, os arquivos gerados e o `.installed`. Idempotente -
rodar de novo sem erro se já tiver sido desinstalado.

Só afeta entradas apontando pra **este** clone (este path). Se o dev-toolbox
já foi instalado a partir de mais de um clone/path (ex: `~/.dev-toolbox` e um
clone local em paralelo, ou um path antigo que já foi movido/apagado), cada
um deixa sua própria entrada em `~/.gitconfig`/`~/.bashrc`/`~/.zshrc` - rode
`./uninstall.sh` a partir de cada um pra limpar tudo, ou edite os arquivos a
mão removendo as linhas correspondentes. É a causa mais comum de alias
duplicado (ex: `git chain` aparecendo mais de uma vez).

## Dependências

Alguns itens exigem `jq`, `fzf` e/ou `gh` instalados. `install.sh` roda
`deps.sh` automaticamente antes de instalar/atualizar - ele detecta o que já
está presente (e a versão), instala o que falta e atualiza o que estiver
abaixo da versão mínima exigida. Suporta **macOS** (via `brew`) e
**Ubuntu/Debian** (via `apt-get`, incluindo o repo oficial do `gh` quando
necessário).

Pra só checar sem instalar nada:

```bash
./deps.sh --check-only
```

## O que o install faz

- **git**: gera `git/aliases.local.gitconfig` (gitignored) só com os aliases
  selecionados e registra ele via `include.path` no seu `~/.gitconfig` global.
  Rodar `install.sh` de novo regenera esse arquivo - ligar/desligar alias é só
  mudar a seleção e rodar de novo.
- **shell**: gera `shell/aliases.local.sh` (gitignored) só com os itens
  selecionados e garante um `source` desse arquivo único no `~/.bashrc` e
  `~/.zshrc` (idempotente, não duplica linha). Mesmo padrão do git -
  desmarcar um item some do arquivo gerado automaticamente, sem precisar
  editar o rc file a mão.

## Itens disponíveis

| id        | tipo  | descrição                                                        |
|-----------|-------|-------------------------------------------------------------------|
| `chain`   | git   | `git chain` - mostra a cadeia de branches (stack de PRs) até main. Requer `gh` autenticado pra exibir número/status de PR (funciona sem, só com hierarquia de branches). Ver [`git/chain/README.md`](git/chain/README.md). |
| `aliases` | shell | `aliases` - lista todos os aliases (shell + git) numa tabela, mostrando de onde cada um vem. `-r`/`--run` abre um menu `fzf` pra escolher e executar um na hora; `--only-dev-toolbox` filtra só os deste repo. Ver [`shell/aliases/README.md`](shell/aliases/README.md). |
| `update`  | shell | `update` - atualiza pacotes do sistema e ferramentas de dev instaladas (apt, brew, uv, poetry, mise, flatpak, snap, aqua, gcloud, rustup, pipx, cursor, vscode, sublime, podman, gh + extensões, docker desktop, mas), com detecção de SO (Ubuntu/Debian x macOS via `uname`) pra rodar só o que faz sentido em cada um, roda `apt autoremove`/`autoclean` no fim (Linux), pulando qualquer uma ausente. Ver [`shell/update/README.md`](shell/update/README.md). |
| `kinfo`   | shell | `kinfo <ambiente> [app]` - mostra detalhes de um deployment no Kubernetes (namespace, env, versão, quem/quando fez o último deploy). Com `fzf` instalado e o app omitido, abre um seletor com os deployments do namespace. Requer `kubectl` configurado. Ver [`shell/kinfo/README.md`](shell/kinfo/README.md). |
| `fix-network` | shell | `fix_network` - ajusta a rede em caso de instabilidade (desativa IPv6 opcional, limpa cache de DNS opcional, reinicia NetworkManager+Netskope no Linux), cross-platform Ubuntu+macOS via `uname` - restart de rede/Netskope só roda no Linux. Ver [`shell/fix-network/README.md`](shell/fix-network/README.md). |

`MANIFEST` é a fonte da verdade que o install lê (em inglês, formato fixo).

## Estrutura

Cada alias/script mora no próprio diretório, com implementação, fragment de
config e README dedicado lado a lado:

```
dev-toolbox/
├── bootstrap.sh                  # entrypoint do curl - clona/atualiza + chama install.sh
├── install.sh                    # instala/atualiza (local ou via bootstrap), --interactive p/ seleção
├── deps.sh                       # verifica/instala dependências externas (jq, fzf, gh) - chamado pelo install.sh
├── MANIFEST                      # catálogo dos itens instaláveis (id|type|path|entry|description)
├── git/
│   ├── aliases.local.gitconfig   # GERADO, gitignored - não editar a mão
│   └── chain/                    # um dir por alias git
│       ├── script.sh             # implementação
│       ├── alias.gitconfig       # `chain = !bash {{ROOT}}/git/chain/script.sh`
│       └── README.md             # doc dedicada do alias
└── shell/
    ├── aliases.local.sh          # GERADO, gitignored - não editar a mão
    ├── _lib/log.sh               # cores/log compartilhados - não é item instalável
    └── aliases/                  # um dir por alias/função de shell
        ├── script.sh             # implementação (`aliases() { ... }`)
        └── README.md             # doc dedicada do alias
```

## Adicionar um alias novo

**git:**
1. Criar `git/<id>/` com `script.sh` (implementação) e `README.md` (doc do alias).
2. `git/<id>/alias.gitconfig` com `<nome> = !bash {{ROOT}}/git/<id>/script.sh`.
3. Linha nova em `MANIFEST`: `<id>|git|git/<id>/alias.gitconfig|<nome>|<description>`.
4. `./install.sh` pra sincronizar local (ou pull + `./install.sh --interactive` em outra máquina).

**shell:**
1. Criar `shell/<id>/` com `script.sh` (função/alias, pode usar `{{ROOT}}`) e `README.md`.
2. Linha nova em `MANIFEST`: `<id>|shell|shell/<id>/script.sh|<nome>|<description>`.
3. `./install.sh` pra sincronizar.
