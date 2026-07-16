# Contribuindo com o dev-toolbox

Guia rápido pra quem quer adicionar ou alterar um alias. Convenções
completas (estrutura, idioma, placeholder `{{ROOT}}`) estão em
[`AGENTS.md`](AGENTS.md) — este arquivo é o passo a passo prático.

## Adicionando um alias de git

1. Crie o diretório do item:
   ```bash
   mkdir git/meu-alias
   ```
2. Escreva o script em `git/meu-alias/script.sh` (não precisa de `chmod +x` - o `alias.gitconfig` invoca `bash script.sh` explicitamente).
3. Crie `git/meu-alias/alias.gitconfig`:
   ```ini
   meu-alias = !bash {{ROOT}}/git/meu-alias/script.sh
   ```
   `{{ROOT}}` é literal — o `install.sh` substitui pelo path real do clone.
4. Documente em `git/meu-alias/README.md` (uso, flags, exemplos — use
   [`git/chain/README.md`](git/chain/README.md) como referência de nível de
   detalhe).
5. Adicione uma linha no `MANIFEST` (em inglês):
   ```
   meu-alias|git|git/meu-alias/alias.gitconfig|meu-alias|Short description in English
   ```
6. Teste local:
   ```bash
   ./install.sh
   git meu-alias   # confirma que o alias funciona
   ```

## Adicionando um alias/função de shell

Mesmo fluxo, trocando `alias.gitconfig` por `aliases.sh` com as
funções/aliases de bash+zsh, e `type=shell` no `MANIFEST`.

## Checklist antes do PR

- [ ] `bash -n` em todo script novo/alterado (sintaxe válida)
- [ ] `shellcheck` limpo (se tiver instalado localmente)
- [ ] `./install.sh` roda sem erro e o alias novo funciona
- [ ] `./install.sh --interactive` mostra o item novo no menu com a descrição certa
- [ ] README dedicado do item criado/atualizado
- [ ] Linha adicionada/atualizada no `MANIFEST`
- [ ] Nenhum path absoluto hardcoded (`{{ROOT}}` no lugar do path do clone)
- [ ] `git/aliases.local.gitconfig` e `.installed` **não** estão no commit (gerados, gitignored)

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), em inglês:

```
feat(git): add git prune-merged alias
fix(chain): handle detached HEAD without crashing
docs(chain): document --no-pr flag
```

## Removendo um item

1. Apagar o diretório (`git/<id>/` ou `shell/<id>/`).
2. Remover a linha correspondente do `MANIFEST`.
3. Rodar `./install.sh` — o item some sozinho do arquivo gerado
   (`git/aliases.local.gitconfig` ou `shell/aliases.local.sh`, conforme o
   tipo). Nada a editar a mão em `~/.bashrc`/`~/.zshrc`/`~/.gitconfig`.
