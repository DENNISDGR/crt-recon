#!/usr/bin/env bash

# ─────────────────────────────────────────────
#  crt.sh — Certificate Transparency Recon Tool
# ─────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

usage() {
    echo -e "${BOLD}Usage:${RESET}"
    echo -e "  $(basename "$0") -d <domain> [-s <substring>] [-w <outfile>] [--alive] [-t <threads>] [-x <proxy>]"
    echo ""
    echo -e "${BOLD}Flags:${RESET}"
    echo -e "  ${CYAN}-d${RESET}       Target domain           (required)  e.g. facebook.com"
    echo -e "  ${CYAN}-s${RESET}       Filter by substring     (optional)  e.g. dev, staging, api"
    echo -e "  ${CYAN}-w${RESET}       Write output to file    (optional)  e.g. output.txt"
    echo -e "  ${CYAN}--alive${RESET}  Probe hosts, only output alive ones"
    echo -e "  ${CYAN}-t${RESET}       Concurrent probes       (default: 50)"
    echo -e "  ${CYAN}-x${RESET}       Proxy for alive checks  (optional)  e.g. socks5://127.0.0.1:1080"
    echo -e "  ${CYAN}-h${RESET}       Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${RESET}"
    echo -e "  $(basename "$0") -d facebook.com"
    echo -e "  $(basename "$0") -d facebook.com -s dev"
    echo -e "  $(basename "$0") -d facebook.com --alive -t 100 -w results.txt"
    echo -e "  $(basename "$0") -d facebook.com --alive -x socks5://127.0.0.1:1080 -w results.txt"
    exit 0
}

# ── Argument parsing ──────────────────────────
DOMAIN=""
SUBSTRING=""
OUTFILE=""
ALIVE=false
THREADS=50
PROXY=""

ARGS=()
for arg in "$@"; do
    [[ "$arg" == "--alive" ]] && ALIVE=true || ARGS+=("$arg")
done
set -- "${ARGS[@]}"

while getopts ":d:s:w:t:x:h" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        s) SUBSTRING="$OPTARG" ;;
        w) OUTFILE="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        x) PROXY="$OPTARG" ;;
        h) usage ;;
        :)
            echo -e "${RED}[!] Option -$OPTARG requires an argument.${RESET}" >&2
            exit 1
            ;;
        \?)
            echo -e "${RED}[!] Unknown option: -$OPTARG${RESET}" >&2
            exit 1
            ;;
    esac
done

# ── Validate ──────────────────────────────────
if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}[!] Domain is required. Use -d <domain>${RESET}"
    echo ""
    usage
fi

if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || (( THREADS < 1 )); then
    echo -e "${RED}[!] -t must be a positive integer.${RESET}"
    exit 1
fi

# ── Dependency check ──────────────────────────
for cmd in curl jq xargs; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}[!] Required tool not found: ${cmd}${RESET}"
        exit 1
    fi
done

# ── Banner ────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "  ██████╗██████╗ ████████╗   ███████╗██╗  ██╗"
echo " ██╔════╝██╔══██╗╚══██╔══╝   ██╔════╝██║  ██║"
echo " ██║     ██████╔╝   ██║      ███████╗███████║"
echo " ██║     ██╔══██╗   ██║      ╚════██║██╔══██║"
echo " ╚██████╗██║  ██║   ██║      ███████║██║  ██║"
echo "  ╚═════╝╚═╝  ╚═╝   ╚═╝      ╚══════╝╚═╝  ╚═╝"
echo -e "${RESET}"
echo -e "  ${BOLD}Certificate Transparency Recon${RESET} via crt.sh"
echo -e "  ──────────────────────────────────────────"
echo -e "  ${BOLD}Domain   :${RESET} $DOMAIN"
[[ -n "$SUBSTRING" ]]  && echo -e "  ${BOLD}Filter   :${RESET} $SUBSTRING"
[[ -n "$OUTFILE"   ]]  && echo -e "  ${BOLD}Output   :${RESET} $OUTFILE"
[[ "$ALIVE" == true ]] && echo -e "  ${BOLD}Alive    :${RESET} enabled (${THREADS} threads)"
[[ -n "$PROXY"     ]]  && echo -e "  ${BOLD}Proxy    :${RESET} $PROXY"
echo -e "  ──────────────────────────────────────────"
echo ""

