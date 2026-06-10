# Análise dos scripts existentes no sistema

**Data:** 2026-06-10 · **Sistema:** macOS 26.5 (build 25F71), arm64

## Âmbito

Foram analisadas as três localizações pedidas: `~/.local/bin`, `/usr/local/bin`
e `~/.config` (busca recursiva por `*.sh`, `*.zsh`, `*.bash`).

## Resultado: não existem scripts shell personalizados para otimizar

### `~/.local/bin`
Contém apenas **`rtk`** (7,3 MB) — um executável Mach-O arm64 compilado em Rust
(o "Rust Token Killer" referido no CLAUDE.md). Não é um script: não há código
fonte shell para analisar ou reescrever. Está corretamente instalado e funcional.

### `/usr/local/bin`
Contém exclusivamente **symlinks geridos pelas próprias aplicações**:
- Docker Desktop (`docker`, `docker-compose`, `kubectl`, `cagent`, `hub-tool`, credenciais)
- Visual Studio Code (`code`)
- Python.org 3.14 (`python3*`, `pip3*`, `idle3*`, `pydoc3*`)

Estes symlinks são recriados/atualizados pelos instaladores respetivos.
**Não devem ser editados manualmente** — qualquer alteração seria perdida na
próxima atualização da app.

### `~/.config`
Sem ficheiros de script shell. Apenas configurações de aplicações.

## Avaliação de segurança das localizações

| Verificação | Estado |
|---|---|
| Binários desconhecidos em `~/.local/bin` | Nenhum além do `rtk` documentado |
| Symlinks órfãos em `/usr/local/bin` | Nenhum detetado |
| Scripts com permissões excessivas | N/A (não existem scripts) |

## Conclusão e ação tomada

Como não havia scripts para melhorar, a tarefa converteu-se na **criação de
raiz** de um toolkit com as boas práticas que se aplicariam numa reescrita:

- `set -u` e validação de caminhos (`is_safe_path`) antes de qualquer remoção
- Compatibilidade com bash 3.2 nativo (sem arrays associativos nem `${var,,}`)
- Confirmação do utilizador por secção + modo `--dry-run`
- Logs de auditoria com lista de todos os ficheiros removidos
- Reversibilidade (`--revert`) para todas as alterações de estado do sistema
- Recusa de execução como root; `sudo` apenas nos comandos pontuais
- Zero dependências externas — apenas utilitários incluídos no macOS

Ver `README.md` para a documentação completa dos scripts criados.
