#!/bin/bash
# ============================================================================
# optimize-mac.sh — Otimização de desempenho do macOS (reversível)
#
# 1. Analisa RAM/CPU e gera relatório "antes"
# 2. Permite terminar aplicações pesadas (graciosamente, via Finder/osascript)
# 3. Otimiza definições de energia em bateria (pmset) — estado anterior guardado
# 4. Liberta memória de cache (purge) se a memória livre estiver baixa
# 5. Desativa serviços listados na configuração — registados para reversão
# 6. Gera relatório "depois" e comparação
#
# Uso:
#   ./optimize-mac.sh                # otimização interativa
#   ./optimize-mac.sh --report-only  # apenas relatório, não altera nada
#   ./optimize-mac.sh --revert       # reverte pmset e serviços desativados
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_macos
require_not_root
load_config
init_logging

PMSET_STATE="${STATE_DIR}/pmset-battery-backup.txt"
SERVICES_STATE="${STATE_DIR}/disabled-services.txt"

MODE="optimize"
case "${1:-}" in
    --revert)      MODE="revert" ;;
    --report-only) MODE="report" ;;
esac

# ---------------------------------------------------------------------------
# Relatório de desempenho (CPU, RAM, processos)
# ---------------------------------------------------------------------------
capture_metrics() {
    local label="$1"
    local out="${LOG_DIR}/performance-${label}-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "=== Relatório de desempenho (${label}) — $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo
        echo "--- Carga do sistema ---"
        uptime
        echo
        echo "--- Memória ---"
        memory_pressure 2>/dev/null | grep -E "percentage|pressure" || true
        sysctl vm.swapusage 2>/dev/null || true
        echo
        echo "--- Top 10 processos por CPU ---"
        ps -Aceo pcpu,pmem,comm -r | head -11
        echo
        echo "--- Top 10 processos por memória ---"
        ps -Aceo pmem,pcpu,comm -m | head -11
        echo
        echo "--- Disco ---"
        df -h /
    } > "${out}" 2>&1
    echo "${out}"
}

memory_free_pct() {
    memory_pressure 2>/dev/null | awk -F': ' '/percentage/ {gsub(/%/,"",$2); print int($2); exit}'
}

show_top_processes() {
    printf '\n%s\n' "${C_BOLD}--- Top 10 processos por CPU ---${C_RESET}"
    ps -Aceo pcpu,pmem,comm -r | head -11
    printf '\n%s\n' "${C_BOLD}--- Top 10 processos por memória ---${C_RESET}"
    ps -Aceo pmem,pcpu,comm -m | head -11
}

# ---------------------------------------------------------------------------
# Terminar aplicações pesadas (graciosamente — a app pode pedir para guardar)
# ---------------------------------------------------------------------------
quit_heavy_apps() {
    printf '\n%s\n' "${C_BOLD}--- 2/5: Reduzir aplicações pesadas ---${C_RESET}"
    show_top_processes
    echo
    log_info "Pode terminar aplicações graciosamente (equivalente a Cmd+Q; a app pode pedir para guardar trabalho)."
    while :; do
        printf '%s' "${C_YELLOW}Nome da aplicação a terminar (Enter para continuar): ${C_RESET}"
        local app
        read -r app
        [ -z "${app}" ] && break
        if osascript -e "tell application \"${app}\" to quit" >/dev/null 2>&1; then
            log_ok "Pedido de encerramento enviado a: ${app}"
        else
            log_warn "Não foi possível terminar \"${app}\" (nome errado ou app não está aberta)."
        fi
    done
}

# ---------------------------------------------------------------------------
# Otimização de energia em bateria (pmset -b) — guarda valores anteriores
# ---------------------------------------------------------------------------
# Chaves alteradas e novos valores (apenas no perfil de BATERIA):
#   displaysleep 5  — ecrã desliga após 5 min
#   disksleep 10    — disco dorme após 10 min
#   powernap 0      — desativa Power Nap (acordares em segundo plano)
#   womp 0          — desativa Wake on LAN
PMSET_KEYS="displaysleep disksleep powernap womp"
PMSET_VALUES="5 10 0 0"

