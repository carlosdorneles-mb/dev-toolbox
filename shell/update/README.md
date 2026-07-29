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

Em terminal interativo com `gum`, pergunta antes de pedir a senha do `sudo`
(`gum confirm`) - se o usuário recusar, pula todos os blocos que exigem
`apt`/`dpkg`/`systemctl` (mostra um aviso) e atualiza só as ferramentas de
usuário (Homebrew, UV, Poetry, Mise, Flatpak, Snap, Aqua, Google Cloud SDK,
Rustup, Pipx, extensões do GitHub CLI, Mac App Store). Sem terminal
interativo ou sem `gum`, mantém o comportamento antigo: pede a senha direto
(`sudo -v`), sem perguntar.

Cada bloco roda só se o binário correspondente existir na máquina
(`command -v <bin>`), com spinner (`gum spin`) enquanto atualiza e uma
mensagem de sucesso ou erro ao final:

- **dev-toolbox** - roda o `bootstrap.sh` via `curl` (`DEV_TOOLBOX_DIR`
  apontando pro próprio clone) com a flag `--update`, que faz `git pull` e
  chama `install.sh --update` (reaplica a seleção salva em `.installed`,
  somando item novo do catalog.json - não força tudo de novo); se falhar o
  comando avisa e segue com o resto
- **APT** (`apt update && apt upgrade`) - sempre roda, sem checagem prévia;
  o `apt update` dessa etapa é reaproveitado pelos blocos `--only-upgrade`
  mais abaixo (VS Code, Sublime, Podman, GitHub CLI), que não repetem o
  `update`.
- **Homebrew** (`brew update && brew upgrade`)
- **UV** (`uv self update`)
- **Poetry** (`poetry self update`)
- **Mise** (`mise self-update -y`)
- **Flatpak** (`flatpak update -y`)
- **Snap** (`sudo snap refresh`)
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
  (`gh extension upgrade --all`) rodam em qualquer SO onde o binário exista -
  são justamente os blocos que continuam rodando quando o usuário recusa dar
  sudo (ver Descrição) - **Snap é exceção**: exige sudo mesmo sendo
  multiplataforma, então é pulado junto com os blocos `apt`/`dpkg` se o
  usuário recusar.
- **Exclusivo do macOS**: Mac App Store via `mas upgrade` (requer `mas`
  instalado - sem CLI oficial da Apple pra isso).
- Flatpak/Snap/Aqua são Linux-only na prática (`command -v` simplesmente não
  encontra o binário no Mac).

## Observações

- Não é idempotente no sentido de "seguro rodar sempre sem custo": a
  maioria dos blocos dispara download/instalação de verdade a cada chamada
  (Cursor e Docker Desktop são exceção - checam antes de baixar).
