#!/usr/bin/env bash
#
# Robinhood Chain RPC node kurulum scripti
# Kaynak: https://docs.robinhood.com/chain/run-a-full-node/
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

print_header() {
  echo -e "${BLUE}============================================${RESET}"
  echo -e "${BLUE}    UFUKDEGEN TARAFINDAN HAZIRLANMIŞTIR    ${RESET}"
  echo -e "${BLUE}============================================${RESET}"
  echo ""
}

section() { echo -e "\n${BOLD}${BLUE}========== $* ==========${RESET}\n"; }
info()    { echo -e "${CYAN}[bilgi]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[uyarı]${RESET} $*"; }
ok()      { echo -e "${GREEN}[tamam]${RESET} $*"; }
err()     { echo -e "${RED}[hata]${RESET} $*"; }
abort()   { err "$*"; exit 1; }

trap 'err "Beklenmeyen hata, satır $LINENO. Script durdu."' ERR

confirm() {
  local prompt="${1:-Devam edilsin mi?}" default="${2:-Y}" reply
  if [[ "${NON_INTERACTIVE}" == "1" ]]; then
    [[ "${default}" =~ ^[Yy]$ ]] && return 0 || return 1
  fi
  read -rp "${prompt} [Y/n]: " reply || true
  [[ -z "$reply" ]] && reply="${default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

##############################
# ARGÜMANLAR ve VARSAYILANLAR
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
FORWARD_TARGET=""          # bos ise agin resmi RPC'si kullanilir, "null" kapatir
NON_INTERACTIVE="0"
UNINSTALL_ONLY="0"
DRY_RUN="0"

# Dokümanın sabitlediği sürüm. Docker Hub'da daha yenisi olabilir, biz
# dokümanı takip ediyoruz: resmi rehber ne diyorsa o kurulur.
NITRO_IMAGE="offchainlabs/nitro-node:v3.11.2-3599aca"
CDN="https://cdn.robinhood.com/assets/generated_assets/hoodchain_docsite/chain-node-configs"
SNAPSHOT_INDEX="https://snapshot-explorer.arbitrum.io/api/snapshots"
SERVICE="robinhood-rpc"

usage() {
  cat <<EOF
${BOLD}Robinhood Chain RPC node kurulumu${RESET}

Kullanım:
  sudo ./script.sh [seçenekler]

Seçenekler:
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
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    -h|--help)        usage; exit 0;;
    *) usage; abort "Bilinmeyen seçenek: $1";;
  esac
done

print_header

##############################
# ÖN KONTROLLER
##############################
need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || abort "Lütfen sudo ile (root) çalıştırın."
}
check_apt() {
  command -v apt-get >/dev/null 2>&1 || abort "Bu script Debian/Ubuntu (apt) içindir."
}

need_root
check_apt

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
  *) abort "--network sadece mainnet veya testnet olabilir.";;
esac

[[ -z "$FORWARD_TARGET" ]] && FORWARD_TARGET="$SEQUENCER_URL"

CONFIG_DIR="${DATA_ROOT}/config"
DATA_DIR="${DATA_ROOT}/robinhood-nitro-data"

##############################
# KALDIRMA
##############################
if [[ "$UNINSTALL_ONLY" == "1" ]]; then
  section "KALDIRMA"
  systemctl disable --now "${SERVICE}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  systemctl daemon-reload
  docker rm -f "${SERVICE}" 2>/dev/null || true
  rm -rf "${CONFIG_DIR}"
  ok "Servis ve config kaldırıldı."
  warn "Veri klasörü duruyor: ${DATA_DIR}"
  warn "Diski boşaltmak isterseniz elle silin: rm -rf ${DATA_DIR}"
  exit 0
fi

##############################
# GEREKSINIMLER
##############################
section "SİSTEM KONTROLÜ"

RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
info "RAM: ${RAM_GB} GB"
if (( RAM_GB < 60 )); then
  warn "Resmi doküman en az 64 GB RAM istiyor, önerdiği 128 GB. Sizde ${RAM_GB} GB var."
  # Kuru denemede durmuyoruz: hiçbir şey kurulmayacağı için donanımı yetersiz olan
  # biri de L1 adreslerini ve config'i buradan doğrulayabilsin.
  if [[ "$DRY_RUN" == "1" ]]; then
    warn "Kuru deneme olduğu için devam ediliyor."
  else
    confirm "Yine de devam edilsin mi?" "N" || abort "Kurulum iptal edildi."
  fi
else
  ok "RAM yeterli."
fi

mkdir -p "${DATA_ROOT}"
FREE_GB=$(df -BG --output=avail "${DATA_ROOT}" | tail -1 | tr -dc '0-9')
info "Boş disk (${DATA_ROOT}): ${FREE_GB} GB"

