#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MODE="${1:-scan}"
REPORT_DIR="${HOME}/Desktop/mac-maintenance-reports"
REPORT_FILE="${REPORT_DIR}/mac-maintenance-$(date +%Y-%m-%d-%H%M%S).log"

readonly BYTES_IN_GB=1073741824

usage() {
  cat <<USAGE
Usage:
  ${SCRIPT_NAME} scan   Analyze disk usage and cleanup candidates. Does not delete anything.
  ${SCRIPT_NAME} clean  Analyze and ask before deleting safe cleanup candidates.

Examples:
  ./${SCRIPT_NAME} scan
  ./${SCRIPT_NAME} clean
USAGE
}

log() {
  printf '%s\n' "$*" | tee -a "${REPORT_FILE}"
}

section() {
  log ""
  log "== $* =="
}

path_exists() {
  [[ -e "$1" ]]
}

human_size() {
  local path="$1"
  local output=""

  if ! path_exists "${path}"; then
    printf '0B'
    return
  fi

  output="$(du -sh "${path}" 2>/dev/null | awk 'NR == 1 {print $1}')" || true
  if [[ -n "${output}" ]]; then
    printf '%s' "${output}"
  else
    printf 'unavailable'
  fi
}

path_bytes() {
  local path="$1"

  if ! path_exists "${path}"; then
    printf '0'
    return
  fi

  du -sk "${path}" 2>/dev/null | awk '{print $1 * 1024}' || printf '0'
}

confirm() {
  local prompt="$1"
  local answer=""

  read -r -p "${prompt} [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

print_path_size() {
  local label="$1"
  local path="$2"

  if path_exists "${path}"; then
    log "$(printf '%-34s' "${label}") $(human_size "${path}")  ${path}"
  fi
}

list_largest_children() {
  local title="$1"
  local path="$2"
  local limit="${3:-20}"
  local output=""

  section "${title}"
  if ! path_exists "${path}"; then
    log "Path not found: ${path}"
    return
  fi

  log "Top ${limit} items in ${path}:"
  output="$(du -sh "${path}"/* "${path}"/.[!.]* "${path}"/..?* 2>/dev/null \
    | sort -hr \
    | head -n "${limit}")" || true

  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}" | tee -a "${REPORT_FILE}"
  else
    log "Could not inspect ${path}. Some directories may require permissions."
  fi
}

disk_summary() {
  section "Disk summary"
  df -h / | tee -a "${REPORT_FILE}"
}

memory_summary() {
  section "Current memory pressure"
  vm_stat | tee -a "${REPORT_FILE}"
  log ""
  log "Top memory processes:"
  printf '%-8s %10s %7s  %s\n' "PID" "RSS" "%MEM" "COMMAND" | tee -a "${REPORT_FILE}"
  ps -axo pid=,rss=,pmem=,comm= \
    | sort -k2 -nr \
    | head -n 15 \
    | awk '{pid=$1; rss=$2; pmem=$3; $1=$2=$3=""; sub(/^ +/, ""); printf "%-8s %9.1fMB %6s%%  %s\n", pid, rss / 1024, pmem, $0}' \
    | tee -a "${REPORT_FILE}"
}

cleanup_candidates() {
  section "Cleanup candidates"
  print_path_size "User caches" "${HOME}/Library/Caches"
  print_path_size "User logs" "${HOME}/Library/Logs"
  print_path_size "Trash" "${HOME}/.Trash"
  print_path_size "Downloads" "${HOME}/Downloads"
  print_path_size "Homebrew cache" "${HOME}/Library/Caches/Homebrew"
  print_path_size "npm cache" "${HOME}/.npm"
  print_path_size "pnpm store" "${HOME}/Library/pnpm/store"
  print_path_size "Yarn cache" "${HOME}/Library/Caches/Yarn"
  print_path_size "pip cache" "${HOME}/Library/Caches/pip"
  print_path_size "Go build cache" "${HOME}/Library/Caches/go-build"
  print_path_size "Xcode derived data" "${HOME}/Library/Developer/Xcode/DerivedData"
  print_path_size "CoreSimulator devices" "${HOME}/Library/Developer/CoreSimulator/Devices"
  print_path_size "Docker data" "${HOME}/Library/Containers/com.docker.docker/Data"
}

