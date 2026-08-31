#!/usr/bin/env bash
#
# Robinhood Chain RPC node kurulum scripti / setup script
# Kaynak / Source: https://docs.robinhood.com/chain/run-a-full-node/
#
# Bu script resmi dokumanin adimlarini uygular. Config dosyalari Robinhood'un
# kendi CDN'inden, docker imaji dokumanin sabitledigi surumden, snapshot ise
# Arbitrum'un resmi snapshot indeksinden geliyor. Hicbiri elle yazilmadi.

set -Eeuo pipefail

if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  RESET="$(printf '\033[0m')"
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  CYAN="$(printf '\033[36m')"
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN="";
fi

##############################
# DIL / LANGUAGE
##############################
UI_LANG=""   # tr | en

# Iki dilli metin. Her mesajin iki hali yan yana duruyor, boylece birini
# degistirip digerini unutmak zor.
m() { if [[ "$UI_LANG" == "en" ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

print_header() {
  echo -e "${BLUE}============================================${RESET}"
  echo -e "${BLUE}    UFUKDEGEN TARAFINDAN HAZIRLANMIŞTIR    ${RESET}"
  echo -e "${BLUE}============================================${RESET}"
  echo ""
}

section() { echo -e "\n${BOLD}${BLUE}========== $* ==========${RESET}\n"; }
info()    { echo -e "${CYAN}[$(m "bilgi" "info")]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[$(m "uyarı" "warn")]${RESET} $*"; }
ok()      { echo -e "${GREEN}[$(m "tamam" "ok")]${RESET} $*"; }
err()     { echo -e "${RED}[$(m "hata" "error")]${RESET} $*"; }
abort()   { err "$*"; exit 1; }

trap 'err "$(m "Beklenmeyen hata, satır" "Unexpected error on line") $LINENO."' ERR

confirm() {
  local prompt="$1" default="${2:-Y}" reply
  if [[ "${NON_INTERACTIVE}" == "1" ]]; then
    [[ "${default}" =~ ^[Yy]$ ]] && return 0 || return 1
  fi
  read -rp "${prompt} [Y/n]: " reply || true
  [[ -z "$reply" ]] && reply="${default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

##############################
# ARGÜMANLAR / ARGUMENTS
##############################
NETWORK="mainnet"          # mainnet | testnet
EXPOSE_RPC="no"            # yes | no
RPC_PORT="8547"
WS_PORT="8548"
ALLOWED_IP=""
L1_RPC=""
L1_BEACON=""
DATA_ROOT="/root/rh"
USE_SNAPSHOT="yes"
SNAPSHOT_TYPE="pruned"     # pruned | full-path | archive-path
FORWARD_TARGET=""          # bos ise resmi sequencer / empty means the official sequencer
NON_INTERACTIVE="0"
UNINSTALL_ONLY="0"
DRY_RUN="0"

# Dokumanin sabitledigi surum. Docker Hub'da daha yenisi olabilir, biz
# dokumani takip ediyoruz: resmi rehber ne diyorsa o kurulur.
NITRO_IMAGE="offchainlabs/nitro-node:v3.11.2-3599aca"
CDN="https://cdn.robinhood.com/assets/generated_assets/hoodchain_docsite/chain-node-configs"
SNAPSHOT_INDEX="https://snapshot-explorer.arbitrum.io/api/snapshots"
SERVICE="robinhood-rpc"
SNAPSHOT_CLEANUP_SERVICE="${SERVICE}-snapshot-cleanup"
CONTAINER_HOME="/home/user"
CONTAINER_UID="1000"
CONTAINER_GID="1000"

usage() {
  if [[ "$UI_LANG" == "en" ]]; then
    cat <<EOF
${BOLD}Robinhood Chain RPC node setup${RESET}

Usage:
  sudo ./script.sh [options]

Options:
  --lang <tr|en>                Interface language (asked at start if omitted)
  --network <mainnet|testnet>   Network to install (default: mainnet)
  --l1-rpc <url>                Ethereum L1 execution RPC URL (required)
  --l1-beacon <url>             Ethereum L1 beacon URL (required)
  --expose-rpc <yes|no>         Open the RPC to other machines (default: no)
  --allowed-ip <ip>             When opening it, allow only this IP
  --rpc-port <port>             HTTP RPC port (default: 8547)
  --ws-port <port>              WebSocket port (default: 8548)
  --data-dir <path>             Data and config root (default: /root/rh)
  --no-snapshot                 Skip the snapshot, sync from genesis
  --snapshot-type <type>        pruned | full-path | archive-path
  --forwarding-target <url>     Where transactions are forwarded. Defaults to
                                the chain's own RPC. Read only: null
  --dry-run                     Check L1 endpoints, disk, config and snapshot.
                                Docker/node service are not installed
  --non-interactive             Ask nothing, use defaults
  --uninstall                   Remove the service and config (data is kept)
  -h, --help                    This screen

Example:
  sudo ./script.sh --lang en --network mainnet \\
    --l1-rpc https://eth-mainnet.example/v2/KEY \\
    --l1-beacon https://beacon.example
EOF
  else
    cat <<EOF
${BOLD}Robinhood Chain RPC node kurulumu${RESET}

Kullanım:
  sudo ./script.sh [seçenekler]

Seçenekler:
  --lang <tr|en>                Arayüz dili (verilmezse başta sorulur)
  --network <mainnet|testnet>   Kurulacak ağ (varsayılan: mainnet)
  --l1-rpc <url>                Ethereum L1 execution RPC adresi (zorunlu)
  --l1-beacon <url>             Ethereum L1 beacon adresi (zorunlu)
  --expose-rpc <yes|no>         RPC'yi dışarı aç (varsayılan: no)
  --allowed-ip <ip>             Dışarı açarken sadece bu IP'ye izin ver
  --rpc-port <port>             HTTP RPC portu (varsayılan: 8547)
  --ws-port <port>              WebSocket portu (varsayılan: 8548)
  --data-dir <yol>              Veri ve config kökü (varsayılan: /root/rh)
  --no-snapshot                 Snapshot indirme, sıfırdan senkronla
  --snapshot-type <tür>         pruned | full-path | archive-path
  --forwarding-target <url>     İşlemlerin iletileceği adres. Varsayılan ağın
                                kendi RPC'si. Sadece okuma için: null
  --dry-run                     L1 adresleri, disk, config ve snapshot kontrolü.
                                Docker/node servisi kurulmaz
  --non-interactive             Soru sorma, varsayılanlarla devam et
  --uninstall                   Servisi ve config'i kaldır (veri korunur)
  -h, --help                    Bu ekran

Örnek:
  sudo ./script.sh --network mainnet \\
    --l1-rpc https://eth-mainnet.example/v2/KEY \\
    --l1-beacon https://beacon.example
EOF
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang|--network|--l1-rpc|--l1-beacon|--expose-rpc|--allowed-ip|--rpc-port|--ws-port|--data-dir|--snapshot-type|--forwarding-target)
      [[ $# -ge 2 && -n "${2:-}" && "${2:-}" != --* ]] \
        || abort "$(m "Eksik değer" "Missing value"): $1"
      ;;
  esac
  case "$1" in
    --lang)           UI_LANG="${2:-}"; shift 2;;
    --network)        NETWORK="${2:-mainnet}"; shift 2;;
    --l1-rpc)         L1_RPC="${2:-}"; shift 2;;
    --l1-beacon)      L1_BEACON="${2:-}"; shift 2;;
    --expose-rpc)     EXPOSE_RPC="${2:-no}"; shift 2;;
    --allowed-ip)     ALLOWED_IP="${2:-}"; shift 2;;
    --rpc-port)       RPC_PORT="${2:-8547}"; shift 2;;
    --ws-port)        WS_PORT="${2:-8548}"; shift 2;;
    --data-dir)       DATA_ROOT="${2:-/root/rh}"; shift 2;;
    --no-snapshot)    USE_SNAPSHOT="no"; shift;;
    --snapshot-type)  SNAPSHOT_TYPE="${2:-pruned}"; shift 2;;
    --forwarding-target) FORWARD_TARGET="${2:-}"; shift 2;;
    --dry-run)        DRY_RUN="1"; shift;;
    --non-interactive) NON_INTERACTIVE="1"; shift;;
    --uninstall)      UNINSTALL_ONLY="1"; shift;;
    -h|--help)        [[ -z "$UI_LANG" ]] && UI_LANG="tr"; usage; exit 0;;
    *) [[ -z "$UI_LANG" ]] && UI_LANG="tr"; usage; abort "$(m "Bilinmeyen seçenek" "Unknown option"): $1";;
  esac