# Doküman "güncel zincir boyutunun 2 katı + %20" diyor. Mainnet pruned snapshot
# bugün 466 GB, yani gerçekçi taban 1.1 TB. Testnet için 233 GB üzerinden.
if [[ "$NETWORK" == "mainnet" ]]; then NEED_GB=1150; else NEED_GB=600; fi
if (( FREE_GB < NEED_GB )); then
  warn "${NETWORK} için önerilen boş alan ${NEED_GB} GB, sizde ${FREE_GB} GB var."
  warn "Snapshot açılırken arşiv ve açılmış veri bir süre birlikte diskte durur."
  if [[ "$DRY_RUN" == "1" ]]; then
    warn "Kuru deneme olduğu için devam ediliyor."
  else
    confirm "Yine de devam edilsin mi?" "N" || abort "Kurulum iptal edildi."
  fi
else
  ok "Disk yeterli."
fi

##############################
# PAKETLER ve DOCKER
##############################
section "PAKETLER"
if [[ "$DRY_RUN" == "1" ]]; then
  # Kuru denemede docker kurmuyoruz ama curl ve jq lazım, ve taze bir sunucuda
  # jq kurulu gelmez. Küçük araçları burada da kuruyoruz, yoksa "kuru deneme"
  # tam da en çok işe yarayacağı yerde, sıfırdan kurulan makinede çalışmıyordu.
  if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    info "Kuru deneme için curl ve jq kuruluyor (docker kurulmayacak)..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl jq >/dev/null 2>&1
  fi
  ok "Kuru deneme: docker ve diğer paketler atlanıyor."
else
info "Paket listesi güncelleniyor..."
DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
info "Gerekli araçlar kuruluyor..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl jq wget gnupg lsb-release ufw >/dev/null 2>&1
ok "Araçlar hazır."

if ! command -v docker >/dev/null 2>&1; then
  info "Docker kuruluyor..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  systemctl enable --now docker
  ok "Docker kuruldu."
else
  ok "Docker zaten kurulu: $(docker --version | cut -d, -f1)"
fi
fi

##############################
# L1 UÇ NOKTALARI
##############################
section "ETHEREUM L1 BAĞLANTISI"

cat <<EOF
Robinhood Chain verisini Ethereum'a yazar, blob olarak. Node'un çalışabilmesi
için iki adrese ihtiyacı var:

  1) L1 execution RPC   (${PARENT_NAME}, chainId ${PARENT_ID})
  2) L1 beacon adresi   (blob verisi sadece burada durur)

Kendi Ethereum node'unuz varsa onun adreslerini, yoksa bir sağlayıcının
adreslerini girin. Bu adım isteğe bağlı değil, node bunlarsız senkronlanamaz.
EOF
echo ""

if [[ -z "$L1_RPC" ]]; then
  [[ "$NON_INTERACTIVE" == "1" ]] && abort "--l1-rpc verilmedi."
  read -rp "L1 execution RPC adresi: " L1_RPC
fi
if [[ -z "$L1_BEACON" ]]; then
  [[ "$NON_INTERACTIVE" == "1" ]] && abort "--l1-beacon verilmedi."
  read -rp "L1 beacon adresi: " L1_BEACON
fi
[[ -n "$L1_RPC" && -n "$L1_BEACON" ]] || abort "İki adres de zorunlu."

info "L1 execution adresi doğrulanıyor..."
# `|| true`: curl bağlanamazsa pipefail yüzünden script burada ölürdü ve
# kullanıcı "satır 288" hatası görürdü. Kontrolü aşağıda kendimiz yapıyoruz.
L1_CHAIN_HEX=$(curl -s --max-time 25 -X POST "$L1_RPC" \
  -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)
[[ -n "$L1_CHAIN_HEX" ]] || abort "L1 execution adresi cevap vermedi: ${L1_RPC}
        Adres doğru mu, sağlayıcınız ayakta mı ve anahtarınız geçerli mi kontrol edin."
L1_CHAIN=$((L1_CHAIN_HEX))
if [[ "$L1_CHAIN" != "$PARENT_ID" ]]; then
  abort "Yanlış L1: adres chainId ${L1_CHAIN} döndü, ${NETWORK} için ${PARENT_ID} (${PARENT_NAME}) gerekiyor."
fi
ok "L1 execution doğru: chainId ${L1_CHAIN} (${PARENT_NAME})"

