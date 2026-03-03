# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the script

```bash
bash healthcheck.sh
```

Exit code is `0` if all checks pass, `1` if any fail.

## Architecture

A single script (`healthcheck.sh`) with a fixed structure:

1. **Color constants** — `GREEN`, `RED`, `BOLD`, `NC`
2. **Counters** — `PASS` and `FAIL` (global integers)
3. **Output helpers** — `pass "msg"`, `fail "msg"`, `section "name"`
4. **Check functions** — one function per service/topic, named `check_*`
5. **Main block** — calls `section` then each `check_*` function, prints summary, exits based on `$FAIL`

## Adding a new check

Define a `check_<name>()` function in the `# --- Checks ---` section, then call it from the main block under the appropriate `section`. Use `pass` / `fail` for results and indent extra detail output with two spaces for readability.

## Check conventions

- Service checks use `systemctl is-active --quiet <service> 2>/dev/null`
- If a service is up and has extra diagnostic output to show, print it immediately after the `pass` line, indented with `sed 's/^/  /'` or explicit `echo "  ..."`
- Role/state detection (e.g. keepalived MASTER/BACKUP) is done by inspecting live system state (`ip addr show`) cross-referenced against config files
