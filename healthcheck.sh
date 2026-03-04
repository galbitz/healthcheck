#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0

pass() {
  echo -e "${GREEN}[  OK  ]${NC} $1"
  (( ++PASS ))
}

fail() {
  echo -e "${RED}[ FAIL ]${NC} $1"
  (( ++FAIL ))
}

section() {
  echo ""
  echo -e "${BOLD}=== $1 ===${NC}"
}

# --- Checks ---

check_system_info() {
  local main_ip kernel hostname last_update
  main_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ { print $7; exit }')
  kernel=$(uname -r)
  hostname=$(hostname -f)
  last_update=$(stat -c '%y' /var/lib/dpkg/info 2>/dev/null \
    || stat -c '%y' /var/cache/yum 2>/dev/null \
    || echo "unknown")
  last_update=${last_update%%.*}  # trim sub-seconds

  echo "  IP:          ${main_ip:-unknown}"
  echo "  Kernel:      ${kernel}"
  echo "  Hostname:    ${hostname}"
  echo "  Last update: ${last_update}"

  local config="/etc/keepalived/keepalived.conf"
  local vips=()
  if [[ -f "$config" ]]; then
    mapfile -t vips < <(awk '/virtual_ipaddress/,/\}/' "$config" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
  fi

  if [[ ${#vips[@]} -gt 0 ]]; then
    local assigned=()
    for vip in "${vips[@]}"; do
      ip addr show 2>/dev/null | grep -q "$vip" && assigned+=("$vip")
    done

    if [[ ${#assigned[@]} -gt 0 ]]; then
      echo "  Role:        MASTER (active node)"
      echo "  VIP(s):      ${assigned[*]}"
    else
      echo "  Role:        BACKUP (standby node)"
      echo "  VIP(s):      ${vips[*]} (from config, not assigned)"
    fi
  fi
}

check_zabbix_agent() {
  if systemctl is-active --quiet zabbix-agent 2>/dev/null; then
    pass "zabbix-agent is running"
  else
    fail "zabbix-agent is not running"
  fi
}

check_mdatp() {
  if ! systemctl list-unit-files mdatp.service &>/dev/null || ! systemctl list-unit-files mdatp.service | grep -q mdatp; then
    return
  fi
  if systemctl is-active --quiet mdatp 2>/dev/null; then
    pass "mdatp is running"
    local health
    health=$(mdatp health 2>/dev/null)
    local expiration org_id
    expiration=$(echo "$health" | awk -F': ' '/product_expiration/ { print $2; exit }')
    org_id=$(echo "$health" | awk -F': ' '/org_id/ { print $2; exit }')
    echo "  product_expiration : ${expiration:-unknown}"
    echo "  org_id             : ${org_id:-unknown}"
    if ! date -d "$expiration" &>/dev/null 2>&1; then
      fail "mdatp product_expiration is not a valid date: ${expiration:-empty}"
    fi
    org_id="${org_id//\"/}"
    if [[ -z "$org_id" ]]; then
      fail "mdatp org_id is empty"
    fi
  else
    fail "mdatp is not running"
  fi
}

check_keepalived() {
  if ! systemctl list-unit-files keepalived.service 2>/dev/null | grep -q keepalived; then
    return
  fi
  if systemctl is-active --quiet keepalived 2>/dev/null; then
    pass "keepalived is running"
  else
    fail "keepalived is not running"
  fi
}

check_vault() {
  if ! systemctl list-unit-files vault.service 2>/dev/null | grep -q vault; then
    return
  fi
  if systemctl is-active --quiet vault 2>/dev/null; then
    pass "vault is running"
    local status
    status=$(vault status 2>/dev/null) || true
    local sealed
    sealed=$(echo "$status" | awk '/^Sealed/ { print $2; exit }')
    echo "  Sealed: ${sealed:-unknown}"
    if [[ "$sealed" == "true" ]]; then
      fail "vault is sealed"
    fi
  else
    fail "vault is not running"
  fi
}

# --- Main ---

section "System Info"
check_system_info

section "Services"
check_zabbix_agent
check_mdatp
check_keepalived
check_vault

echo ""
echo "----------------------------------------"
echo -e "Result: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"

[[ $FAIL -eq 0 ]]
