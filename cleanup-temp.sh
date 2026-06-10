#!/bin/bash
# ============================================================================
# cleanup-temp.sh — Limpeza segura de ficheiros temporários no macOS
#
# Limpa: caches do utilizador, logs antigos, /tmp e /var/tmp (apenas ficheiros
# do utilizador), downloads incompletos e o Lixo. Pede confirmação por secção,
# regista tudo em ~/.mac-optimization-logs e gera relatório do espaço libertado.
#
# Uso:
#   ./cleanup-temp.sh             # modo interativo (recomendado)
#   ./cleanup-temp.sh --dry-run   # simula sem apagar nada
#   ASSUME_YES=1 ./cleanup-temp.sh  # sem confirmações (para automação)
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

require_macos
require_not_root
load_config
init_logging

TOTAL_FREED_KB=0

# ---------------------------------------------------------------------------
# Apaga ficheiros encontrados por "find", medindo o espaço libertado.
# $1 = descrição | restantes = argumentos do find (caminho + filtros)
# ---------------------------------------------------------------------------
clean_with_find() {
    local desc="$1"; shift
    local target="$1"

    if ! is_safe_path "${target}" || [ ! -d "${target}" ]; then
        log_warn "Ignorado (caminho inexistente ou protegido): ${target}"
        return 0
    fi

    local count size_kb
    count=$(find "$@" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${count}" -eq 0 ]; then
        log_info "${desc}: nada a remover."
        return 0
    fi

    size_kb=$(find "$@" -print0 2>/dev/null | xargs -0 du -sk 2>/dev/null | awk '{s+=$1} END {print s+0}')
    log_info "${desc}: ${count} item(ns), $(human_kb "${size_kb}")"

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_warn "[dry-run] Nada foi apagado."
        find "$@" 2>/dev/null | head -10 >> "${LOG_FILE}"
        return 0
    fi

    if confirm "Remover ${count} item(ns) — ${desc} ($(human_kb "${size_kb}"))?"; then
        # Regista no log de auditoria tudo o que vai ser apagado
        find "$@" 2>/dev/null >> "${LOG_FILE}"
        find "$@" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null
        TOTAL_FREED_KB=$((TOTAL_FREED_KB + size_kb))
        log_ok "${desc}: $(human_kb "${size_kb}") libertados."
    else
        log_info "${desc}: ignorado pelo utilizador."
    fi
}

# ---------------------------------------------------------------------------
# 1. Caches do utilizador (~/Library/Caches)
#    Remove apenas FICHEIROS com mais de CACHE_AGE_DAYS dias, dentro de cada
#    pasta de cache — as pastas em si são mantidas (as apps esperam que existam).
#    Caches da lista PROTECTED_CACHES nunca são tocadas.
# ---------------------------------------------------------------------------
clean_user_caches() {
    printf '\n%s\n' "${C_BOLD}--- 1/5: Caches do utilizador (~/Library/Caches) ---${C_RESET}"
    local cache_root="${HOME}/Library/Caches"
    [ -d "${cache_root}" ] || { log_warn "Sem acesso a ${cache_root}"; return 0; }

    local dir name protected p
    for dir in "${cache_root}"/*; do
        [ -d "${dir}" ] || continue
        name="$(basename "${dir}")"
        protected=0
        for p in ${PROTECTED_CACHES}; do
            [ "${name}" = "${p}" ] && protected=1 && break
        done
        if [ "${protected}" -eq 1 ]; then
            _log "INFO" "Cache protegida, não tocada: ${name}"
            continue
        fi
        clean_with_find "Cache: ${name}" "${dir}" -type f -mtime +"${CACHE_AGE_DAYS}"
    done
}

# ---------------------------------------------------------------------------
# 2. Logs antigos (~/Library/Logs)
# ---------------------------------------------------------------------------
clean_user_logs() {
    printf '\n%s\n' "${C_BOLD}--- 2/5: Logs antigos (~/Library/Logs, >${LOG_AGE_DAYS} dias) ---${C_RESET}"
    clean_with_find "Logs do utilizador" "${HOME}/Library/Logs" \
        -type f \( -name "*.log" -o -name "*.log.*" -o -name "*.gz" -o -name "*.bz2" \) \
        -mtime +"${LOG_AGE_DAYS}"
}

# ---------------------------------------------------------------------------
# 3. Temporários do sistema (/tmp, /var/tmp)
#    Apenas FICHEIROS pertencentes ao utilizador atual e com mais de
#    TMP_AGE_DAYS dias. Sockets, diretórios e ficheiros de outros utilizadores
#    não são tocados (evita partir apps em execução).
# ---------------------------------------------------------------------------
clean_system_tmp() {
    printf '\n%s\n' "${C_BOLD}--- 3/5: Temporários do sistema (/tmp, /var/tmp, >${TMP_AGE_DAYS} dias) ---${C_RESET}"
    local d
    for d in /tmp /var/tmp; do
        clean_with_find "Temporários em ${d}" "${d}" \
            -type f -user "$(id -un)" -mtime +"${TMP_AGE_DAYS}"
    done
}

# ---------------------------------------------------------------------------
# 4. Downloads incompletos (~/Downloads)
# ---------------------------------------------------------------------------
clean_incomplete_downloads() {
    printf '\n%s\n' "${C_BOLD}--- 4/5: Downloads incompletos (>${DOWNLOADS_AGE_DAYS} dias) ---${C_RESET}"
    clean_with_find "Downloads incompletos" "${HOME}/Downloads" -maxdepth 1 \
        \( -name "*.download" -o -name "*.crdownload" -o -name "*.part" \
           -o -name "*.partial" -o -name "*.opdownload" \) \
        -mtime +"${DOWNLOADS_AGE_DAYS}"
}

# ---------------------------------------------------------------------------
# 5. Esvaziar o Lixo (~/.Trash)
# ---------------------------------------------------------------------------
empty_trash() {
    printf '\n%s\n' "${C_BOLD}--- 5/5: Esvaziar o Lixo ---${C_RESET}"
    if [ "${EMPTY_TRASH}" != "yes" ]; then
        log_info "Esvaziar o Lixo desativado na configuração (EMPTY_TRASH=${EMPTY_TRASH})."
        return 0
    fi
    local trash="${HOME}/.Trash"
    local size_kb count
    size_kb=$(du_kb "${trash}")
    count=$(find "${trash}" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    if [ "${count}" -eq 0 ]; then
        log_info "O Lixo já está vazio."
        return 0
    fi
    log_info "Lixo: ${count} item(ns), $(human_kb "${size_kb}")"
    if [ "${DRY_RUN}" -eq 1 ]; then
        log_warn "[dry-run] O Lixo não foi esvaziado."
        return 0
    fi
    if confirm "Esvaziar o Lixo PERMANENTEMENTE ($(human_kb "${size_kb}"))? Esta ação é IRREVERSÍVEL"; then
        find "${trash}" -mindepth 1 -maxdepth 1 2>/dev/null >> "${LOG_FILE}"
        # Usa o Finder para respeitar itens bloqueados; recua para rm se falhar
        if ! osascript -e 'tell application "Finder" to empty trash' >/dev/null 2>&1; then
            find "${trash}" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null
        fi
        TOTAL_FREED_KB=$((TOTAL_FREED_KB + size_kb))
        log_ok "Lixo esvaziado: $(human_kb "${size_kb}") libertados."
    else
        log_info "Lixo: mantido."
    fi
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------
printf '%s\n' "${C_BOLD}=== Limpeza de temporários do macOS ===${C_RESET}"
[ "${DRY_RUN}" -eq 1 ] && log_warn "MODO DRY-RUN: nada será apagado."
log_info "Log de auditoria: ${LOG_FILE}"

FREE_BEFORE_KB=$(disk_free_kb)

clean_user_caches
clean_user_logs
clean_system_tmp
clean_incomplete_downloads
empty_trash

FREE_AFTER_KB=$(disk_free_kb)
DISK_DELTA_KB=$((FREE_AFTER_KB - FREE_BEFORE_KB))
[ "${DISK_DELTA_KB}" -lt 0 ] && DISK_DELTA_KB=0

printf '\n%s\n' "${C_BOLD}=== Relatório final ===${C_RESET}"
log_ok "Espaço libertado (soma das secções): $(human_kb "${TOTAL_FREED_KB}")"
log_ok "Espaço livre no disco: antes $(human_kb "${FREE_BEFORE_KB}") | depois $(human_kb "${FREE_AFTER_KB}") (+$(human_kb "${DISK_DELTA_KB}"))"
log_info "Relatório completo em: ${LOG_FILE}"