safe_delete_contents() {
  local label="$1"
  local path="$2"

  if ! path_exists "${path}"; then
    log "Skipping ${label}: not found"
    return
  fi

  local before
  before="$(human_size "${path}")"
  log "${label}: ${before} at ${path}"

  if confirm "Delete contents of ${label}?"; then
    find "${path}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    log "Deleted contents of ${label}. Current size: $(human_size "${path}")"
  else
    log "Skipped ${label}."
  fi
}

delete_old_user_logs() {
  local path="${HOME}/Library/Logs"

  if ! path_exists "${path}"; then
    log "Skipping old user logs: not found"
    return
  fi

  log "Old user logs: $(human_size "${path}") at ${path}"
  if confirm "Delete user log files older than 30 days?"; then
    find "${path}" -type f -mtime +30 -delete 2>/dev/null || true
    log "Deleted old user logs. Current size: $(human_size "${path}")"
  else
    log "Skipped old user logs."
  fi
}

run_tool_cleanup() {
  section "Tool-specific cleanup"

  if command -v brew >/dev/null 2>&1; then
    if confirm "Run 'brew cleanup -s'?"; then
      brew cleanup -s 2>&1 | tee -a "${REPORT_FILE}" || log "brew cleanup failed."
    else
      log "Skipped Homebrew cleanup."
    fi
  else
    log "Homebrew not found."
  fi

  if command -v npm >/dev/null 2>&1; then
    if confirm "Run 'npm cache verify'?"; then
      npm cache verify 2>&1 | tee -a "${REPORT_FILE}" || log "npm cache verify failed."
    else
      log "Skipped npm cache verify."
    fi
  else
    log "npm not found."
  fi

  if command -v docker >/dev/null 2>&1; then
    log "Docker cleanup is not automatic because it can remove reusable images."
    if confirm "Run 'docker system df' to inspect Docker usage?"; then
      docker system df 2>&1 | tee -a "${REPORT_FILE}" || log "docker system df failed."
    fi
    if confirm "Run 'docker system prune' to remove stopped containers, unused networks, dangling images and build cache?"; then
      docker system prune 2>&1 | tee -a "${REPORT_FILE}" || log "docker system prune failed."
    else
      log "Skipped Docker prune."
    fi
  else
    log "Docker not found."
  fi
}

run_scan() {
  disk_summary
  memory_summary
  cleanup_candidates
  list_largest_children "Largest items in home" "${HOME}" 25
  list_largest_children "Largest items in Library" "${HOME}/Library" 25
  list_largest_children "Largest applications" "/Applications" 25
  section "Notes"
  log "This script mostly frees disk space. It reports RAM pressure, but deleting caches does not directly reduce RAM usage."
  log "Review Downloads and large app data manually before deleting personal files."
}

run_clean() {
  run_scan
  section "Conservative cleanup"
  safe_delete_contents "Trash" "${HOME}/.Trash"
  delete_old_user_logs
  safe_delete_contents "User caches" "${HOME}/Library/Caches"
  safe_delete_contents "Homebrew cache" "${HOME}/Library/Caches/Homebrew"
  safe_delete_contents "Yarn cache" "${HOME}/Library/Caches/Yarn"
  safe_delete_contents "pip cache" "${HOME}/Library/Caches/pip"
  safe_delete_contents "Go build cache" "${HOME}/Library/Caches/go-build"
  run_tool_cleanup
  section "After cleanup"
  disk_summary
}

main() {
  case "${MODE}" in
    scan|clean|help|--help|-h)
      ;;
    *)
      usage
      exit 2
      ;;
  esac

  if [[ "${MODE}" == "help" || "${MODE}" == "--help" || "${MODE}" == "-h" ]]; then
    usage
    exit 0
  fi

  mkdir -p "${REPORT_DIR}"
  : > "${REPORT_FILE}"

  log "macOS monthly maintenance report"
  log "Started: $(date)"
  log "Mode: ${MODE}"
  log "Report: ${REPORT_FILE}"

  if [[ "${MODE}" == "scan" ]]; then
    run_scan
  else
    run_clean
  fi

  section "Done"
  log "Finished: $(date)"
  log "Report saved to: ${REPORT_FILE}"
}

main "$@"
