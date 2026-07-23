# dev-toolbox — orientação para agentes e contribuidores

Toolbox de aliases de **git** e de **shell** (bash/zsh) compartilhados entre
devs. Um clone único por máquina (`~/.dev-toolbox` via `bootstrap.sh`, ou
clone manual) + `git pull` pra atualizar - nada de copiar arquivo ou
reinstalar pacote a cada mudança. Detalhes de uso em [`README.md`](README.md).

## Idioma

- Documentação (`README.md`, `*/README.md`) e mensagens interativas
  (`echo`, prompts) em **português**.
- **Acentuação obrigatória (CRÍTICO):** todo texto em português - docs,
  comentários, mensagens de `echo`/prompt - usa acentuação correta
  (não → nao é erro). Nunca escrever PT-BR sem acento pra "economizar" ou
  por hábito de script ASCII-only; UTF-8 é seguro em `.sh`/`.md`/`echo`.
- `catalog.json` em **inglês** (campos `description` em inglês).
- Comentários dentro dos scripts `.sh`: seguir o idioma já predominante no
  arquivo (a maioria está em português - ver `git/chain/script.sh`).
- Commits em **inglês**, [Conventional Commits](https://www.conventionalcommits.org/).

## Estrutura

Cada alias/script mora no próprio diretório — implementação, fragment de
config e README lado a lado:

```
dev-toolbox/
├── bootstrap.sh                  # entrypoint via curl: clona/atualiza ~/.dev-toolbox + chama install.sh --interactive
├── install.sh                    # instala/atualiza (local ou via bootstrap); --interactive p/ seleção granular
├── uninstall.sh                  # inverso do install.sh - remove entradas deste clone do ~/.gitconfig e ~/.bashrc/~/.zshrc
├── deps.sh                       # verifica/instala dependências externas (jq, gum, gh); chamado pelo install.sh
├── catalog.json                 # catálogo dos itens instaláveis: array de {id,type,path,entry,description}
├── git/
│   ├── aliases.local.gitconfig   # GERADO por install.sh, gitignored - nunca editar a mão nem commitar
│   └── <id>/                     # um dir por alias git
│       ├── script.sh             # implementação
│       ├── alias.gitconfig       # `<nome> = !bash {{ROOT}}/git/<id>/script.sh` (placeholder {{ROOT}} substituído no install)
│       └── README.md             # doc dedicada do alias (uso, flags, exemplos)
└── shell/
    ├── aliases.local.sh          # GERADO por install.sh, gitignored - nunca editar a mão nem commitar
    ├── _lib/                     # bibliotecas compartilhadas - NÃO é item instalável, fora do catalog.json
    │   └── log.sh                # cores/log padronizados (dtb_log_step/ok/warn/skip/err/banner)
    └── <id>/                     # mesmo padrão pra aliases/funções de shell (ex: shell/aliases/)
        ├── script.sh
        └── README.md
```

## Convenções ao adicionar um item novo

**git:**
1. Criar `git/<id>/script.sh` (implementação) e `git/<id>/README.md` (uso, flags, exemplos — mesmo nível de detalhe do `git/chain/README.md`).
2. Criar `git/<id>/alias.gitconfig` com uma linha: `<nome> = !bash {{ROOT}}/git/<id>/script.sh`.
3. Adicionar entrada no array de `catalog.json`: `{"id": "<id>", "type": "git", "path": "git/<id>/alias.gitconfig", "entry": "<nome>", "description": "<description em inglês>"}`.
4. Se o script exigir binário externo novo (além de jq/gum/gh já cobertos), adicionar uma linha no array `DEPS` de `deps.sh`.
5. Rodar `./install.sh` local pra validar antes de commitar.

**shell:**
1. Criar `shell/<id>/script.sh` e `shell/<id>/README.md`.
2. Entrada no `catalog.json`: `{"id": "<id>", "type": "shell", "path": "shell/<id>/script.sh", "entry": "<nome>", "description": "<description>"}`.
3. Pra log/cor no script: `source "{{ROOT}}/shell/_lib/log.sh"` no início da função e usar `dtb_log_step/ok/warn/skip/err/banner` — não redefinir `RED`/`GREEN`/`NO_COLOR` na mão (ver [`shell/_lib/log.sh`](shell/_lib/log.sh)).
4. `./install.sh` de novo.

`install.sh` prefixa cada item shell gerado com `unalias <entry> 2>/dev/null`
antes do `script.sh` concatenado - defesa contra o erro clássico do bash
"defining function based on alias" quando o shell do usuário (oh-my-zsh, rc
antigo etc) já tem um alias com o mesmo nome da função (`entry` no
`catalog.json`, ex: `update`, `kinfo`).

## Padrão de flags e help

Todo `script.sh` (git ou shell) que aceita opções segue a mesma forma:

1. **Parsing de flags:** `while [[ $# -gt 0 ]]; do case "$1" in ... ; shift; done`
   percorrendo `$@` — nunca `for arg in "$@"` nem checar só `${1:-}` na mão.
   Scripts sem flag real (só `-h`) ainda usam um loop pra detectar `-h`/`--help`
   em qualquer posição, mesmo com argumentos posicionais depois (ver
   `shell/kinfo/script.sh`, `shell/update/script.sh`).
2. **Função de help:** texto do `-h`/`--help` sempre numa função dedicada,
   nomeada `_dtb_help_<id>` (`<id>` = nome do diretório do item, hífen vira
   underscore — ex: `_dtb_help_fix_network`, `_dtb_help_check_local_branches`). A
   função só imprime (heredoc `cat <<'EOF' ... EOF`); quem decide
   `exit`/`return` é o caller, no case do parsing.
3. **Texto do help, mesma estrutura sempre:**
   ```
   <comando> - <descrição de uma linha>

   Uso:
     <comando> [flags] [args]

   Descrição:            (opcional — só se o comportamento não for óbvio pelo Uso:)
     <parágrafo(s)>

   Opções:
     <flag>   <explicação>
     -h       mostra esta ajuda

   Exemplos:              (opcional — só quando exemplos agregam, ex: git/chain)
     $ <comando> ...
   ```
   Ver `git/chain/script.sh` e `git/check-local-branches/script.sh` como referência
   completa (com Exemplos:); `shell/kinfo`, `shell/update`, `shell/aliases`,
   `shell/fix-network` como referência enxuta (sem Exemplos:).

## Dependências externas (`deps.sh`)

`deps.sh` checa/instala/atualiza binários externos exigidos pelos itens do
toolbox (hoje: `jq`, `gum`, `gh`) via `brew` (macOS) ou `apt-get`
(Ubuntu/Debian). A lista fica hardcoded no array `DEPS` do próprio script -
não existe arquivo de configuração externo pra isso. `jq` e `gum` são
obrigatórios - instalados sem perguntar, e se a instalação falhar
`install.sh` aborta (`set -euo pipefail`, sem fallback degradado). `gh` é
opcional - pede confirmação antes de instalar/atualizar; se o usuário
recusar, `install.sh` segue normalmente.

## Antes de commitar

- `bash -n <script>.sh` em todo script tocado (falha de sintaxe não pode chegar em `main` - quebra alias de todo mundo que rodar `install.sh`/`bootstrap.sh`).
- Rodar `shellcheck` se disponível localmente; senão pelo menos revisar manualmente `set -euo pipefail`, quoting de variáveis, e uso de `local`/escopo.
- Testar o fluxo local: `./install.sh` (idempotente) e, se mexeu em `install.sh`/`bootstrap.sh`, também `./install.sh --interactive`.
- **Sempre atualizar o `README.md` do próprio item** (`git/<id>/README.md` ou `shell/<id>/README.md`) quando a mudança alterar comportamento, flags, formato de saída ou requisitos do script - README desatualizado é pior que README ausente. Vale também pro `-h`/help embutido no próprio script, quando existir (ex: `git/chain/script.sh`) - os dois têm que contar a mesma história.
- `git/aliases.local.gitconfig` e `.installed` são gerados e gitignored — nunca commitar.

## Placeholder `{{ROOT}}`

Todo `alias.gitconfig` e `script.sh` (shell) usa `{{ROOT}}` no lugar do path
absoluto do clone. `install.sh` substitui isso via `sed` na hora de gerar
`git/aliases.local.gitconfig` e `shell/aliases.local.sh` — isso é o que
permite o mesmo repo funcionar em qualquer máquina/path de clone sem edição
manual. Nunca hardcodar path absoluto num `alias.gitconfig`/`script.sh`
versionado.

## O que evitar

- Editar `git/aliases.local.gitconfig`, `shell/aliases.local.sh` ou `.installed` a mão (são gerados; mudança se perde no próximo `install.sh`).
- Path absoluto hardcoded em `alias.gitconfig`/`script.sh` (usar sempre `{{ROOT}}`).
- Alias novo sem entrada correspondente no `catalog.json` (fica invisível pro menu interativo de `install.sh --interactive`/`bootstrap.sh`).
- Lógica de negócio pesada dentro do `install.sh`/`bootstrap.sh` — eles só orquestram (seleção, geração de config, source); a lógica do alias em si vive no `script.sh` do próprio item.
- Cor/log ad-hoc (`echo -e "\033[..."` direto ou redeclarar `RED`/`GREEN`/`NO_COLOR` local) em script novo — usar `shell/_lib/log.sh` (ver seção "Convenções" acima).
