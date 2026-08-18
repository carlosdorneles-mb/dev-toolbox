# devstack-rollout-crash-pods

Reinicia (`kubectl rollout restart`) os deployments de um namespace que
tenham pods em crash/erro, pods `Running` com READY incompleto (ex: `0/1`
em vez de `1/1`), ou pods presos em `Terminating`/`PodInitializing`/
`Completed`/`ContainerCreating` há mais de 2min.

## Uso

```bash
devstack-rollout-crash-pods [ambiente]
devstack-rollout-crash-pods -n <ambiente>
devstack-rollout-crash-pods -h | --help
```

- `[ambiente]` (obrigatório) - namespace do Kubernetes. Aceita posicional
  ou via flag `-n`/`--namespace`. Se omitido e `gum` estiver instalado
  (terminal interativo), abre um seletor (`gum filter`) com os namespaces
  do cluster.
- `-h`/`--help` - mostra a ajuda embutida e sai.

## Descrição

1. Verifica `kubectl` instalado e cluster correto (mesmo padrão de
   `devstack-info`/`devstack-users`).
2. Valida o namespace (direto, via flag, ou seletor `gum filter` alimentado
   por `kubectl get namespaces`) e confere que ele existe no cluster.
3. Varre `kubectl get pods -n <ambiente>` por três grupos de problema:
   - pods fora de `Running`/`Terminating`/`PodInitializing`/`Completed`/
     `ContainerCreating` (crash/erro);
   - pods `Running` com READY diferente do total (ex: `0/1`);
   - pods em `Terminating`/`PodInitializing`/`Completed`/
     `ContainerCreating` há mais de 2min (`AGE` da coluna do `kubectl get
     pods`, convertido pra segundos) - normal se recente (pod
     subindo/descendo), sinal de travamento se persiste.
   Em todos, o nome do deployment é derivado removendo o sufixo
   `-<replicaset>-<pod>` do nome do pod.
4. Junta os deployments únicos dos três grupos; se não houver nenhum,
   avisa e sai sem fazer nada.
5. Lista os deployments encontrados e pede confirmação (`[y/N]`) antes de
   rodar `kubectl rollout restart deployment/<nome> -n <ambiente>` em cada
   um.
6. Ao final, pergunta se quer entrar em modo `watch` (`watch "kubectl get
   pods -n <ambiente> | grep -E '(dep1|dep2|...)'"`) pra acompanhar o
   rollout.

## Requisitos

`kubectl` configurado com acesso ao cluster/namespace consultado
(contexto/kubeconfig já resolvido fora deste comando). `watch` instalado
pro modo de acompanhamento opcional (passo 6) - sem ele, o comando ainda
funciona, só o "watch mode" falha se escolhido.

## Exemplo

```bash
$ devstack-rollout-crash-pods staging

Deployments encontrados com problema:
minha-api
outro-servico

Confirmar rollout restart dos deployments acima em 'staging'? [y/N]: y
> Iniciando rollout dos deployments...
Deployment minha-api reiniciado.
Deployment outro-servico reiniciado.

Entrar em modo watch pra acompanhar o rollout? [y/N]:
```
