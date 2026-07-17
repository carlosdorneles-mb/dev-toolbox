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
- `MANIFEST` em **inglês** (formato fixo, tabular, decisão deliberada).
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
├── deps.sh                       # verifica/instala dependências externas (jq, fzf, gh); chamado pelo install.sh
├── MANIFEST                      # catálogo dos itens instaláveis: id|type|path|entry|description
├── git/
│   ├── aliases.local.gitconfig   # GERADO por install.sh, gitignored - nunca editar a mão nem commitar
│   └── <id>/                     # um dir por alias git
│       ├── script.sh             # implementação
│       ├── alias.gitconfig       # `<nome> = !bash {{ROOT}}/git/<id>/script.sh` (placeholder {{ROOT}} substituído no install)
│       └── README.md             # doc dedicada do alias (uso, flags, exemplos)
└── shell/
    └── <id>/                     # mesmo padrão pra aliases/funções de shell (ainda a criar)
        ├── aliases.sh
        └── README.md
```

## Convenções ao adicionar um item novo

**git:**
1. Criar `git/<id>/script.sh` (implementação) e `git/<id>/README.md` (uso, flags, exemplos — mesmo nível de detalhe do `git/chain/README.md`).
2. Criar `git/<id>/alias.gitconfig` com uma linha: `<nome> = !bash {{ROOT}}/git/<id>/script.sh`.
3. Adicionar linha no `MANIFEST`: `<id>|git|git/<id>/alias.gitconfig|<nome>|<description em inglês>`.
4. Se o script exigir binário externo (jq, gh, ...), criar `git/<id>/deps` (formato `bin|min_version|version_cmd`, uma linha por dependência — ver `git/chain/deps`). `deps.sh` descobre e agrega isso sozinho, sem editar `deps.sh`.
5. Rodar `./install.sh` local pra validar antes de commitar.

**shell:**
1. Criar `shell/<id>/aliases.sh` e `shell/<id>/README.md`.
2. Linha no `MANIFEST`: `<id>|shell|shell/<id>/aliases.sh|<nome>|<description>`.
3. Se precisar de binário externo, criar `shell/<id>/deps` (mesmo formato acima).
4. `./install.sh` de novo.

## Dependências externas (`deps.sh`)

`deps.sh` é **genérico** - não conhece nome de dependência nenhum. Ele
descobre o que checar/instalar lendo:
- `deps` na raiz: dependências do próprio toolbox (ex: `fzf`, usado pelo
  `install.sh`), não de um item específico.
- `<git|shell>/<id>/deps` (opcional, um por item): dependências exigidas só
  por aquele alias/script (ex: `git/chain/deps` exige `jq` e `gh`).

Nunca adicionar nome de dependência hardcoded dentro de `deps.sh` - isso
seria lógica de item específico vazando pro orquestrador genérico. Sempre
criar/editar o arquivo `deps` do item correspondente (ou o da raiz, se for
dependência do toolbox como um todo).

## Antes de commitar

- `bash -n <script>.sh` em todo script tocado (falha de sintaxe não pode chegar em `main` - quebra alias de todo mundo que rodar `install.sh`/`bootstrap.sh`).
- Rodar `shellcheck` se disponível localmente; senão pelo menos revisar manualmente `set -euo pipefail`, quoting de variáveis, e uso de `local`/escopo.
- Testar o fluxo local: `./install.sh` (idempotente) e, se mexeu em `install.sh`/`bootstrap.sh`, também `./install.sh --interactive`.
- `git/aliases.local.gitconfig` e `.installed` são gerados e gitignored — nunca commitar.

## Placeholder `{{ROOT}}`

Todo `alias.gitconfig` usa `{{ROOT}}` no lugar do path absoluto do clone.
`install.sh` substitui isso via `sed` na hora de gerar
`git/aliases.local.gitconfig` — isso é o que permite o mesmo repo funcionar
em qualquer máquina/path de clone sem edição manual. Nunca hardcodar path
absoluto num `alias.gitconfig` versionado.

## O que evitar

- Editar `git/aliases.local.gitconfig` ou `.installed` a mão (são gerados; mudança se perde no próximo `install.sh`).
- Path absoluto hardcoded em `alias.gitconfig` (usar sempre `{{ROOT}}`).
- Alias novo sem entrada correspondente no `MANIFEST` (fica invisível pro menu interativo de `install.sh --interactive`/`bootstrap.sh`).
- Lógica de negócio pesada dentro do `install.sh`/`bootstrap.sh` — eles só orquestram (seleção, geração de config, source); a lógica do alias em si vive no `script.sh` do próprio item.