optimize_power() {
    printf '\n%s\n' "${C_BOLD}--- 3/5: Definições de energia (bateria) ---${C_RESET}"
    if ! pmset -g batt 2>/dev/null | grep -qi "InternalBattery"; then
        log_info "Sem bateria interna detetada — otimização de energia ignorada."
        return 0
    fi
    log_info "Alterações propostas (apenas em bateria): displaysleep=5min, disksleep=10min, powernap=off, womp=off"
    log_info "Reversível com: ./optimize-mac.sh --revert"
    if ! confirm "Aplicar otimizações de energia (requer sudo)?"; then
        log_info "Definições de energia: mantidas."
        return 0
    fi

    # Guarda os valores ATUAIS do perfil de bateria antes de alterar
    if [ ! -f "${PMSET_STATE}" ]; then
        pmset -g custom | awk '/Battery Power:/{f=1;next} /AC Power:/{f=0} f && NF>=2 {print $1, $2}' > "${PMSET_STATE}"
        log_info "Estado anterior do pmset guardado em: ${PMSET_STATE}"
    else
        log_warn "Backup pmset já existia (${PMSET_STATE}) — mantido o original."
    fi

    local key val i=1
    for key in ${PMSET_KEYS}; do
        val=$(echo "${PMSET_VALUES}" | awk -v n="${i}" '{print $n}')
        if sudo pmset -b "${key}" "${val}" 2>>"${LOG_FILE}"; then
            log_ok "pmset -b ${key} ${val}"
        else
            log_warn "Falhou: pmset -b ${key} ${val} (chave pode não existir neste modelo)"
        fi
        i=$((i+1))
    done
}

revert_power() {
    if [ ! -f "${PMSET_STATE}" ]; then
        log_info "Sem backup do pmset — nada a reverter."
        return 0
    fi
    log_info "A repor definições de energia a partir de ${PMSET_STATE} (requer sudo)..."
    local key val restored=0
    for key in ${PMSET_KEYS}; do
        val=$(awk -v k="${key}" '$1==k {print $2; exit}' "${PMSET_STATE}")
        if [ -n "${val}" ]; then
            if sudo pmset -b "${key}" "${val}" 2>>"${LOG_FILE}"; then
                log_ok "Reposto: pmset -b ${key} ${val}"
                restored=1
            fi
        fi
    done
    if [ "${restored}" -eq 1 ]; then
        mv "${PMSET_STATE}" "${PMSET_STATE}.restaurado-$(date +%Y%m%d-%H%M%S)"
        log_ok "Definições de energia revertidas."
    fi
}

# ---------------------------------------------------------------------------
# Libertar memória de cache (purge) se a memória livre estiver baixa
# ---------------------------------------------------------------------------
free_memory() {
    printf '\n%s\n' "${C_BOLD}--- 4/5: Memória de cache ---${C_RESET}"
    local free_pct
    free_pct=$(memory_free_pct)
    if [ -z "${free_pct}" ]; then
        log_warn "Não foi possível ler a pressão de memória."
        return 0
    fi
    log_info "Memória livre: ${free_pct}% (limiar configurado: ${MEMORY_FREE_THRESHOLD}%)"
    if [ "${free_pct}" -ge "${MEMORY_FREE_THRESHOLD}" ]; then
        log_ok "Memória livre suficiente — purge não é necessário."
        return 0
    fi
    log_warn "Memória livre abaixo do limiar."
    if confirm "Executar 'purge' para libertar cache de disco da RAM (requer sudo, pode demorar)?"; then
        if sudo purge 2>>"${LOG_FILE}"; then
            log_ok "purge concluído. Memória livre agora: $(memory_free_pct)%"
        else
            log_error "purge falhou."
        fi
    fi
}

