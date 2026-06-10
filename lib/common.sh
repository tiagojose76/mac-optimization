#!/bin/bash
# ============================================================================
# lib/common.sh — Funções partilhadas pelo toolkit mac-optimization
# Compatível com bash 3.2 (versão nativa do macOS). Sem dependências externas.
# ============================================================================

# Diretório de logs de auditoria
LOG_DIR="${HOME}/.mac-optimization-logs"
STATE_DIR="${LOG_DIR}/state"

# Diretório raiz do projeto (um nível acima de lib/)
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${COMMON_LIB_DIR}")"

# ---------------------------------------------------------------------------
# Cores (desativadas automaticamente se a saída não for um terminal)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'
    C_BLUE=$'\033[0;34m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

# ---------------------------------------------------------------------------
# Configuração
# Ordem de carregamento: defaults internos -> mac-optimize.conf do projeto
# -> ~/.mac-optimize.conf (personalização do utilizador, tem prioridade)
# ---------------------------------------------------------------------------
load_config() {
    # Defaults seguros (usados se nenhum ficheiro de configuração existir)
    CACHE_AGE_DAYS="${CACHE_AGE_DAYS:-7}"
    LOG_AGE_DAYS="${LOG_AGE_DAYS:-30}"
    TMP_AGE_DAYS="${TMP_AGE_DAYS:-3}"
    DOWNLOADS_AGE_DAYS="${DOWNLOADS_AGE_DAYS:-7}"
    MEMORY_FREE_THRESHOLD="${MEMORY_FREE_THRESHOLD:-20}"
    PROTECTED_CACHES="${PROTECTED_CACHES:-CloudKit com.apple.bird com.apple.FileProvider FamilyCircle com.apple.Safari com.apple.WebKit com.apple.containermanagerd}"
    SERVICES_TO_DISABLE="${SERVICES_TO_DISABLE:-}"
    EMPTY_TRASH="${EMPTY_TRASH:-yes}"

    if [ -f "${PROJECT_DIR}/mac-optimize.conf" ]; then
        # shellcheck source=/dev/null
        . "${PROJECT_DIR}/mac-optimize.conf"
    fi
    if [ -f "${HOME}/.mac-optimize.conf" ]; then
        # shellcheck source=/dev/null
        . "${HOME}/.mac-optimize.conf"
    fi
}

# ---------------------------------------------------------------------------
# Logging de auditoria
# ---------------------------------------------------------------------------
init_logging() {
    mkdir -p "${LOG_DIR}" "${STATE_DIR}"
    chmod 700 "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
    touch "${LOG_FILE}"
    log_info "=== Início: $(basename "$0") | utilizador: $(id -un) | $(date '+%Y-%m-%d %H:%M:%S') ==="
}

_log() {
    # $1 = nível, restante = mensagem. Escreve no ecrã e no ficheiro de log.
    local level="$1"; shift
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    if [ -n "${LOG_FILE:-}" ]; then
        printf '[%s] [%s] %s\n' "${ts}" "${level}" "$*" >> "${LOG_FILE}"
    fi
}

log_info()  { _log "INFO" "$@";  printf '%s\n' "${C_BLUE}[INFO]${C_RESET} $*"; }
log_ok()    { _log "OK" "$@";    printf '%s\n' "${C_GREEN}[OK]${C_RESET} $*"; }
log_warn()  { _log "AVISO" "$@"; printf '%s\n' "${C_YELLOW}[AVISO]${C_RESET} $*"; }
log_error() { _log "ERRO" "$@";  printf '%s\n' "${C_RED}[ERRO]${C_RESET} $*" >&2; }

die() { log_error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Confirmação do utilizador (respeita ASSUME_YES=1 para modo não interativo)
# ---------------------------------------------------------------------------
confirm() {
    local prompt="${1:-Continuar?}"
    if [ "${ASSUME_YES:-0}" = "1" ]; then
        _log "INFO" "Confirmação automática (ASSUME_YES): ${prompt}"
        return 0
    fi
    printf '%s' "${C_YELLOW}${prompt} [s/N]: ${C_RESET}"
    local answer
    read -r answer
    case "${answer}" in
        s|S|sim|Sim|SIM|y|Y) _log "INFO" "Utilizador confirmou: ${prompt}"; return 0 ;;
        *)                   _log "INFO" "Utilizador recusou: ${prompt}"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Utilitários de tamanho
# ---------------------------------------------------------------------------
du_kb() {
    # Tamanho de um caminho em KB (0 se não existir)
    du -sk "$1" 2>/dev/null | awk '{print $1}' || echo 0
}

human_kb() {
    # Converte KB num formato legível
    awk -v kb="${1:-0}" 'BEGIN {
        if (kb >= 1048576)    printf "%.2f GB", kb/1048576;
        else if (kb >= 1024)  printf "%.2f MB", kb/1024;
        else                  printf "%d KB", kb;
    }'
}

disk_free_kb() {
    df -k / | awk 'NR==2 {print $4}'
}

# ---------------------------------------------------------------------------
# Verificações de segurança
# ---------------------------------------------------------------------------
require_macos() {
    [ "$(uname)" = "Darwin" ] || die "Este script só funciona em macOS."
}

require_not_root() {
    [ "$(id -u)" -ne 0 ] || die "Não execute este script como root. O sudo será pedido apenas quando necessário."
}

# Verifica se um caminho é seguro para limpeza (nunca /, /System, $HOME puro, etc.)
is_safe_path() {
    case "$1" in
        ""|"/"|"/System"*|"/usr"|"/bin"|"/sbin"|"/etc"|"/Library"|"${HOME}"|"/Users"|"/Applications")
            return 1 ;;
        *)  return 0 ;;
    esac
}
