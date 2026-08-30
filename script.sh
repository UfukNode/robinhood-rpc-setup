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
FORWARD_TARGET=""          # bos ise agin resmi RPC'si / empty means the chain's own RPC
NON_INTERACTIVE="0"
UNINSTALL_ONLY="0"
DRY_RUN="0"

# Dokumanin sabitledigi surum. Docker Hub'da daha yenisi olabilir, biz
# dokumani takip ediyoruz: resmi rehber ne diyorsa o kurulur.
NITRO_IMAGE="offchainlabs/nitro-node:v3.11.2-3599aca"
CDN="https://cdn.robinhood.com/assets/generated_assets/hoodchain_docsite/chain-node-configs"
SNAPSHOT_INDEX="https://snapshot-explorer.arbitrum.io/api/snapshots"
SERVICE="robinhood-rpc"

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
  --dry-run                     Check only: L1 endpoints, disk, config and
                                snapshot are verified, nothing is installed
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
  --dry-run                     Sadece kontrol et: L1 adresleri, disk, config ve
                                snapshot doğrulanır, hiçbir şey kurulmaz
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

case "$NETWORK" in
  mainnet)
    CHAIN_ID=4663
    PARENT_NAME="Ethereum mainnet"
    PARENT_ID=1
    CHAIN_INFO="robinhood-chain-info.json"
    GENESIS="robinhood-genesis.json"
    FEED_URL="wss://feed.mainnet.chain.robinhood.com"
    SEQUENCER_URL="https://rpc.mainnet.chain.robinhood.com"
    SNAPSHOT_CHAIN="Robinhood Chain"
    ;;
  testnet)
    CHAIN_ID=46630
    PARENT_NAME="Ethereum Sepolia"
    PARENT_ID=11155111
    CHAIN_INFO="robinhood-chain-testnet-info.json"
    GENESIS=""
    FEED_URL="wss://feed.testnet.chain.robinhood.com"
    SEQUENCER_URL="https://rpc.testnet.chain.robinhood.com"
    SNAPSHOT_CHAIN="Robinhood Chain Sepolia"
    ;;
  *) abort "$(m "--network sadece mainnet veya testnet olabilir." "--network must be mainnet or testnet.")";;
esac

[[ -z "$FORWARD_TARGET" ]] && FORWARD_TARGET="$SEQUENCER_URL"

CONFIG_DIR="${DATA_ROOT}/config"
DATA_DIR="${DATA_ROOT}/robinhood-nitro-data"

##############################
# KALDIRMA / UNINSTALL
##############################
if [[ "$UNINSTALL_ONLY" == "1" ]]; then
  section "$(m "KALDIRMA" "UNINSTALL")"
  systemctl disable --now "${SERVICE}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
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

# Dokuman "guncel zincir boyutunun 2 kati + %20" diyor. Mainnet pruned snapshot
# bugun 466 GB, yani gercekci taban 1.1 TB. Testnet icin 233 GB uzerinden.
if [[ "$NETWORK" == "mainnet" ]]; then NEED_GB=1150; else NEED_GB=600; fi
if (( FREE_GB < NEED_GB )); then
  warn "$(m "${NETWORK} için önerilen boş alan ${NEED_GB} GB, sizde ${FREE_GB} GB var." \
          "${NETWORK} wants about ${NEED_GB} GB free, you have ${FREE_GB} GB.")"
  warn "$(m "Snapshot açılırken arşiv ve açılmış veri bir süre birlikte diskte durur." \
          "While the snapshot unpacks, the archive and the unpacked data sit on disk together.")"
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
L1_CHAIN=$((L1_CHAIN_HEX))
if [[ "$L1_CHAIN" != "$PARENT_ID" ]]; then
  abort "$(m \
    "Yanlış L1: adres chainId ${L1_CHAIN} döndü, ${NETWORK} için ${PARENT_ID} (${PARENT_NAME}) gerekiyor." \
    "Wrong L1: that URL returned chainId ${L1_CHAIN}, ${NETWORK} needs ${PARENT_ID} (${PARENT_NAME}).")"
fi
ok "$(m "L1 execution doğru: chainId ${L1_CHAIN} (${PARENT_NAME})" \
       "L1 execution is correct: chainId ${L1_CHAIN} (${PARENT_NAME})")"

# Node acilirken L1'de eski bir blok araligina eth_getLogs atiyor. Ucretsiz
# public RPC'lerin cogu bunu "archive requests require a personal token" diye
# reddediyor ve node veritabanini kuramadan oluyor. Burada onceden deniyoruz.
info "$(m "L1 arşiv sorgusu destekliyor mu, kontrol ediliyor..." \
         "Checking whether the L1 URL answers archive queries...")"
