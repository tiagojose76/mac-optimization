#!/bin/bash
# ============================================================================
# mac-optimize.sh — Menu central do toolkit de otimização do macOS
#
#   1) Limpeza de temporários       (cleanup-temp.sh)
#   2) Otimização de desempenho     (optimize-mac.sh)
#   3) Análise de saúde do sistema  (system-health.sh)
#   4) Ver logs de otimização
#   5) Sair
#
# Extras: R) Reverter otimizações | D) Simulação de limpeza (dry-run)
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_macos
require_not_root
load_config

run_script() {
    local script="${SCRIPT_DIR}/$1"; shift
    if [ ! -x "${script}" ]; then
        if [ -f "${script}" ]; then
            printf '%s\n' "${C_YELLOW}[AVISO]${C_RESET} ${script} sem permissão de execução — a corrigir."
            chmod +x "${script}" || { printf '%s\n' "${C_RED}[ERRO]${C_RESET} Não foi possível tornar executável."; return 1; }
        else
            printf '%s\n' "${C_RED}[ERRO]${C_RESET} Script não encontrado: ${script}"
            return 1
        fi
    fi
    "${script}" "$@"
}

view_logs() {
    if [ ! -d "${LOG_DIR}" ] || [ -z "$(ls -A "${LOG_DIR}" 2>/dev/null | grep -v '^state$')" ]; then
        printf '%s\n' "${C_YELLOW}Ainda não existem logs em ${LOG_DIR}.${C_RESET}"
        return 0
    fi
    printf '%s\n\n' "${C_BOLD}=== Logs em ${LOG_DIR} (mais recentes primeiro) ===${C_RESET}"
    ls -lht "${LOG_DIR}" | grep -v '^total' | grep -v ' state$' | head -15
    printf '\n%s' "${C_YELLOW}Número da linha do log a abrir (Enter para voltar): ${C_RESET}"
    local n logfile
    read -r n
    [ -z "${n}" ] && return 0
    logfile=$(ls -t "${LOG_DIR}" | grep -v '^state$' | sed -n "${n}p")
    if [ -n "${logfile}" ] && [ -f "${LOG_DIR}/${logfile}" ]; then
        less "${LOG_DIR}/${logfile}"
    else
        printf '%s\n' "${C_RED}Seleção inválida.${C_RESET}"
    fi
}

pause() {
    printf '\n%s' "${C_BLUE}Prima Enter para voltar ao menu...${C_RESET}"
    read -r _
}

while :; do
    clear 2>/dev/null || true
    cat <<MENU
${C_BOLD}╔══════════════════════════════════════════════╗
║       OTIMIZAÇÃO DO macOS — MENU CENTRAL     ║
╚══════════════════════════════════════════════╝${C_RESET}

  ${C_GREEN}1${C_RESET}) Limpeza de ficheiros temporários
  ${C_GREEN}2${C_RESET}) Otimização de desempenho
  ${C_GREEN}3${C_RESET}) Análise de saúde do sistema
  ${C_GREEN}4${C_RESET}) Ver logs de otimização
  ${C_GREEN}5${C_RESET}) Sair

  ${C_BLUE}D${C_RESET}) Simulação de limpeza (dry-run, não apaga nada)
  ${C_BLUE}R${C_RESET}) Reverter otimizações de energia/serviços

  Logs de auditoria: ${LOG_DIR}
MENU
    printf '%s' "${C_BOLD}Escolha uma opção: ${C_RESET}"
    read -r choice
    case "${choice}" in
        1) run_script cleanup-temp.sh; pause ;;
        2) run_script optimize-mac.sh; pause ;;
        3) run_script system-health.sh; pause ;;
        4) view_logs; pause ;;
        5|q|Q) printf '%s\n' "${C_GREEN}Até à próxima!${C_RESET}"; exit 0 ;;
        d|D) run_script cleanup-temp.sh --dry-run; pause ;;
        r|R) run_script optimize-mac.sh --revert; pause ;;
        *) printf '%s\n' "${C_RED}Opção inválida.${C_RESET}"; sleep 1 ;;
    esac
done
