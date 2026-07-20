# update

Atualiza o próprio dev-toolbox (git pull + re-instala se mudou), pacotes do
sistema e ferramentas de dev instaladas na máquina, uma por uma, pulando
qualquer uma que não esteja presente.

## Uso

```bash
update
update --only-dev-toolbox
update -h | --help
```

`--only-dev-toolbox` roda só o bloco de git pull + reinstala do próprio
dev-toolbox, pulando pacotes do sistema e demais ferramentas (não pede
`sudo`).

## Descrição

Pede a senha do `sudo` uma vez no início (`sudo -v`) e roda em sequência,
cada bloco só se o binário correspondente existir na máquina
(`command -v <bin>`):

- **dev-toolbox** - `git pull --ff-only` no próprio repo, depois roda
  `install.sh` de novo (idempotente, pega novos aliases/scripts do
  MANIFEST.json mesmo sem mudança); se houver alterações locais não
  commitadas o pull falha e o comando avisa e segue com o resto
- **APT** (`apt update && apt upgrade`) - sempre roda, sem checagem prévia;
  o `apt update` dessa etapa é reaproveitado pelos blocos `--only-upgrade`
  mais abaixo (VS Code, Sublime, Podman, GitHub CLI), que não repetem o
  `update`.
- **Homebrew** (`brew update && brew upgrade`)
- **UV** (`uv self update`)
- **Poetry** (`poetry self update`)
- **Mise** (`mise self-update -y`)
- **Flatpak** (`flatpak update -y`)
- **Snap** (`snap refresh`)
- **Aqua** (`aqua upa`)
- **Google Cloud SDK** (`gcloud components update --quiet`)
- **Rustup** (`rustup update`)
- **Pipx** (`pipx upgrade-all`)
- **Cursor** - checa o `ETag` remoto do `.deb` contra um cache em
  `/tmp/.dev-toolbox-cursor-etag`; só baixa/instala se mudou (senão avisa
  que já está atualizado)
- **VS Code** (`apt install --only-upgrade code`)
- **Sublime Text** (`apt install --only-upgrade sublime-text`)
- **Podman** (`apt install --only-upgrade podman`)
- **GitHub CLI** (`apt install --only-upgrade gh`) + extensões
  (`gh extension upgrade --all`)
- **Docker Desktop** - checa se já está na última versão
  (`docker desktop update -k`); se não estiver, baixa o `.deb`, para o
  serviço (`systemctl --user stop docker-desktop`), instala e reinicia o
  serviço
- **Mac App Store** (`mas upgrade`) - só no macOS, requer
  [`mas`](https://github.com/mas-cli/mas) instalado (`brew install mas`)
- **Limpeza** (`apt autoremove -y && apt autoclean`) - roda por último, tira
  pacotes órfãos deixados pelos upgrades acima

## Requisitos

- **Obrigatório:** `bash`/`zsh`, `sudo`.
- **Opcional:** cada ferramenta listada acima só é atualizada se já estiver
  instalada (`command -v`) - nenhuma delas é instalada do zero por este
  comando.

## Compatibilidade Ubuntu/Debian x macOS

Detecta o SO via `uname -s` e ajusta os blocos que dependem de gerenciador
de pacote nativo:

- **Ubuntu/Debian** (`apt` presente): roda o bloco `apt update/upgrade`
  inicial, os blocos `apt install --only-upgrade` de VS Code/Sublime
  Text/Podman/GitHub CLI, o Cursor via `.deb` (com cache de `ETag`), o
  Docker Desktop via `.deb`+`systemctl --user`, e a limpeza final
  (`apt autoremove`/`autoclean`).
- **macOS**: nenhum desses blocos roda (não fazem sentido sem `apt`/`dpkg`/
  `systemctl`) - o bloco **Homebrew** cobre VS Code, Sublime Text, Podman,
  GitHub CLI, Cursor e Docker Desktop automaticamente, **desde que
  instalados via `brew`/`brew install --cask`** (o `brew upgrade` do topo já
  atualiza formulas e casks juntos). Instalação manual (fora do Homebrew)
  dessas ferramentas no Mac não é coberta por este comando.
- **Multiplataforma independente de `apt`**: Homebrew, UV, Poetry, Mise,
  Rustup, Pipx, Google Cloud SDK e as extensões do GitHub CLI
  (`gh extension upgrade --all`) rodam em qualquer SO onde o binário exista.
- **Exclusivo do macOS**: Mac App Store via `mas upgrade` (requer `mas`
  instalado - sem CLI oficial da Apple pra isso).
- Flatpak/Snap/Aqua são Linux-only na prática (`command -v` simplesmente não
  encontra o binário no Mac).

## Observações

- Não é idempotente no sentido de "seguro rodar sempre sem custo": a
  maioria dos blocos dispara download/instalação de verdade a cada chamada
  (Cursor e Docker Desktop são exceção - checam antes de baixar).