# ── Fetch results ─────────────────────────────
echo -e "${YELLOW}[*] Querying crt.sh for: ${BOLD}$DOMAIN${RESET}"

RAW=$(curl -s "https://crt.sh/?q=%25.${DOMAIN}&output=json")

if [[ -z "$RAW" ]]; then
    echo -e "${RED}[!] No response from crt.sh. Check your connection.${RESET}"
    exit 1
fi

if echo "$RAW" | grep -q "502 Bad Gateway"; then
    echo -e "${RED}[!] crt.sh returned 502 Bad Gateway — server is down or rate limiting.${RESET}"
    echo -e "    Wait a moment and try again."
    exit 1
fi

if ! echo "$RAW" | jq empty 2>/dev/null; then
    echo -e "${RED}[!] crt.sh returned an invalid response (possibly rate-limited or down).${RESET}"
    echo -e "    Try again in a few seconds."
    exit 1
fi

# ── Parse & filter ────────────────────────────
RESULTS=$(echo "$RAW" \
    | jq -r '.[] | .name_value' \
    | tr ',' '\n' \
    | sed 's/^\*\.//' \
    | sort -u)

if [[ -n "$SUBSTRING" ]]; then
    RESULTS=$(echo "$RESULTS" | grep "$SUBSTRING")
fi

COUNT=$(echo "$RESULTS" | grep -c '.' 2>/dev/null || echo 0)

if [[ -z "$RESULTS" ]]; then
    echo -e "${RED}[!] No results found.${RESET}"
    [[ -n "$SUBSTRING" ]] && echo -e "    Try a different substring or remove the -s filter."
    exit 0
fi

echo -e "${GREEN}[+] Found ${BOLD}${COUNT}${RESET}${GREEN} unique subdomain(s):${RESET}"
echo ""
echo "$RESULTS"
echo ""

# ── Alive check ───────────────────────────────
if [[ "$ALIVE" == true ]]; then
    echo -e "${YELLOW}[*] Probing ${COUNT} hosts with ${THREADS} concurrent threads...${RESET}"
    echo ""

    TMPFILE=$(mktemp)

    # Export vars so the subshell spawned by xargs can access them
    export PROXY

    probe() {
        local host="$1"
        local proxy_flag=""
        [[ -n "$PROXY" ]] && proxy_flag="--proxy $PROXY"
        for scheme in https http; do
            code=$(curl -s -o /dev/null -w "%{http_code}" \
                --max-time 5 $proxy_flag "$scheme://$host" 2>/dev/null)
            if [[ "$code" != "000" && -n "$code" ]]; then
                echo "$host $scheme $code"
                return
            fi
        done
    }
    export -f probe

    # Run probes concurrently, collect to temp file
    echo "$RESULTS" | xargs -P "$THREADS" -I {} bash -c 'probe "$@"' _ {} > "$TMPFILE"

    # Sort output for consistent display
    ALIVE_RESULTS=$(sort "$TMPFILE")
    rm -f "$TMPFILE"

    if [[ -z "$ALIVE_RESULTS" ]]; then
        echo -e "${RED}[!] No alive hosts found.${RESET}"
        exit 0
    fi

    ALIVE_COUNT=$(echo "$ALIVE_RESULTS" | grep -c '.' 2>/dev/null || echo 0)

    # Pretty print
    while read -r line; do
        host=$(echo "$line" | awk '{print $1}')
        scheme=$(echo "$line" | awk '{print $2}')
        code=$(echo "$line" | awk '{print $3}')
        echo -e "  ${GREEN}[+]${RESET} $host ${BOLD}($scheme — $code)${RESET}"
    done <<< "$ALIVE_RESULTS"

    echo ""
    echo -e "${GREEN}[+] ${BOLD}${ALIVE_COUNT}${RESET}${GREEN} host(s) alive${RESET}"
    echo ""

    if [[ -n "$OUTFILE" ]]; then
        echo "$ALIVE_RESULTS" | awk '{print $1}' > "$OUTFILE"
        echo -e "${GREEN}[+] Alive hosts saved to: ${BOLD}${OUTFILE}${RESET}"
    fi

# ── Write to file (no alive check) ───────────
elif [[ -n "$OUTFILE" ]]; then
    echo "$RESULTS" > "$OUTFILE"
    echo -e "${GREEN}[+] Results saved to: ${BOLD}${OUTFILE}${RESET}"
fi