L1_HEAD_HEX=$(curl -s --max-time 25 -X POST "$L1_RPC" -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' 2>/dev/null \
  | jq -r '.result // empty' 2>/dev/null || true)
if [[ -n "$L1_HEAD_HEX" ]]; then
  OLD_BLOCK=$(printf '0x%x' $(( L1_HEAD_HEX - 200000 )))
  LOGS_ERR=$(curl -s --max-time 30 -X POST "$L1_RPC" -H 'content-type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"${OLD_BLOCK}\",\"toBlock\":\"${OLD_BLOCK}\"}]}" \
    2>/dev/null | jq -r '.error.message // empty' 2>/dev/null || true)
  if [[ -n "$LOGS_ERR" ]]; then
    warn "$(m "L1 adresiniz eski blok sorgusunu reddetti:" "Your L1 URL refused an old-block query:")"
    warn "  ${LOGS_ERR}"
    warn "$(m "Node açılırken bu sorguyu yapıyor. Arşiv desteği olmayan ücretsiz bir" \
            "The node makes this query on startup. With a free URL that has no archive")"
    warn "$(m "adres kullanıyorsanız kurulum senkron başlamadan hata verir." \
            "support, setup fails before syncing even begins.")"
    if [[ "$DRY_RUN" == "1" ]]; then
      warn "$(m "Kuru deneme olduğu için devam ediliyor." "Dry run, carrying on anyway.")"
    else
      confirm "$(m "Yine de devam edilsin mi?" "Continue anyway?")" "N" \
        || abort "$(m "Kurulum iptal edildi." "Setup cancelled.")"
    fi
  else
    ok "$(m "L1 arşiv sorgusu çalışıyor." "Archive queries work.")"
  fi
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
    warn "$(m "Kuru deneme olduğu için devam ediliyor." "Dry run, carrying on anyway.")"
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
  info "$(m "İndiriliyor" "Downloading"): ${name}"
  curl -fsSL --max-time 180 "${CDN}/${name}" -o "${CONFIG_DIR}/${name}" \
    || abort "$(m "İndirilemedi" "Could not download"): ${CDN}/${name}"
  jq -e . "${CONFIG_DIR}/${name}" >/dev/null 2>&1 \
    || abort "$(m "Geçerli JSON değil" "Not valid JSON"): ${name}"
  ok "${name} ($(du -h "${CONFIG_DIR}/${name}" | cut -f1))"
}

fetch "${CHAIN_INFO}"
[[ -n "$GENESIS" ]] && fetch "${GENESIS}"

# Indirilen dosyanin gercekten istedigimiz ag oldugunu dogrula. Yanlis config
# ile acilan bir node saatlerce senkronlanip sonunda bos cikar.
INFO_CHAIN=$(jq -r 'if type=="array" then .[0] else . end | .["chain-config"].chainId' "${CONFIG_DIR}/${CHAIN_INFO}")
[[ "$INFO_CHAIN" == "$CHAIN_ID" ]] || abort "$(m \
  "Config chainId ${INFO_CHAIN} diyor, ${NETWORK} için ${CHAIN_ID} bekleniyordu." \
  "The config says chainId ${INFO_CHAIN}, ${NETWORK} expects ${CHAIN_ID}.")"
ok "$(m "Config doğrulandı: chainId ${CHAIN_ID}" "Config verified: chainId ${CHAIN_ID}")"

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

  read -r SNAPSHOT_URL SNAP_SIZE SNAP_DATE SNAP_PARTS < <(
    printf '%s' "$SNAP_JSON" | jq -r --arg chain "$SNAPSHOT_CHAIN" --arg type "$SNAPSHOT_TYPE" '
      .data[] | select(.name == $chain) as $c
      | $c.snapshots[]
      | select(.type | ascii_downcase == ($type | ascii_downcase))
      | {date: .snapshotDate, parts: .parts, base: $c.downloadBaseUrl}
    ' | jq -s -r 'sort_by(.date) | last
      | (.base + "/" + (.parts[0].key | @uri | gsub("%2F";"/"))) + " "
      + ((.parts | map(.size) | add) | tostring) + " "
      + .date + " "
      + (.parts | length | tostring)'
  )

  [[ -n "$SNAPSHOT_URL" && "$SNAPSHOT_URL" != "null" ]] || abort "$(m \
    "${SNAPSHOT_CHAIN} için ${SNAPSHOT_TYPE} snapshot bulunamadı." \
    "No ${SNAPSHOT_TYPE} snapshot found for ${SNAPSHOT_CHAIN}.")"

  SNAP_GB=$(( SNAP_SIZE / 1000000000 ))
  info "$(m "Tarih " "Date  "): ${SNAP_DATE}"
  info "$(m "Boyut " "Size  "): ${SNAP_GB} GB ($(m "${SNAP_PARTS} parça" "${SNAP_PARTS} part(s)"))"
  info "$(m "Adres " "URL   "): ${SNAPSHOT_URL}"

  if (( SNAP_PARTS > 1 )); then
    warn "$(m "Bu snapshot ${SNAP_PARTS} parçadan oluşuyor. Nitro tek parçayı kendisi indirir," \
            "This snapshot has ${SNAP_PARTS} parts. Nitro downloads a single part itself,")"
    warn "$(m "çok parçalı olanlar için resmi dokümandaki elle birleştirme adımı gerekir." \
            "multi-part ones need the manual join step from the official docs.")"
    warn "$(m "Daha küçük bir tür seçmek isterseniz: --snapshot-type pruned" \
            "For a smaller one: --snapshot-type pruned")"
    confirm "$(m "Yine de devam edilsin mi?" "Continue anyway?")" "N" \
      || abort "$(m "Kurulum iptal edildi." "Setup cancelled.")"
  fi

  info "$(m "Adres erişilebilir mi, kontrol ediliyor..." "Checking that the URL is reachable...")"
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -I --max-time 60 "${SNAPSHOT_URL}")
  [[ "$HTTP_CODE" == "200" ]] || abort "$(m \
    "Snapshot adresi ${HTTP_CODE} döndü." "The snapshot URL returned ${HTTP_CODE}.")"
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

