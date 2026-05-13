# crt.sh — Certificate Transparency Recon Tool

Bash scripts for subdomain enumeration via [certificate transparency logs](https://crt.sh).

---

## Features

- Subdomain discovery via crt.sh CT logs
- Filter results by substring (e.g. `dev`, `staging`, `api`)
- Concurrent host probing to find alive subdomains
- Proxy support for alive checks (SOCKS5, SOCKS4, HTTP)
- Output to file
- Handles 502 / invalid responses from crt.sh gracefully

## Requirements

- `curl`
- `jq`
- `xargs` (standard on Linux/macOS)

---

## Installation

```bash
git clone https://github.com/DENNISDGR/crt-recon.git
cd crt-recon
chmod +x crt.sh
```

---

## Usage

```
crt.sh -d <domain> [-s <substring>] [-w <outfile>] [--alive] [-t <threads>] [-x <proxy>]
```

| Flag | Description | Default |
|------|-------------|---------|
| `-d` | Target domain *(required)* | — |
| `-s` | Filter results by substring | — |
| `-w` | Write output to file | — |
| `--alive` | Probe each host and only keep alive ones | — |
| `-t` | Number of concurrent probes | `50` |
| `-x` | Proxy for alive checks (`socks5://`, `http://`) | — |
| `-h` | Show help | — |

---

## Examples

```bash
# All subdomains for a domain
./crt.sh -d facebook.com

# Filter for dev subdomains only
./crt.sh -d facebook.com -s dev

# Alive check with 100 threads, save results
./crt.sh -d facebook.com --alive -t 100 -w results.txt

# Route alive checks through a SOCKS5 proxy
./crt.sh -d facebook.com --alive -x socks5://127.0.0.1:1080

# Full combo
./crt.sh -d facebook.com -s dev --alive -t 100 -x socks5://127.0.0.1:1080 -w dev_alive.txt
```

---

## How it works

1. Queries `crt.sh` for all certificates issued to `*.domain` 
2. Extracts every `name_value` field (covers multi-SAN certs)
3. Splits, strips wildcard prefixes, deduplicates
4. Optionally filters by substring via `grep`
5. Optionally probes each host over `https` then `http` using concurrent `xargs -P` workers

---

## Notes

- crt.sh occasionally returns 502 — the script handles this and exits cleanly
- Alive probing uses a 5s timeout per host per scheme
- The proxy flag only applies to alive probes, not the crt.sh query itself
