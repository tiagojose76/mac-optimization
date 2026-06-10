#!/bin/bash
# ============================================================================
# system-health.sh — Análise de saúde do sistema (100% leitura, não altera nada)
#
# Verifica: disco, memória, CPU/térmica, bateria, segurança (FileVault,
# Gatekeeper, SIP), uptime e processos pesados. Guarda o relatório em
# ~/.mac-optimization-logs.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_macos
load_config
init_logging

section() { printf '\n%s\n' "${C_BOLD}--- $* ---${C_RESET}"; _log "INFO" "Secção: $*"; }

# Escreve no ecrã e no log ao mesmo tempo
run_check() { "$@" 2>&1 | tee -a "${LOG_FILE}"; }

printf '%s\n' "${C_BOLD}=== Análise de saúde do sistema — $(date '+%Y-%m-%d %H:%M') ===${C_RESET}"

section "Sistema"
run_check sw_vers
run_check uname -m
echo "Uptime: $(uptime | sed 's/.*up /up /;s/,.*load/ | load/')" | tee -a "${LOG_FILE}"

section "Disco"
run_check df -h /
FREE_PCT=$(df -k / | awk 'NR==2 {gsub(/%/,"",$5); print 100-$5}')
if [ "${FREE_PCT}" -lt 10 ]; then
    log_error "Espaço livre crítico: ${FREE_PCT}% — execute a limpeza (opção 1 do menu)."
elif [ "${FREE_PCT}" -lt 20 ]; then
    log_warn "Espaço livre baixo: ${FREE_PCT}% — considere executar a limpeza."
else
    log_ok "Espaço livre saudável: ${FREE_PCT}%"
fi

section "Memória"
run_check sysctl -n hw.memsize | awk '{printf "RAM instalada: %.0f GB\n", $1/1073741824}'
MEM_FREE=$(memory_pressure 2>/dev/null | awk -F': ' '/percentage/ {gsub(/%/,"",$2); print int($2); exit}')
if [ -n "${MEM_FREE:-}" ]; then
    if [ "${MEM_FREE}" -lt "${MEMORY_FREE_THRESHOLD}" ]; then
        log_warn "Memória livre: ${MEM_FREE}% (abaixo do limiar de ${MEMORY_FREE_THRESHOLD}%)"
    else
        log_ok "Memória livre: ${MEM_FREE}%"
    fi
fi
run_check sysctl vm.swapusage

section "CPU e térmica"
echo "Load average:$(uptime | awk -F'load averages:' '{print $2}')" | tee -a "${LOG_FILE}"
run_check pmset -g therm

section "Bateria e energia"
run_check pmset -g batt
echo | tee -a "${LOG_FILE}"
echo "Perfil de energia ativo:" | tee -a "${LOG_FILE}"
run_check pmset -g

section "Segurança"
echo "FileVault:  $(fdesetup status 2>/dev/null || echo 'sem permissão para verificar')" | tee -a "${LOG_FILE}"
echo "Gatekeeper: $(spctl --status 2>/dev/null || echo 'desconhecido')" | tee -a "${LOG_FILE}"
echo "SIP:        $(csrutil status 2>/dev/null || echo 'desconhecido')" | tee -a "${LOG_FILE}"

section "Top 5 processos por CPU"
run_check sh -c "ps -Aceo pcpu,pmem,comm -r | head -6"

section "Top 5 processos por memória"
run_check sh -c "ps -Aceo pmem,pcpu,comm -m | head -6"

section "Tamanhos relevantes para limpeza"
for d in "${HOME}/Library/Caches" "${HOME}/Library/Logs" "${HOME}/.Trash"; do
    echo "$(human_kb "$(du_kb "${d}")")  ${d}" | tee -a "${LOG_FILE}"
done

printf '\n'
log_ok "Relatório completo guardado em: ${LOG_FILE}"