done

print_header

# Dil secimi. --lang verilmisse sorulmaz; soru sorulamayan bir ortamda
# (--non-interactive ya da terminal yok) Turkce varsayilir.
case "${UI_LANG,,}" in
  tr|en) UI_LANG="${UI_LANG,,}";;
  "")
    if [[ "$NON_INTERACTIVE" == "1" || ! -t 0 ]]; then
      UI_LANG="tr"
    else
      echo "  Dil seçin / Choose language"
      echo ""
      echo "    1) Türkçe"
      echo "    2) English"
      echo ""
      read -rp "  [1/2]: " _pick || true
      case "${_pick:-1}" in
        2) UI_LANG="en";;
        *) UI_LANG="tr";;
      esac
      echo ""
    fi
    ;;
  *) UI_LANG="tr"; echo "  (bilinmeyen dil, Türkçe kullanılıyor)"; echo "";;
esac

##############################
# ÖN KONTROLLER / PRE-CHECKS
##############################
[[ "${EUID:-$(id -u)}" -eq 0 ]] \
  || abort "$(m "Lütfen sudo ile (root) çalıştırın." "Please run this with sudo (as root).")"
command -v apt-get >/dev/null 2>&1 \
  || abort "$(m "Bu script Debian/Ubuntu (apt) içindir." "This script is for Debian/Ubuntu (apt).")"

# Docker deposu asagida Ubuntu'ya gore ekleniyor. Debian ve Ubuntu-turevi olup
# Ubuntu olmayan sistemlerde yanlis depo eklemek yerine acik bir hata veriyoruz.
. /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" =~ ^(22\.04|24\.04)$ ]] || abort "$(m \
  "Bu script yalnızca Ubuntu 22.04/24.04 üzerinde destekleniyor (bulunan: ${PRETTY_NAME:-bilinmiyor})." \
  "This script supports Ubuntu 22.04/24.04 only (found: ${PRETTY_NAME:-unknown}).")"

case "$NETWORK" in
  mainnet)
    CHAIN_ID=4663
    PARENT_NAME="Ethereum mainnet"
    PARENT_ID=1
    CHAIN_INFO="robinhood-chain-info.json"
    GENESIS="robinhood-genesis.json"
    FEED_URL="wss://feed.mainnet.chain.robinhood.com"
    SEQUENCER_URL="https://sequencer.mainnet.chain.robinhood.com"
    SNAPSHOT_CHAIN="Robinhood Chain"
    ROLLUP_ADDRESS="0x23A19d23e89166adedbDcB432518AB01e4272D94"
    ROLLUP_DEPLOYED_AT=24994238
    GENESIS_ASSERTION_TOPIC="0x901c3aee23cf4478825462caaab375c606ab83516060388344f0650340753630"
    ;;
  testnet)
    CHAIN_ID=46630
    PARENT_NAME="Ethereum Sepolia"
    PARENT_ID=11155111
    CHAIN_INFO="robinhood-chain-testnet-info.json"
    GENESIS=""
    FEED_URL="wss://feed.testnet.chain.robinhood.com"
    SEQUENCER_URL="https://sequencer.testnet.chain.robinhood.com"
    SNAPSHOT_CHAIN="Robinhood Chain Sepolia"
    ROLLUP_ADDRESS="0xdc5F8E399DBd8a9F5F87AeC4C23Beb12431b386D"
    ROLLUP_DEPLOYED_AT=10204516
    GENESIS_ASSERTION_TOPIC="0x901c3aee23cf4478825462caaab375c606ab83516060388344f0650340753630"
    ;;
  *) abort "$(m "--network sadece mainnet veya testnet olabilir." "--network must be mainnet or testnet.")";;
esac

[[ -z "$FORWARD_TARGET" ]] && FORWARD_TARGET="$SEQUENCER_URL"

for _port in "$RPC_PORT" "$WS_PORT"; do
  if [[ ! "$_port" =~ ^[0-9]+$ ]] || (( _port < 1 || _port > 65535 )); then
    abort "$(m "Geçersiz port: ${_port}" "Invalid port: ${_port}")"
  fi
done
[[ "$RPC_PORT" != "$WS_PORT" ]] || abort "$(m \
  "HTTP ve WebSocket portları farklı olmalı." \
  "HTTP and WebSocket ports must be different.")"

case "$EXPOSE_RPC" in
  yes|no) ;;
  *) abort "$(m "--expose-rpc yes veya no olmalı." "--expose-rpc must be yes or no.")";;
esac

case "$SNAPSHOT_TYPE" in
  pruned|full-path|archive-path) ;;
  *) abort "$(m \
    "--snapshot-type pruned, full-path veya archive-path olabilir." \
    "--snapshot-type can be pruned, full-path or archive-path.")";;
esac

[[ "$L1_RPC" != *$'\n'* && "$L1_BEACON" != *$'\n'* ]] || abort "$(m \
  "L1 adreslerinde satır sonu olamaz." "L1 URLs cannot contain newlines.")"

