# fix-network

Ajusta a rede em caso de instabilidade de conexão. Cross-platform
Ubuntu/Debian + macOS.

## Uso

```bash
fix-network
fix-network --skip-ipv6
fix-network --skip-dns
fix-network -h | --help
```

## Descrição

Detecta o SO via `uname -s` e pede a senha do `sudo` uma vez no início
(`sudo -v`). Passos 1 e 2 rodam por padrão, sem confirmação; use as flags
pra pular. Passos em sequência:

1. **IPv6** (roda por padrão; `--skip-ipv6` pula)
   - Linux: desativa IPv6 (`ipv6.method ignore`) em todos os perfis salvos
     do NetworkManager via `nmcli`.
   - macOS: desativa IPv6 (`networksetup -setv6off`) em todos os serviços
     de rede listados por `networksetup -listallnetworkservices`.
2. **Cache de DNS** (roda por padrão; `--skip-dns` pula)
   - Linux: limpa via `resolvectl flush-caches`.
   - macOS: limpa via `dscacheutil -flushcache` + `killall -HUP mDNSResponder`.
3. **NetworkManager** - só no Linux, reinicia sempre
   (`systemctl restart NetworkManager`). Sem equivalente confiável no
   macOS (não existe unidade systemd tipo NetworkManager) - passo pulado
   lá, com aviso.
4. **Netskope (`stagentd`)** - só no Linux, aguarda 5s pra rede estabilizar
   e reinicia o serviço, só se ele existir e estiver ativo/habilitado na
   máquina (`systemctl is-active`/`is-enabled`). Sem nome de serviço
   launchd confiável no macOS - passo pulado lá, com aviso.

## Requisitos

- **Obrigatório:** `bash`/`zsh`, `sudo`.
- **Linux:** `systemctl`, `NetworkManager` (`nmcli`), `resolvectl`.
- **macOS:** `networksetup`, `dscacheutil`, `killall`.
- **Opcional:** `stagentd` (Netskope, Linux) - só é reiniciado se presente
  na máquina.

## Compatibilidade Ubuntu/Debian x macOS

- **Ubuntu/Debian**: roda todos os 4 passos.
- **macOS**: roda IPv6 e cache de DNS (passos 1 e 2) com os comandos
  equivalentes do macOS; pula restart de NetworkManager e Netskope
  (passos 3 e 4), que não têm um equivalente direto e confiável na
  plataforma - avisa isso na tela em vez de tentar adivinhar.

## Observações

- No Linux, não é idempotente no sentido de "sem efeito colateral":
  reinicia `NetworkManager` (derruba a conexão por alguns segundos) toda
  vez que roda, independente das flags `--skip-ipv6`/`--skip-dns`.
- No macOS, IPv6 e DNS rodam sem confirmação por padrão (a menos que
  puladas via flag) - não há restart incondicional de rede.
