# mac-optimization — Toolkit de Otimização do macOS

Conjunto de scripts shell para limpeza, otimização e diagnóstico do macOS,
usando **apenas comandos nativos** (sem Homebrew, sem dependências externas).
Compatível com o bash 3.2 incluído no macOS.

## Estrutura

| Ficheiro | Função |
|---|---|
| `mac-optimize.sh` | **Menu central** — ponto de entrada recomendado |
| `cleanup-temp.sh` | Limpeza de caches, logs, temporários, downloads incompletos e Lixo |
| `optimize-mac.sh` | Otimização de RAM/CPU/energia/serviços, com relatórios antes/depois |
| `system-health.sh` | Diagnóstico de saúde (só leitura, não altera nada) |
| `mac-optimize.conf` | Configuração (idades de ficheiros, caches protegidas, serviços) |
| `lib/common.sh` | Funções partilhadas (logging, confirmações, segurança) |
| `docs/ANALISE-SCRIPTS.md` | Relatório da análise dos scripts pré-existentes no sistema |

## Instalação segura

```bash
cd ~/Documents/mac-optimization

# 1. Inspecione os scripts antes de executar (boa prática com qualquer script)
less cleanup-temp.sh

# 2. Torne os scripts executáveis
chmod +x mac-optimize.sh cleanup-temp.sh optimize-mac.sh system-health.sh

# 3. (Opcional) Crie a sua configuração pessoal
cp mac-optimize.conf ~/.mac-optimize.conf

# 4. Primeira execução: SEMPRE em modo simulação
./cleanup-temp.sh --dry-run

# 5. Use o menu central
./mac-optimize.sh
```

Para chamar de qualquer diretório, adicione um alias ao `~/.zshrc`:

```bash
alias macopt='~/Documents/mac-optimization/mac-optimize.sh'
```

## Utilização

### Menu central
```bash
./mac-optimize.sh
# 1 = limpeza | 2 = otimização | 3 = saúde | 4 = logs | 5 = sair
# D = simulação de limpeza | R = reverter otimizações
```

### Limpeza (`cleanup-temp.sh`)
- `./cleanup-temp.sh --dry-run` — mostra o que seria apagado, **sem apagar nada**
- `./cleanup-temp.sh` — interativo, pede confirmação **por secção**
- `ASSUME_YES=1 ./cleanup-temp.sh` — sem confirmações (só para automação, use com cuidado)

O que limpa (tudo configurável em `mac-optimize.conf`):
1. `~/Library/Caches` — apenas ficheiros com mais de `CACHE_AGE_DAYS` dias; as pastas
   são mantidas e as caches da lista `PROTECTED_CACHES` (iCloud, Safari…) nunca são tocadas
2. `~/Library/Logs` — logs com mais de `LOG_AGE_DAYS` dias
3. `/tmp` e `/var/tmp` — apenas **ficheiros do seu utilizador** com mais de `TMP_AGE_DAYS` dias
4. `~/Downloads` — downloads incompletos (`.download`, `.crdownload`, `.part`…)
5. Lixo — esvaziado via Finder, com confirmação explícita (irreversível)

No final apresenta o relatório do espaço libertado e o espaço livre antes/depois.

### Otimização (`optimize-mac.sh`)
- `./optimize-mac.sh` — interativo (relatório antes → ações → relatório depois)
- `./optimize-mac.sh --report-only` — apenas analisa, não altera nada
- `./optimize-mac.sh --revert` — **reverte** as definições de energia e reativa serviços

Ações (cada uma com confirmação):
1. Relatório "antes" (CPU, RAM, swap, top processos) guardado em `~/.mac-optimization-logs`
2. Encerramento gracioso de apps pesadas (equivalente a Cmd+Q — a app pode pedir para guardar)
3. Energia em bateria via `pmset -b`: ecrã 5 min, disco 10 min, Power Nap off, Wake-on-LAN off
   — os valores anteriores são guardados e repostos com `--revert`
4. `purge` da cache de disco, apenas se a memória livre estiver abaixo de `MEMORY_FREE_THRESHOLD`
5. Desativação de LaunchAgents listados em `SERVICES_TO_DISABLE` (lista **vazia por omissão**)
   — cada serviço desativado é registado e reativável com `--revert`

### Saúde do sistema (`system-health.sh`)
Só leitura. Verifica disco (com alertas a <20% e <10% livres), memória/swap,
térmica, bateria, FileVault/Gatekeeper/SIP e processos pesados.

## Logs de auditoria

Tudo é registado em `~/.mac-optimization-logs/` (permissões 700):
- `cleanup-temp-AAAAMMDD-HHMMSS.log` — inclui a lista de cada ficheiro apagado
- `performance-antes/depois-*.txt` — relatórios de desempenho
- `state/` — backups necessários para o `--revert` (pmset e serviços)

## ⚠️ Avisos de segurança

- **Esvaziar o Lixo é irreversível.** O script avisa e pede confirmação explícita.
- **Nunca execute como root/sudo diretamente.** Os scripts recusam-se a correr como
  root; o `sudo` é pedido apenas nos comandos pontuais que o exigem (`pmset`, `purge`).
- **Limpar caches tem custo:** as apps reconstroem as caches, o que pode tornar os
  primeiros arranques mais lentos. Por isso só se apagam ficheiros antigos.
- **Não adicione serviços a `SERVICES_TO_DISABLE` sem saber o que fazem.** Desativar
  agentes da Apple (`com.apple.*`) pode partir funcionalidades do sistema.
- **SIP (System Integrity Protection) deve ficar ativo.** Nenhum destes scripts o
  toca, e deve desconfiar de qualquer "otimizador" que peça para o desativar.
- Os scripts validam caminhos antes de apagar (`is_safe_path`) e nunca tocam em
  `/System`, `/usr`, `/Applications` ou na raiz da pasta pessoal.
- Reveja sempre o log de auditoria após cada execução.

## Personalização

Edite `~/.mac-optimize.conf` (prioritário) ou `mac-optimize.conf`:

```bash
CACHE_AGE_DAYS=7            # idade mínima das caches a apagar
LOG_AGE_DAYS=30             # idade mínima dos logs a apagar
TMP_AGE_DAYS=3              # idade mínima em /tmp e /var/tmp
DOWNLOADS_AGE_DAYS=7        # idade mínima dos downloads incompletos
EMPTY_TRASH=yes             # "no" para nunca esvaziar o Lixo
MEMORY_FREE_THRESHOLD=20    # % de memória livre abaixo da qual se sugere purge
PROTECTED_CACHES="..."      # caches que nunca são tocadas
SERVICES_TO_DISABLE=""      # LaunchAgents a desativar (vazio = nenhum)
```

## Reversibilidade

| Ação | Como reverter |
|---|---|
| Definições de energia (pmset) | `./optimize-mac.sh --revert` |
| Serviços desativados | `./optimize-mac.sh --revert` |
| Caches apagadas | Reconstruídas automaticamente pelas apps |
| Logs/temporários/Lixo apagados | **Irreversível** — daí as confirmações e o dry-run |
