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
  (( PASS++ ))
}

fail() {
  echo -e "${RED}[ FAIL ]${NC} $1"
  (( FAIL++ ))
}

section() {
  echo ""
  echo -e "${BOLD}=== $1 ===${NC}"
}

# --- Checks ---

check_zabbix_agent() {
  if systemctl is-active --quiet zabbix-agent 2>/dev/null; then
    pass "zabbix-agent is running"
  else
    fail "zabbix-agent is not running"
  fi
}

check_mdatp() {
  if systemctl is-active --quiet mdatp 2>/dev/null; then
    pass "mdatp is running"
    echo ""
    echo -e "${BOLD}mdatp health:${NC}"
    mdatp health 2>&1 | sed 's/^/  /'
  else
    fail "mdatp is not running"
  fi
}

check_keepalived() {
  if systemctl is-active --quiet keepalived 2>/dev/null; then
    pass "keepalived is running"

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
        echo "  Role: MASTER (active node)"
        echo "  VIP(s) assigned: ${assigned[*]}"
      else
        echo "  Role: BACKUP (standby node)"
        echo "  VIP(s) from config: ${vips[*]}"
      fi
    else
      echo "  VIP: (could not determine — check $config)"
    fi
  else
    fail "keepalived is not running"
  fi
}

# --- Main ---

section "Services"
check_zabbix_agent
check_mdatp
check_keepalived

echo ""
echo "----------------------------------------"
echo -e "Result: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"

[[ $FAIL -eq 0 ]]