# ---------------------------------------------------------------------------
# Desativar serviços (LaunchAgents do utilizador) — com registo para reversão
# ---------------------------------------------------------------------------
disable_services() {
    printf '\n%s\n' "${C_BOLD}--- 5/5: Serviços desnecessários ---${C_RESET}"
    if [ -z "${SERVICES_TO_DISABLE}" ]; then
        log_info "Nenhum serviço listado em SERVICES_TO_DISABLE (configuração). Nada a desativar."
        log_info "Edite mac-optimize.conf para listar serviços — apenas se souber o que cada um faz."
        return 0
    fi
    local uid svc
    uid=$(id -u)
    for svc in ${SERVICES_TO_DISABLE}; do
        if ! launchctl print "gui/${uid}/${svc}" >/dev/null 2>&1; then
            log_warn "Serviço não encontrado (ignorado): ${svc}"
            continue
        fi
        if confirm "Desativar o serviço '${svc}'?"; then
            launchctl bootout "gui/${uid}/${svc}" 2>>"${LOG_FILE}" || true
            if launchctl disable "gui/${uid}/${svc}" 2>>"${LOG_FILE}"; then
                echo "${svc}" >> "${SERVICES_STATE}"
                log_ok "Desativado: ${svc} (registado para reversão)"
            else
                log_error "Falha ao desativar: ${svc}"
            fi
        fi
    done
}

revert_services() {
    if [ ! -s "${SERVICES_STATE}" ]; then
        log_info "Sem serviços desativados registados — nada a reverter."
        return 0
    fi
    local uid svc
    uid=$(id -u)
    while IFS= read -r svc; do
        [ -z "${svc}" ] && continue
        if launchctl enable "gui/${uid}/${svc}" 2>>"${LOG_FILE}"; then
            launchctl kickstart "gui/${uid}/${svc}" 2>>"${LOG_FILE}" || true
            log_ok "Reativado: ${svc}"
        else
            log_warn "Falha ao reativar: ${svc} (pode exigir logout/login)"
        fi
    done < "${SERVICES_STATE}"
    mv "${SERVICES_STATE}" "${SERVICES_STATE}.restaurado-$(date +%Y%m%d-%H%M%S)"
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------
case "${MODE}" in
    revert)
        printf '%s\n' "${C_BOLD}=== Reversão das otimizações ===${C_RESET}"
        revert_power
        revert_services
        log_ok "Reversão concluída. Log: ${LOG_FILE}"
        ;;
    report)
        printf '%s\n' "${C_BOLD}=== Relatório de desempenho (sem alterações) ===${C_RESET}"
        REPORT=$(capture_metrics "atual")
        show_top_processes
        printf '\n'
        log_info "Memória livre: $(memory_free_pct)%"
        log_ok "Relatório guardado em: ${REPORT}"
        ;;
    optimize)
        printf '%s\n' "${C_BOLD}=== Otimização de desempenho do macOS ===${C_RESET}"
        log_info "Log de auditoria: ${LOG_FILE}"

        printf '\n%s\n' "${C_BOLD}--- 1/5: Análise inicial (RAM e CPU) ---${C_RESET}"
        BEFORE=$(capture_metrics "antes")
        log_ok "Relatório 'antes' guardado em: ${BEFORE}"
        log_info "Memória livre: $(memory_free_pct)% | Carga: $(uptime | awk -F'load averages:' '{print $2}')"

        quit_heavy_apps
        optimize_power
        free_memory
        disable_services

        printf '\n%s\n' "${C_BOLD}--- Análise final ---${C_RESET}"
        sleep 2
        AFTER=$(capture_metrics "depois")
        log_ok "Relatório 'depois' guardado em: ${AFTER}"
        log_info "Memória livre: $(memory_free_pct)% | Carga: $(uptime | awk -F'load averages:' '{print $2}')"
        printf '\n'
        log_ok "Otimização concluída. Para reverter: ./optimize-mac.sh --revert"
        ;;
esac