DOCKER_ARGS=(
  "--chain.info-files=/home/nitro/config/${CHAIN_INFO}"
  "--parent-chain.connection.url=${L1_RPC}"
  "--parent-chain.blob-client.beacon-url=${L1_BEACON}"
  "--node.feed.input.url=${FEED_URL}"
  # Sequencer olmayan bir node bunu istiyor ve olmadan hic acilmiyor:
  # "Fatal configuration error: ForwardingTarget not set and not sequencer".
  # Resmi dokumandaki komutta yok, gercek calistirmada ortaya cikti.
  "--execution.forwarding-target=${FORWARD_TARGET}"
  "--http.addr=0.0.0.0"
  "--http.port=8547"
  "--http.api=net,web3,eth"
  "--http.vhosts=*"
  "--http.corsdomain=*"
  "--ws.addr=0.0.0.0"
  "--ws.port=8548"
  "--ws.api=net,web3,eth"
)
[[ -n "$GENESIS" ]] && DOCKER_ARGS+=("--init.genesis-json-file=/home/nitro/config/${GENESIS}")
[[ -n "$SNAPSHOT_URL" ]] && DOCKER_ARGS+=("--init.url=${SNAPSHOT_URL}")

info "$(m "Docker imajı çekiliyor" "Pulling the Docker image"): ${NITRO_IMAGE} (~1.4 GB)"
if ! docker pull "${NITRO_IMAGE}" >/dev/null 2>/tmp/rh-pull.err; then
  err "$(m "Docker imajı çekilemedi. Docker'ın verdiği hata:" "Could not pull the image. Docker said:")"
  sed 's/^/        /' /tmp/rh-pull.err | head -5
  abort "$(m "İnternet bağlantınızı ve diskte yer olduğunu kontrol edip tekrar deneyin." \
           "Check your connection and free disk space, then try again.")"
fi
ok "$(m "İmaj hazır." "Image is ready.")"

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
ExecStartPre=-/usr/bin/docker rm -f ${SERVICE}
ExecStart=/usr/bin/docker run --rm --name ${SERVICE} \\
  -v ${DATA_DIR}:/home/nitro/.arbitrum \\
  -v ${CONFIG_DIR}:/home/nitro/config \\
  -p ${RPC_PORT}:8547 -p ${WS_PORT}:8548 \\
  ${NITRO_IMAGE} \\
$(printf '  %s \\\n' "${DOCKER_ARGS[@]}" | sed 's/%/%%/g; $ s/ \\$//')
ExecStop=/usr/bin/docker stop -t 120 ${SERVICE}
Restart=always
RestartSec=15
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE}" >/dev/null 2>&1
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
  info "$(m "RPC dışarı açılmadı. Sadece bu sunucudan erişilebilir." \
          "The RPC was not exposed. It is reachable only from this server.")"
  info "$(m "Sonradan açmak için" "To open it later"): ufw allow from <ip> to any port ${RPC_PORT} proto tcp"
fi

##############################
# BASLAT / START
##############################
section "$(m "BAŞLATILIYOR" "STARTING")"
systemctl restart "${SERVICE}"
sleep 8
if systemctl is-active --quiet "${SERVICE}"; then
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
  RPC        : http://127.0.0.1:${RPC_PORT}
  WebSocket  : ws://127.0.0.1:${WS_PORT}
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
  warn "Downloading and unpacking the snapshot takes hours. The block number"
  warn "standing still for the first few hours is normal, as long as the log moves."
else
  cat <<EOF

${BOLD}${GREEN}Kurulum tamamlandı.${RESET}

  Ağ         : ${NETWORK} (chainId ${CHAIN_ID})
  RPC        : http://127.0.0.1:${RPC_PORT}
  WebSocket  : ws://127.0.0.1:${WS_PORT}
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
  warn "Snapshot indirme ve açma işlemi saatler sürer. İlk saatlerde blok"
  warn "numarasının ilerlememesi normaldir, log akıyorsa her şey yolundadır."
fi