# Node acilirken L1'de eski bir blok araligina eth_getLogs atiyor. Ucretsiz
# public RPC'lerin cogu bunu "archive requests require a personal token" diye
# reddediyor ve node veritabanini kuramadan oluyor. Burada onceden deniyoruz.
info "L1 arşiv sorgusu destekliyor mu, kontrol ediliyor..."
L1_HEAD_HEX=$(curl -s --max-time 25 -X POST "$L1_RPC" -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' 2>/dev/null \
  | jq -r '.result // empty' 2>/dev/null || true)
if [[ -n "$L1_HEAD_HEX" ]]; then
  OLD_BLOCK=$(printf '0x%x' $(( L1_HEAD_HEX - 200000 )))
  LOGS_ERR=$(curl -s --max-time 30 -X POST "$L1_RPC" -H 'content-type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"${OLD_BLOCK}\",\"toBlock\":\"${OLD_BLOCK}\"}]}" \
    2>/dev/null | jq -r '.error.message // empty' 2>/dev/null || true)
  if [[ -n "$LOGS_ERR" ]]; then
    warn "L1 adresiniz eski blok sorgusunu reddetti:"
    warn "  ${LOGS_ERR}"
    warn "Node açılırken bu sorguyu yapıyor. Arşiv desteği olmayan ücretsiz bir"
    warn "adres kullanıyorsanız kurulum senkron başlamadan hata verir."
    if [[ "$DRY_RUN" == "1" ]]; then
      warn "Kuru deneme olduğu için devam ediliyor."
    else
      confirm "Yine de devam edilsin mi?" "N" || abort "Kurulum iptal edildi."
    fi
  else
    ok "L1 arşiv sorgusu çalışıyor."
  fi
fi

info "L1 beacon adresi doğrulanıyor..."
BEACON_VER=$(curl -s --max-time 25 "${L1_BEACON%/}/eth/v1/node/version" 2>/dev/null \
  | jq -r '.data.version // empty' 2>/dev/null || true)
if [[ -z "$BEACON_VER" ]]; then
  warn "Beacon adresi /eth/v1/node/version sorusuna cevap vermedi."
  warn "Adres yanlışsa node blob verisini okuyamaz ve senkronlanamaz."
  confirm "Yine de devam edilsin mi?" "N" || abort "Kurulum iptal edildi."
else
  ok "Beacon cevap verdi: ${BEACON_VER}"
fi

##############################
# CONFIG DOSYALARI
##############################
section "CONFIG DOSYALARI"
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}"

fetch() {
  local name="$1"
  info "İndiriliyor: ${name}"
  curl -fsSL --max-time 180 "${CDN}/${name}" -o "${CONFIG_DIR}/${name}" \
    || abort "İndirilemedi: ${CDN}/${name}"
  jq -e . "${CONFIG_DIR}/${name}" >/dev/null 2>&1 \
    || abort "Geçerli JSON değil: ${name}"
  ok "${name} ($(du -h "${CONFIG_DIR}/${name}" | cut -f1))"
}

fetch "${CHAIN_INFO}"
[[ -n "$GENESIS" ]] && fetch "${GENESIS}"

# İndirilen dosyanın gerçekten istediğimiz ağ olduğunu doğrula. Yanlış config
# ile açılan bir node saatlerce senkronlanıp sonunda boş çıkar.
INFO_CHAIN=$(jq -r 'if type=="array" then .[0] else . end | .["chain-config"].chainId' "${CONFIG_DIR}/${CHAIN_INFO}")
[[ "$INFO_CHAIN" == "$CHAIN_ID" ]] \
  || abort "Config chainId ${INFO_CHAIN} diyor, ${NETWORK} için ${CHAIN_ID} bekleniyordu."
ok "Config doğrulandı: chainId ${CHAIN_ID}"

##############################
# SNAPSHOT
##############################
SNAPSHOT_URL=""
if [[ "$USE_SNAPSHOT" == "yes" ]]; then
  section "SNAPSHOT"
  info "Arbitrum snapshot indeksinden en güncel ${SNAPSHOT_TYPE} aranıyor..."
  SNAP_JSON=$(curl -fsSL --max-time 90 -A "robinhood-rpc-setup" "${SNAPSHOT_INDEX}") \
    || abort "Snapshot indeksi okunamadı."

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

  [[ -n "$SNAPSHOT_URL" && "$SNAPSHOT_URL" != "null" ]] \
    || abort "${SNAPSHOT_CHAIN} için ${SNAPSHOT_TYPE} snapshot bulunamadı."

  SNAP_GB=$(( SNAP_SIZE / 1000000000 ))
  info "Tarih  : ${SNAP_DATE}"
  info "Boyut  : ${SNAP_GB} GB (${SNAP_PARTS} parça)"
  info "Adres  : ${SNAPSHOT_URL}"

  if (( SNAP_PARTS > 1 )); then
    warn "Bu snapshot ${SNAP_PARTS} parçadan oluşuyor. Nitro tek parçayı kendisi indirir,"
    warn "çok parçalı olanlar için resmi dokümandaki elle birleştirme adımı gerekir."
    warn "Daha küçük bir tür seçmek isterseniz: --snapshot-type pruned"
    confirm "Yine de devam edilsin mi?" "N" || abort "Kurulum iptal edildi."
  fi

  info "Adres erişilebilir mi, kontrol ediliyor..."
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -I --max-time 60 "${SNAPSHOT_URL}")
  [[ "$HTTP_CODE" == "200" ]] || abort "Snapshot adresi ${HTTP_CODE} döndü."
  ok "Snapshot hazır. İndirmeyi node'un kendisi yapacak."
  warn "${SNAP_GB} GB indirilecek. Hattınıza göre saatler sürebilir, bu normal."