CONFIG_DIR="${DATA_ROOT}/config"
DATA_DIR="${DATA_ROOT}/robinhood-nitro-data"
ENV_FILE="${CONFIG_DIR}/rpc.env"
SNAPSHOT_DOWNLOAD_DIR="${DATA_DIR}/snapshot-download"
if [[ "$EXPOSE_RPC" == "yes" ]]; then
  RPC_BIND_ADDR="0.0.0.0"
else
  RPC_BIND_ADDR="127.0.0.1"
fi

[[ "$DATA_ROOT" == /* && "$DATA_ROOT" != "/" ]] || abort "$(m \
  "--data-dir mutlak ve güvenli bir yol olmalı; / kullanılamaz." \
  "--data-dir must be a safe absolute path; / is not allowed.")"
[[ "$DATA_ROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || abort "$(m \
  "--data-dir boşluk veya özel karakter içermemeli." \
  "--data-dir must not contain spaces or special characters.")"

##############################
# KALDIRMA / UNINSTALL
##############################
if [[ "$UNINSTALL_ONLY" == "1" ]]; then
  section "$(m "KALDIRMA" "UNINSTALL")"
  systemctl disable --now "${SNAPSHOT_CLEANUP_SERVICE}" 2>/dev/null || true
  systemctl disable --now "${SERVICE}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  rm -f "/etc/systemd/system/${SNAPSHOT_CLEANUP_SERVICE}.service"
  systemctl daemon-reload
  docker rm -f "${SERVICE}" 2>/dev/null || true
  rm -rf "${CONFIG_DIR}"
  ok "$(m "Servis ve config kaldırıldı." "Service and config removed.")"
  warn "$(m "Veri klasörü duruyor" "The data directory is still there"): ${DATA_DIR}"
  warn "$(m "Diski boşaltmak isterseniz elle silin" "Remove it by hand to free the disk"): rm -rf ${DATA_DIR}"
  exit 0
fi

##############################
# GEREKSINIMLER / REQUIREMENTS
##############################
section "$(m "SİSTEM KONTROLÜ" "SYSTEM CHECK")"

RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
CPU_COUNT=$(nproc)
info "CPU: ${CPU_COUNT}"
if (( CPU_COUNT < 8 )); then
  warn "$(m "Resmi gereksinim en az 8 modern CPU çekirdeği." \
          "The official requirement is at least 8 modern CPU cores.")"
fi
info "RAM: ${RAM_GB} GB"
if (( RAM_GB < 60 )); then
  warn "$(m "Resmi doküman en az 64 GB RAM istiyor, önerdiği 128 GB. Sizde ${RAM_GB} GB var." \
          "The official docs ask for 64 GB of RAM and recommend 128 GB. You have ${RAM_GB} GB.")"
  # Kuru denemede durmuyoruz: hicbir sey kurulmayacagi icin donanimi yetersiz
  # olan biri de L1 adreslerini ve config'i buradan dogrulayabilsin.
  if [[ "$DRY_RUN" == "1" ]]; then
    warn "$(m "Kuru deneme olduğu için devam ediliyor." "Dry run, carrying on anyway.")"
  else
    confirm "$(m "Yine de devam edilsin mi?" "Continue anyway?")" "N" \
      || abort "$(m "Kurulum iptal edildi." "Setup cancelled.")"
  fi
else
  ok "$(m "RAM yeterli." "RAM is enough.")"
fi

mkdir -p "${DATA_ROOT}"
FREE_GB=$(df -BG --output=avail "${DATA_ROOT}" | tail -1 | tr -dc '0-9')
info "$(m "Boş disk" "Free disk") (${DATA_ROOT}): ${FREE_GB} GB"

DATA_FS=$(findmnt -n -o FSTYPE -T "${DATA_ROOT}" 2>/dev/null || true)
case "$DATA_FS" in
  nfs*|cifs|fuse.sshfs|ceph|glusterfs)
    abort "$(m "Veri yolu ağ diskinde (${DATA_FS}); yerel NVMe gerekiyor." \
                "The data path is on network storage (${DATA_FS}); local NVMe is required.")";;
esac
if ! lsblk -dn -o ROTA | grep -q '^0$'; then
  warn "$(m "Sistemde NVMe/SSD doğrulanamadı; Nitro için yerel NVMe gerekiyor." \
          "No NVMe/SSD could be verified; Nitro requires locally attached NVMe.")"
fi

if command -v timedatectl >/dev/null 2>&1 && \
   [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" != "yes" ]]; then
  warn "$(m "Sistem saati NTP ile senkron görünmüyor." \
          "The system clock does not appear to be synchronized by NTP.")"
fi

# Bu degerler yalnizca erken uyari tabanidir. Resmi hesap guncel zincir
# boyutunun 2 kati + %20'dir ve snapshot'in sikistirilmis boyutuyla ayni degildir.
if [[ "$NETWORK" == "mainnet" ]]; then NEED_GB=1150; else NEED_GB=600; fi
if (( FREE_GB < NEED_GB )); then
  warn "$(m "${NETWORK} için ön kontrol tabanı ${NEED_GB} GB, sizde ${FREE_GB} GB var." \
          "The ${NETWORK} preflight floor is ${NEED_GB} GB; you have ${FREE_GB} GB.")"
  warn "$(m "Bu kesin yeterlilik hesabı değildir; resmi 2 x zincir boyutu + %20 kuralını uygulayın." \
          "This is not a capacity guarantee; apply the official 2 x chain size + 20% rule.")"
  if [[ "$USE_SNAPSHOT" == "yes" ]]; then
    warn "$(m "Snapshot açılırken arşiv ve açılmış veri bir süre birlikte diskte durur." \
            "While the snapshot unpacks, the archive and the unpacked data sit on disk together.")"
  else
    warn "$(m "Genesis'ten senkron sırasında veritabanı uzun süre büyümeye devam eder." \
            "During a genesis sync the database keeps growing for a long time.")"
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    warn "$(m "Kuru deneme olduğu için devam ediliyor." "Dry run, carrying on anyway.")"
  else
    confirm "$(m "Yine de devam edilsin mi?" "Continue anyway?")" "N" \
      || abort "$(m "Kurulum iptal edildi." "Setup cancelled.")"
  fi
else
  ok "$(m "Disk yeterli." "Disk is enough.")"
fi

##############################
# PAKETLER / PACKAGES
##############################
section "$(m "PAKETLER" "PACKAGES")"
if [[ "$DRY_RUN" == "1" ]]; then
  # Kuru denemede docker kurmuyoruz ama curl ve jq lazim, ve taze bir sunucuda
  # jq kurulu gelmez. Kucuk araclari burada da kuruyoruz, yoksa "kuru deneme"
  # tam da en cok ise yarayacagi yerde, sifirdan kurulan makinede calismiyordu.
  if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    info "$(m "Kuru deneme için curl ve jq kuruluyor (docker kurulmayacak)..." \
            "Installing curl and jq for the dry run (docker is skipped)...")"
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl jq >/dev/null 2>&1
  fi
  ok "$(m "Kuru deneme: docker ve diğer paketler atlanıyor." "Dry run: docker and the rest are skipped.")"
else
  info "$(m "Paket listesi güncelleniyor..." "Updating the package list...")"
  DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
  info "$(m "Gerekli araçlar kuruluyor..." "Installing the tools we need...")"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl jq wget gnupg lsb-release ufw >/dev/null 2>&1
  ok "$(m "Araçlar hazır." "Tools are ready.")"

  if ! command -v docker >/dev/null 2>&1; then
    info "$(m "Docker kuruluyor..." "Installing Docker...")"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
    systemctl enable --now docker
    ok "$(m "Docker kuruldu." "Docker installed.")"
  else
    systemctl enable --now docker >/dev/null 2>&1 \
      || abort "$(m "Docker servisi başlatılamadı." "The Docker service could not be started.")"
    ok "$(m "Docker zaten kurulu" "Docker is already installed"): $(docker --version | cut -d, -f1)"
  fi
fi

##############################
# L1 / ETHEREUM
##############################
section "$(m "ETHEREUM L1 BAĞLANTISI" "ETHEREUM L1 CONNECTION")"

if [[ "$UI_LANG" == "en" ]]; then
  cat <<EOF
Robinhood Chain writes its data to Ethereum as blobs. For the node to read that
data it needs two endpoints:

  1) L1 execution RPC   (${PARENT_NAME}, chainId ${PARENT_ID})
  2) L1 beacon URL      (blob data lives only there)

If you run your own Ethereum node, use its URLs. Otherwise get them from a
provider. This is not optional, the node cannot sync without them.
EOF
else
  cat <<EOF
Robinhood Chain verisini Ethereum'a yazar, blob olarak. Node'un çalışabilmesi
için iki adrese ihtiyacı var:

  1) L1 execution RPC   (${PARENT_NAME}, chainId ${PARENT_ID})
  2) L1 beacon adresi   (blob verisi sadece burada durur)

Kendi Ethereum node'unuz varsa onun adreslerini, yoksa bir sağlayıcının
adreslerini girin. Bu adım isteğe bağlı değil, node bunlarsız senkronlanamaz.
EOF
fi
echo ""

if [[ -z "$L1_RPC" ]]; then
  [[ "$NON_INTERACTIVE" == "1" ]] && abort "$(m "--l1-rpc verilmedi." "--l1-rpc was not given.")"
  read -rp "$(m "L1 execution RPC adresi" "L1 execution RPC URL"): " L1_RPC
fi
if [[ -z "$L1_BEACON" ]]; then
  [[ "$NON_INTERACTIVE" == "1" ]] && abort "$(m "--l1-beacon verilmedi." "--l1-beacon was not given.")"
  read -rp "$(m "L1 beacon adresi" "L1 beacon URL"): " L1_BEACON
fi
[[ -n "$L1_RPC" && -n "$L1_BEACON" ]] \
  || abort "$(m "İki adres de zorunlu." "Both URLs are required.")"
[[ "$L1_RPC" != *$'\n'* && "$L1_BEACON" != *$'\n'* ]] || abort "$(m \
  "L1 adreslerinde satır sonu olamaz." "L1 URLs cannot contain newlines.")"

info "$(m "L1 execution adresi doğrulanıyor..." "Checking the L1 execution URL...")"
# `|| true`: curl baglanamazsa pipefail yuzunden script burada olurdu ve
# kullanici ham bir satir numarasi gorurdu. Kontrolu asagida kendimiz yapiyoruz.
L1_CHAIN_HEX=$(curl -s --max-time 25 -X POST "$L1_RPC" \
  -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)
[[ -n "$L1_CHAIN_HEX" ]] || abort "$(m \
  "L1 execution adresi cevap vermedi: ${L1_RPC}
        Adres doğru mu, sağlayıcınız ayakta mı ve anahtarınız geçerli mi kontrol edin." \
  "The L1 execution URL did not answer: ${L1_RPC}
        Check the URL, whether your provider is up, and whether your key is valid.")"
[[ "$L1_CHAIN_HEX" =~ ^0[xX][0-9a-fA-F]+$ || "$L1_CHAIN_HEX" =~ ^[0-9]+$ ]] || abort "$(m \
  "L1 execution adresi geçersiz chainId döndürdü: ${L1_CHAIN_HEX}" \
  "The L1 execution URL returned an invalid chainId: ${L1_CHAIN_HEX}")"
L1_CHAIN=$((L1_CHAIN_HEX))
if [[ "$L1_CHAIN" != "$PARENT_ID" ]]; then
  abort "$(m \
    "Yanlış L1: adres chainId ${L1_CHAIN} döndü, ${NETWORK} için ${PARENT_ID} (${PARENT_NAME}) gerekiyor." \
    "Wrong L1: that URL returned chainId ${L1_CHAIN}, ${NETWORK} needs ${PARENT_ID} (${PARENT_NAME}).")"
fi
ok "$(m "L1 execution doğru: chainId ${L1_CHAIN} (${PARENT_NAME})" \
       "L1 execution is correct: chainId ${L1_CHAIN} (${PARENT_NAME})")"

# Tam bir archive-state node gerekmiyor; ancak saglayici Rollup kontratinin
# kuruldugu eski L1 bloklarinda eth_getLogs sorgusuna cevap verebilmeli.
info "$(m "L1 geçmiş log sorgusu kontrol ediliyor..." \
         "Checking an L1 historical log query...")"
DEPLOYED_HEX=$(printf '0x%x' "$ROLLUP_DEPLOYED_AT")
LOGS_RESPONSE=$(curl -s --max-time 30 -X POST "$L1_RPC" -H 'content-type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"${ROLLUP_ADDRESS}\",\"fromBlock\":\"${DEPLOYED_HEX}\",\"toBlock\":\"${DEPLOYED_HEX}\",\"topics\":[[\"${GENESIS_ASSERTION_TOPIC}\"]]}]}" \
  2>/dev/null || true)
if ! printf '%s' "$LOGS_RESPONSE" | jq -e '.result | type == "array" and length > 0' >/dev/null 2>&1; then
  LOGS_ERR=$(printf '%s' "$LOGS_RESPONSE" | jq -r '.error.message // empty' 2>/dev/null || true)
  [[ -n "$LOGS_ERR" ]] || LOGS_ERR=$(m \
    "Beklenen genesis assertion logu bulunamadı veya cevap geçersiz." \
    "The expected genesis assertion log was missing or the response was invalid.")
  warn "$(m "L1 adresiniz geçmiş log sorgusunu reddetti:" "Your L1 URL refused a historical log query:")"
  warn "  ${LOGS_ERR}"
  if [[ "$DRY_RUN" == "1" ]]; then
    abort "$(m "Kuru deneme başarısız: historical log desteği doğrulanamadı." \
                "Dry run failed: historical log support could not be verified.")"
  else
    confirm "$(m "Yine de devam edilsin mi?" "Continue anyway?")" "N" \
      || abort "$(m "Kurulum iptal edildi." "Setup cancelled.")"
  fi
else
  ok "$(m "L1 geçmiş log sorgusu çalışıyor." "The L1 historical log query works.")"
fi

info "$(m "L1 beacon adresi doğrulanıyor..." "Checking the L1 beacon URL...")"
BEACON_VER=$(curl -s --max-time 25 "${L1_BEACON%/}/eth/v1/node/version" 2>/dev/null \
  | jq -r '.data.version // empty' 2>/dev/null || true)
if [[ -z "$BEACON_VER" ]]; then
  warn "$(m "Beacon adresi /eth/v1/node/version sorusuna cevap vermedi." \
          "The beacon URL did not answer /eth/v1/node/version.")"
  warn "$(m "Adres yanlışsa node blob verisini okuyamaz ve senkronlanamaz." \
          "If the URL is wrong the node cannot read blob data and will not sync.")"
  if [[ "$DRY_RUN" == "1" ]]; then
    abort "$(m "Kuru deneme başarısız: beacon endpoint doğrulanamadı." \
                "Dry run failed: the beacon endpoint could not be verified.")"
  else
    confirm "$(m "Yine de devam edilsin mi?" "Continue anyway?")" "N" \
      || abort "$(m "Kurulum iptal edildi." "Setup cancelled.")"
  fi
else
  ok "$(m "Beacon cevap verdi" "The beacon answered"): ${BEACON_VER}"
fi

##############################
# CONFIG
##############################
section "$(m "CONFIG DOSYALARI" "CONFIG FILES")"
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}"

fetch() {
  local name="$1"
  local target="${CONFIG_DIR}/${name}" tmp
  tmp=$(mktemp "${CONFIG_DIR}/.${name}.XXXXXX")
  info "$(m "İndiriliyor" "Downloading"): ${name}"
  curl -fsSL --max-time 180 "${CDN}/${name}" -o "${tmp}" \
    || { rm -f "${tmp}"; abort "$(m "İndirilemedi" "Could not download"): ${CDN}/${name}"; }
  jq -e . "${tmp}" >/dev/null 2>&1 \
    || { rm -f "${tmp}"; abort "$(m "Geçerli JSON değil" "Not valid JSON"): ${name}"; }
  chmod 0644 "${tmp}"
  mv -f "${tmp}" "${target}"
  ok "${name} ($(du -h "${target}" | cut -f1))"
}

fetch "${CHAIN_INFO}"
[[ -n "$GENESIS" ]] && fetch "${GENESIS}"

# Indirilen dosyanin gercekten istedigimiz ag oldugunu dogrula. Yanlis config
# ile acilan bir node saatlerce senkronlanip sonunda bos cikar.
INFO_CHAIN=$(jq -r 'if type=="array" then .[0] else . end | .["chain-config"].chainId' "${CONFIG_DIR}/${CHAIN_INFO}")
[[ "$INFO_CHAIN" == "$CHAIN_ID" ]] || abort "$(m \
  "Config chainId ${INFO_CHAIN} diyor, ${NETWORK} için ${CHAIN_ID} bekleniyordu." \
  "The config says chainId ${INFO_CHAIN}, ${NETWORK} expects ${CHAIN_ID}.")"
INFO_PARENT=$(jq -r 'if type=="array" then .[0] else . end | .["parent-chain-id"]' "${CONFIG_DIR}/${CHAIN_INFO}")
[[ "$INFO_PARENT" == "$PARENT_ID" ]] || abort "$(m \
  "Config parent chainId ${INFO_PARENT} diyor, ${PARENT_ID} bekleniyordu." \
  "The config says parent chainId ${INFO_PARENT}, expected ${PARENT_ID}.")"
INFO_ROLLUP=$(jq -r 'if type=="array" then .[0] else . end | .rollup.rollup' "${CONFIG_DIR}/${CHAIN_INFO}")
[[ "${INFO_ROLLUP,,}" == "${ROLLUP_ADDRESS,,}" ]] || abort "$(m \
  "Config içindeki Rollup adresi beklenen resmi adresle uyuşmuyor." \
  "The Rollup address in the config does not match the expected official address.")"
if [[ -n "$GENESIS" ]]; then
  jq -e '.serializedChainConfig and (.alloc | type == "object") and (.alloc | length > 0)' \
    "${CONFIG_DIR}/${GENESIS}" >/dev/null 2>&1 || abort "$(m \
      "Genesis dosyasında zorunlu alanlar eksik." \
      "Required fields are missing from the genesis file.")"
fi
ok "$(m "Config doğrulandı: chainId ${CHAIN_ID}, parent ${PARENT_ID}" \
         "Config verified: chainId ${CHAIN_ID}, parent ${PARENT_ID}")"

##############################
# SNAPSHOT
##############################
SNAPSHOT_URL=""
if [[ "$USE_SNAPSHOT" == "yes" ]]; then
  section "SNAPSHOT"
  info "$(m "Arbitrum snapshot indeksinden en güncel ${SNAPSHOT_TYPE} aranıyor..." \
           "Looking up the newest ${SNAPSHOT_TYPE} snapshot in Arbitrum's index...")"
  SNAP_JSON=$(curl -fsSL --max-time 90 -A "robinhood-rpc-setup" "${SNAPSHOT_INDEX}") \
    || abort "$(m "Snapshot indeksi okunamadı." "Could not read the snapshot index.")"

  SNAPSHOT_URL=""; SNAP_SIZE=""; SNAP_DATE=""; SNAP_PARTS=""; SNAP_SHA256=""
  read -r SNAPSHOT_URL SNAP_SIZE SNAP_DATE SNAP_PARTS SNAP_SHA256 < <(
    printf '%s' "$SNAP_JSON" | jq -r --arg chain "$SNAPSHOT_CHAIN" --arg type "$SNAPSHOT_TYPE" '
      .data[] | select(.name == $chain) as $c
      | $c.snapshots[]
      | select(.isFinished == true)
      | select(.type | ascii_downcase == ($type | ascii_downcase))
      | {date: .snapshotDate, parts: .parts, base: $c.downloadBaseUrl}
    ' | jq -s -r 'sort_by(.date) | (last // empty)
      | (.base + "/" + (.parts[0].key | @uri | gsub("%2F";"/"))) + " "
      + ((.parts | map(.size) | add) | tostring) + " "
      + .date + " "
      + (.parts | length | tostring) + " "
      + .parts[0].sha256'
  ) || true

  [[ -n "$SNAPSHOT_URL" && "$SNAPSHOT_URL" != "null" ]] || abort "$(m \
    "${SNAPSHOT_CHAIN} için ${SNAPSHOT_TYPE} snapshot bulunamadı." \
    "No ${SNAPSHOT_TYPE} snapshot found for ${SNAPSHOT_CHAIN}.")"

  SNAP_GB=$(( SNAP_SIZE / 1000000000 ))
  info "$(m "Tarih " "Date  "): ${SNAP_DATE}"
  info "$(m "Boyut " "Size  "): ${SNAP_GB} GB ($(m "${SNAP_PARTS} parça" "${SNAP_PARTS} part(s)"))"
  info "$(m "Adres " "URL   "): ${SNAPSHOT_URL}"

  if (( SNAP_PARTS > 1 )); then
    abort "$(m \
      "Bu snapshot ${SNAP_PARTS} parçalı. Tek parçayı Nitro'ya vermek bozuk arşiv oluşturacağı için kurulum durduruldu. --snapshot-type pruned kullanın." \
      "This snapshot has ${SNAP_PARTS} parts. Passing one part to Nitro creates a broken archive, so setup stopped. Use --snapshot-type pruned.")"
  fi

  info "$(m "Adres erişilebilir mi, kontrol ediliyor..." "Checking that the URL is reachable...")"
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -I --max-time 60 "${SNAPSHOT_URL}")
  [[ "$HTTP_CODE" == "200" ]] || abort "$(m \
    "Snapshot adresi ${HTTP_CODE} döndü." "The snapshot URL returned ${HTTP_CODE}.")"
  REMOTE_SHA256=$(curl -fsSL --max-time 30 "${SNAPSHOT_URL}.sha256" 2>/dev/null || true)
  [[ "$REMOTE_SHA256" == "$SNAP_SHA256" ]] || abort "$(m \
    "Snapshot checksum'u indeks ile CDN arasında uyuşmuyor; indirme başlatılmadı." \
    "The snapshot checksum differs between the index and CDN; download was not started.")"
  ok "$(m "Snapshot hazır. İndirmeyi node'un kendisi yapacak." \
             "Snapshot is ready. The node downloads it itself.")"
  warn "$(m "${SNAP_GB} GB indirilecek. Hattınıza göre saatler sürebilir, bu normal." \
          "${SNAP_GB} GB will be downloaded. Depending on your line this takes hours, which is normal.")"
else
  warn "$(m "Snapshot kapalı. Node sıfırdan senkronlanacak, bu çok uzun sürer." \
          "Snapshot is off. The node will sync from genesis, which takes a very long time.")"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  section "$(m "KURU DENEME BİTTİ" "DRY RUN FINISHED")"
  ok "$(m "Her şey yolunda. Gerçek kurulum için --dry-run olmadan çalıştırın." \
         "Everything checks out. Run it without --dry-run to install for real.")"
  echo ""
  echo "  $(m "Ağ           " "Network      ") : ${NETWORK} (chainId ${CHAIN_ID})"
  echo "  $(m "L1 execution " "L1 execution ") : $(m "doğrulandı" "verified") (chainId ${L1_CHAIN})"
  echo "  $(m "L1 beacon    " "L1 beacon    ") : ${BEACON_VER:-$(m "doğrulanamadı" "not verified")}"
  echo "  $(m "Config       " "Config       ") : ${CONFIG_DIR}"
  echo "  $(m "Snapshot     " "Snapshot     ") : ${SNAPSHOT_URL:-$(m "kapalı" "off")}"
  echo "  $(m "Docker imajı " "Docker image ") : ${NITRO_IMAGE} ($(m "çekilmedi" "not pulled"))"
  echo ""
  exit 0
fi

##############################
# SERVIS / SERVICE
##############################
section "$(m "SERVİS" "SERVICE")"

if [[ "$EXPOSE_RPC" == "yes" ]]; then
  ufw status | grep -q '^Status: active' || abort "$(m \
    "RPC dışarı açılmadan önce UFW aktif olmalı. Önce SSH portunu izinli tutarak UFW'yi yapılandırın." \
    "UFW must be active before exposing RPC. Configure UFW while keeping your SSH port allowed.")"
  if [[ -n "$ALLOWED_IP" ]]; then
    ufw status verbose | grep -q 'Default: deny (incoming)' || abort "$(m \
      "--allowed-ip güvenli çalışsın diye UFW gelen bağlantı varsayılanı deny olmalı." \
      "UFW must default to deny incoming connections for --allowed-ip to be safe.")"
  fi
fi

# Nitro image v3.11.2 `user` (uid 1000) hesabi ve /home/user altinda
# calisiyor. Host dizini bu hesaba yazilabilir olmadan kalici veri yazilamaz.
install -d -m 0755 -o "${CONTAINER_UID}" -g "${CONTAINER_GID}" "${DATA_DIR}"
if [[ -n "$SNAPSHOT_URL" ]]; then
  # Veritabani icindeki varsayilan tmp dizini restart sonrasi Nitro tarafindan
  # "unexpected files" diye reddediliyor. Ayri dizin yarim indirmeyi korur.
  install -d -m 0755 -o "${CONTAINER_UID}" -g "${CONTAINER_GID}" "${SNAPSHOT_DOWNLOAD_DIR}"
fi

# L1 saglayici anahtarlari systemd unit ve process argumanlarina yazilmasin.
# Nitro bu degerleri --conf.env-prefix=NITRO ile environment'tan okur.
umask 077
{
  printf 'NITRO_PARENT__CHAIN_CONNECTION_URL=%s\n' "$L1_RPC"
  printf 'NITRO_PARENT__CHAIN_BLOB__CLIENT_BEACON__URL=%s\n' "$L1_BEACON"
  printf 'GOMEMLIMIT=%sGiB\n' "$(( RAM_GB * 3 / 4 ))"
  printf 'MALLOC_ARENA_MAX=2\n'
  # Snapshot CDN'i uzun HTTP/2 transferlerinde zaman zaman INTERNAL_ERROR ile
  # stream'i kapatiyor. Go HTTP/1.1'e dustugunde Range ile ayni dosyadan surer.
  printf 'GODEBUG=http2client=0\n'
} > "${ENV_FILE}"
chmod 0600 "${ENV_FILE}"

port_in_use() {
  ss -ltnH | awk '{print $4}' | grep -Eq "(^|:)${1}$"
}
DOCKER_ARGS=(
  "--conf.env-prefix=NITRO"
  "--chain.info-files=${CONTAINER_HOME}/config/${CHAIN_INFO}"
  "--node.feed.input.url=${FEED_URL}"
  "--node.resource-mgmt.mem-free-limit=4GB"
  # Sequencer olmayan bir node bunu istiyor ve olmadan hic acilmiyor:
  # "Fatal configuration error: ForwardingTarget not set and not sequencer".
  # Resmi dokumandaki komutta yok, gercek calistirmada ortaya cikti.
  "--execution.forwarding-target=${FORWARD_TARGET}"
  "--http.addr=${RPC_BIND_ADDR}"
  "--http.port=${RPC_PORT}"
  "--http.api=net,web3,eth"
  "--http.vhosts=*"
  "--ws.addr=${RPC_BIND_ADDR}"
  "--ws.port=${WS_PORT}"
  "--ws.api=net,web3,eth"
)
[[ -n "$GENESIS" ]] && DOCKER_ARGS+=("--init.genesis-json-file=${CONTAINER_HOME}/config/${GENESIS}")
if [[ -n "$SNAPSHOT_URL" ]]; then
  DOCKER_ARGS+=(
    "--init.url=${SNAPSHOT_URL}"
    "--init.download-path=${CONTAINER_HOME}/.arbitrum/snapshot-download"
  )
fi
if [[ "$SNAPSHOT_TYPE" == "full-path" || "$SNAPSHOT_TYPE" == "archive-path" ]]; then
  DOCKER_ARGS+=("--execution.caching.state-scheme=path")
fi
if [[ "$SNAPSHOT_TYPE" == "archive-path" ]]; then
  DOCKER_ARGS+=("--execution.caching.archive=true" "--execution.caching.state-history=0")
fi

info "$(m "Docker imajı çekiliyor" "Pulling the Docker image"): ${NITRO_IMAGE} (~5 GB)"
if ! docker pull "${NITRO_IMAGE}" >/dev/null 2>/tmp/rh-pull.err; then
  err "$(m "Docker imajı çekilemedi. Docker'ın verdiği hata:" "Could not pull the image. Docker said:")"
  sed 's/^/        /' /tmp/rh-pull.err | head -5
  abort "$(m "İnternet bağlantınızı ve diskte yer olduğunu kontrol edip tekrar deneyin." \
           "Check your connection and free disk space, then try again.")"
fi
ok "$(m "İmaj hazır." "Image is ready.")"

# Guncellemede once tum indirme ve kontrolleri bitir, sonra mevcut node'u
# graceful shutdown ile kapat. Boylece bir on kontrol hatasi calisan node'u
# gereksiz yere durdurmaz ve kendi portlarimiz cakisma sanilmaz.
if systemctl is-active --quiet "${SERVICE}" 2>/dev/null; then
  info "$(m "Mevcut servis düzgün biçimde durduruluyor..." \
           "Gracefully stopping the existing service...")"
  systemctl stop "${SERVICE}"
fi
if [[ "$(docker inspect -f '{{.State.Running}}' "${SERVICE}" 2>/dev/null || true)" == "true" ]]; then
  docker stop --timeout 1800 "${SERVICE}" >/dev/null
fi

port_in_use "$RPC_PORT" && abort "$(m \
  "${RPC_PORT} portu başka bir süreç tarafından kullanılıyor." \
  "Port ${RPC_PORT} is already used by another process.")"
port_in_use "$WS_PORT" && abort "$(m \
  "${WS_PORT} portu başka bir süreç tarafından kullanılıyor." \
  "Port ${WS_PORT} is already used by another process.")"

# systemd unit dosyasinda % bir belirtec on ekidir ve literal % icin %% yazilir.
# Snapshot adresi bosluk yuzunden %20 iceriyor, escape edilmeden yazilinca
# systemd "bad unit file setting" deyip servisi hic baslatmiyor. Bu hata sadece
# snapshot ile kuruldugunda ortaya cikiyor.
cat > "/etc/systemd/system/${SERVICE}.service" <<EOF
[Unit]
Description=Robinhood Chain RPC node (${NETWORK})
After=network-online.target docker.service
Requires=docker.service

[Service]
ExecStartPre=-/usr/bin/docker stop --timeout 1800 ${SERVICE}
ExecStartPre=-/usr/bin/docker rm ${SERVICE}
ExecStart=/usr/bin/docker run --rm --stop-timeout 1800 --name ${SERVICE} --network host \\
  --env-file ${ENV_FILE} \\
  -v ${DATA_DIR}:${CONTAINER_HOME}/.arbitrum \\
  -v ${CONFIG_DIR}:${CONTAINER_HOME}/config:ro \\
  ${NITRO_IMAGE} \\
$(printf '  %s \\\n' "${DOCKER_ARGS[@]}" | sed 's/%/%%/g; $ s/ \\$//')
ExecStop=/usr/bin/docker stop --timeout 1800 ${SERVICE}
SuccessExitStatus=2
Restart=always
RestartSec=15
TimeoutStopSec=1830

[Install]
WantedBy=multi-user.target
EOF

systemd-analyze verify "/etc/systemd/system/${SERVICE}.service" >/dev/null 2>&1 \
  || abort "$(m "Oluşturulan systemd servisi doğrulanamadı." \
              "The generated systemd service did not pass validation.")"

if [[ -n "$SNAPSHOT_URL" ]]; then
  CHAIN_ID_HEX=$(printf '0x%x' "$CHAIN_ID")
  cat > "${CONFIG_DIR}/cleanup-snapshot.sh" <<EOF
#!/usr/bin/env bash
set -u

while systemctl is-active --quiet "${SERVICE}"; do
  RESPONSE=\$(curl -s --max-time 10 -X POST "http://127.0.0.1:${RPC_PORT}" \\
    -H 'content-type: application/json' \\
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null || true)
  if printf '%s' "\$RESPONSE" | jq -e --arg expected "${CHAIN_ID_HEX}" \\
    '.result | ascii_downcase == \$expected' >/dev/null 2>&1; then
    find "${SNAPSHOT_DOWNLOAD_DIR}" -mindepth 1 -maxdepth 1 -type f -delete
    rmdir "${SNAPSHOT_DOWNLOAD_DIR}" 2>/dev/null || true
    exit 0
  fi
  sleep 60
done
EOF
  chmod 0700 "${CONFIG_DIR}/cleanup-snapshot.sh"

  cat > "/etc/systemd/system/${SNAPSHOT_CLEANUP_SERVICE}.service" <<EOF
[Unit]
Description=Remove Robinhood snapshot after successful import
Requires=${SERVICE}.service
After=${SERVICE}.service
PartOf=${SERVICE}.service

[Service]
Type=oneshot
ExecStart=${CONFIG_DIR}/cleanup-snapshot.sh
SuccessExitStatus=SIGTERM

[Install]
WantedBy=${SERVICE}.service
EOF
  systemd-analyze verify "/etc/systemd/system/${SNAPSHOT_CLEANUP_SERVICE}.service" >/dev/null 2>&1 \
    || abort "$(m "Snapshot temizleme servisi doğrulanamadı." \
                "The snapshot cleanup service did not pass validation.")"
else
  systemctl disable --now "${SNAPSHOT_CLEANUP_SERVICE}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SNAPSHOT_CLEANUP_SERVICE}.service"
  rm -f "${CONFIG_DIR}/cleanup-snapshot.sh"
fi

systemctl daemon-reload
systemctl enable "${SERVICE}" >/dev/null 2>&1
if [[ -n "$SNAPSHOT_URL" ]]; then
  systemctl enable "${SNAPSHOT_CLEANUP_SERVICE}" >/dev/null 2>&1
fi
ok "$(m "Servis yazıldı" "Service written"): ${SERVICE}.service"

##############################
# GUVENLIK DUVARI / FIREWALL
##############################
section "$(m "GÜVENLİK DUVARI" "FIREWALL")"
if [[ "$EXPOSE_RPC" == "yes" ]]; then
  if [[ -n "$ALLOWED_IP" ]]; then
    ufw allow from "${ALLOWED_IP}" to any port "${RPC_PORT}" proto tcp >/dev/null
    ufw allow from "${ALLOWED_IP}" to any port "${WS_PORT}" proto tcp >/dev/null
    ok "$(m "RPC sadece ${ALLOWED_IP} adresine açıldı." "The RPC was opened only to ${ALLOWED_IP}.")"
  else
    warn "$(m "RPC tüm internete açılıyor. Bu node'unuzu herkesin kullanabileceği anlamına gelir." \
            "The RPC is about to be opened to the whole internet, which means anyone can use your node.")"
    warn "$(m "Tek bir IP'ye kısıtlamak için: --allowed-ip <ip>" \
            "To limit it to one address: --allowed-ip <ip>")"
    if confirm "$(m "Yine de herkese açılsın mı?" "Open it to everyone anyway?")" "N"; then
      ufw allow "${RPC_PORT}"/tcp >/dev/null
      ufw allow "${WS_PORT}"/tcp >/dev/null
      ok "$(m "Portlar açıldı." "Ports opened.")"
    else
      info "$(m "Portlar açılmadı, node sadece sunucunun kendisinden erişilebilir." \
              "Ports were not opened, the node is reachable only from this server.")"
    fi
  fi
else
  info "$(m "RPC 127.0.0.1 adresine bağlandı; ağdan erişilemez." \
          "RPC is bound to 127.0.0.1 and is not reachable from the network.")"
  info "$(m "Uzaktan güvenli kullanım için SSH tüneli açın" "For secure remote use, open an SSH tunnel"):"
  info "  ssh -L ${RPC_PORT}:127.0.0.1:${RPC_PORT} root@<sunucu-ip>"
fi

##############################
# BASLAT / START
##############################
section "$(m "BAŞLATILIYOR" "STARTING")"
systemctl restart "${SERVICE}"
sleep 8
if systemctl is-active --quiet "${SERVICE}" && \
   [[ "$(docker inspect -f '{{.State.Running}}' "${SERVICE}" 2>/dev/null || true)" == "true" ]]; then
  ok "$(m "Servis çalışıyor." "The service is running.")"
else
  err "$(m "Servis başlamadı. Son satırlar:" "The service did not start. Last lines:")"
  journalctl -u "${SERVICE}" -n 15 --no-pager 2>/dev/null | sed 's/^/        /'
  echo ""
  err "$(m "Tam log için" "Full log"): journalctl -u ${SERVICE} -n 100 --no-pager"
  exit 1
fi

if [[ "$UI_LANG" == "en" ]]; then
  cat <<EOF

${BOLD}${GREEN}Setup complete.${RESET}

  Network    : ${NETWORK} (chainId ${CHAIN_ID})
  RPC        : http://${RPC_BIND_ADDR}:${RPC_PORT}
  WebSocket  : ws://${RPC_BIND_ADDR}:${WS_PORT}
  Data       : ${DATA_DIR}
  Config     : ${CONFIG_DIR}

${BOLD}Everyday commands${RESET}

  Follow logs : journalctl -u ${SERVICE} -f
  Status      : systemctl status ${SERVICE}
  Stop        : systemctl stop ${SERVICE}
  Start       : systemctl start ${SERVICE}
  Remove      : sudo ./script.sh --uninstall

${BOLD}Checking sync${RESET}

  curl -s -X POST http://127.0.0.1:${RPC_PORT} -H 'content-type: application/json' \\
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}'

  When the answer is ${DIM}false${RESET} the node is fully synced. Until then the block
  number lags behind, which is normal.

  curl -s -X POST http://127.0.0.1:${RPC_PORT} -H 'content-type: application/json' \\
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'

EOF
  if [[ "$USE_SNAPSHOT" == "yes" ]]; then
    warn "Downloading and unpacking the snapshot takes hours. The block number"
    warn "standing still for the first few hours is normal, as long as the log moves."
  else
    warn "Snapshot is disabled. Syncing from genesis takes substantially longer."
  fi
else
  cat <<EOF

${BOLD}${GREEN}Kurulum tamamlandı.${RESET}

  Ağ         : ${NETWORK} (chainId ${CHAIN_ID})
  RPC        : http://${RPC_BIND_ADDR}:${RPC_PORT}
  WebSocket  : ws://${RPC_BIND_ADDR}:${WS_PORT}
  Veri       : ${DATA_DIR}
  Config     : ${CONFIG_DIR}

${BOLD}Sık kullanılan komutlar${RESET}

  Log izle        : journalctl -u ${SERVICE} -f
  Durum           : systemctl status ${SERVICE}
  Durdur          : systemctl stop ${SERVICE}
  Başlat          : systemctl start ${SERVICE}
  Kaldır          : sudo ./script.sh --uninstall

${BOLD}Senkron kontrolü${RESET}

  curl -s -X POST http://127.0.0.1:${RPC_PORT} -H 'content-type: application/json' \\
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}'

  Cevap ${DIM}false${RESET} olduğunda senkron bitmiştir. O ana kadar blok numarası
  geriden gelir, bu normaldir.

  curl -s -X POST http://127.0.0.1:${RPC_PORT} -H 'content-type: application/json' \\
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'

EOF
  if [[ "$USE_SNAPSHOT" == "yes" ]]; then
    warn "Snapshot indirme ve açma işlemi saatler sürer. İlk saatlerde blok"
    warn "numarasının ilerlememesi normaldir, log akıyorsa her şey yolundadır."
  else
    warn "Snapshot kapalı. Genesis'ten senkron çok daha uzun sürer."
  fi
fi