else
  warn "Snapshot kapalı. Node sıfırdan senkronlanacak, bu çok uzun sürer."
fi

if [[ "$DRY_RUN" == "1" ]]; then
  section "KURU DENEME BİTTİ"
  ok "Her şey yolunda. Gerçek kurulum için --dry-run olmadan çalıştırın."
  echo ""
  echo "  Ağ            : ${NETWORK} (chainId ${CHAIN_ID})"
  echo "  L1 execution  : doğrulandı (chainId ${L1_CHAIN})"
  echo "  L1 beacon     : ${BEACON_VER:-doğrulanamadı}"
  echo "  Config        : ${CONFIG_DIR}"
  echo "  Snapshot      : ${SNAPSHOT_URL:-kapalı}"
  echo "  Docker imajı  : ${NITRO_IMAGE} (çekilmedi)"
  echo ""
  exit 0
fi

##############################
# SERVIS
##############################
section "SERVİS"

DOCKER_ARGS=(
  "--chain.info-files=/home/nitro/config/${CHAIN_INFO}"
  "--parent-chain.connection.url=${L1_RPC}"
  "--parent-chain.blob-client.beacon-url=${L1_BEACON}"
  "--node.feed.input.url=${FEED_URL}"
  # Sequencer olmayan bir node bunu istiyor ve olmadan hic acilmiyor:
  # "Fatal configuration error: ForwardingTarget not set and not sequencer".
  # Resmi dokumandaki komutta yok, gercek calistirmada ortaya cikti. Buraya
  # agin kendi RPC'si yaziliyor, boylece node'a gonderilen islemler sequencer'a
  # iletilir. Sadece okuma yapacaksaniz --forwarding-target null verin.
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

info "Docker imajı çekiliyor: ${NITRO_IMAGE} (yaklaşık 1.4 GB)"
if ! docker pull "${NITRO_IMAGE}" >/dev/null 2>/tmp/rh-pull.err; then
  err "Docker imajı çekilemedi. Docker'ın verdiği hata:"
  sed 's/^/        /' /tmp/rh-pull.err | head -5
  abort "İnternet bağlantınızı ve diskte yer olduğunu kontrol edip tekrar deneyin."
fi
ok "İmaj hazır."

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
$(printf '  %s \\\n' "${DOCKER_ARGS[@]}" | sed '$ s/ \\$//')
ExecStop=/usr/bin/docker stop -t 120 ${SERVICE}
Restart=always
RestartSec=15
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE}" >/dev/null
ok "Servis yazıldı: ${SERVICE}.service"

##############################
# GUVENLIK DUVARI
##############################
section "GÜVENLİK DUVARI"
if [[ "$EXPOSE_RPC" == "yes" ]]; then
  if [[ -n "$ALLOWED_IP" ]]; then
    ufw allow from "${ALLOWED_IP}" to any port "${RPC_PORT}" proto tcp >/dev/null
    ufw allow from "${ALLOWED_IP}" to any port "${WS_PORT}" proto tcp >/dev/null
    ok "RPC sadece ${ALLOWED_IP} adresine açıldı."
  else
    warn "RPC tüm internete açılıyor. Bu node'unuzu herkesin kullanabileceği anlamına gelir."
    warn "Tek bir IP'ye kısıtlamak için: --allowed-ip <ip>"
    if confirm "Yine de herkese açılsın mı?" "N"; then
      ufw allow "${RPC_PORT}"/tcp >/dev/null
      ufw allow "${WS_PORT}"/tcp >/dev/null
      ok "Portlar açıldı."
    else
      info "Portlar açılmadı, node sadece sunucunun kendisinden erişilebilir."
    fi
  fi
else
  info "RPC dışarı açılmadı. Sadece bu sunucudan erişilebilir."
  info "Sonradan açmak için: ufw allow from <ip> to any port ${RPC_PORT} proto tcp"
fi

##############################
# BASLAT
##############################
section "BAŞLATILIYOR"
systemctl restart "${SERVICE}"
sleep 8
if systemctl is-active --quiet "${SERVICE}"; then
  ok "Servis çalışıyor."
else
  err "Servis başlamadı. Son satırlar:"
  journalctl -u "${SERVICE}" -n 15 --no-pager 2>/dev/null | sed 's/^/        /'
  echo ""
  err "Tam log için: journalctl -u ${SERVICE} -n 100 --no-pager"
  exit 1
fi

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
