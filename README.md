# Robinhood Chain RPC Node Kurulum Rehberi

Bu rehber, Robinhood Chain üzerinde kendi RPC node'unuzu kurmanız için hazırlandı. Kurulumun
tamamı Robinhood'un resmi dokümanını takip eder: config dosyaları Robinhood'un kendi CDN'inden,
docker imajı dokümanın sabitlediği sürümden, snapshot ise Arbitrum'un resmi snapshot indeksinden
gelir. Hiçbir adres elle yazılmadı, hepsi kaynağından çekiliyor.

Yanındaki `script.sh` bütün adımları tek komutta yapar. Rehberi okuyup elle de kurabilirsiniz,
ikisi de aynı sonucu verir.

> **Bu kurulum küçük bir VPS'e sığmaz.** Resmi doküman en az 64 GB RAM istiyor, önerdiği 128 GB.
> Mainnet snapshot'ı bugün itibarıyla 466 GB ve doküman "zincir boyutunun 2 katı + %20" diyor,
> yani gerçekçi disk ihtiyacı 1.1 TB NVMe. Üstüne, node'un çalışması için kendi Ethereum L1
> bağlantınız gerekiyor. Diğer rehberlerimdeki 6 dolarlık sunucularla olacak bir iş değil, en
> baştan bilin.

---

## Genel Bilgiler

| Özellik            | Açıklama                                                     |
| ------------------ | ------------------------------------------------------------ |
| Ağ                 | Robinhood Chain (mainnet)                                     |
| Chain ID           | 4663                                                          |
| Tür                | Arbitrum Nitro L2, Ethereum üzerine yazar                     |
| Gaz tokeni         | ETH                                                           |
| Üst zincir         | Ethereum mainnet (chainId 1)                                  |
| Resmi doküman      | https://docs.robinhood.com/chain/run-a-full-node/             |
| Public RPC         | https://rpc.mainnet.chain.robinhood.com                        |
| Explorer           | https://robinhoodchain.blockscout.com                          |
| Docker imajı       | `offchainlabs/nitro-node:v3.11.2-3599aca`                     |
| Portlar            | 8547 (HTTP RPC), 8548 (WebSocket)                             |

Testnet de kurulabilir. Adı **Robinhood Chain Sepolia**, chainId **46630**, üst zinciri
**Sepolia** (11155111). Yani testnet için Sepolia L1 bağlantısı gerekir, mainnet'inki işe yaramaz.

---

## Sistem Gereksinimleri

| Gereksinim         | Detaylar                                                              |
| ------------------ | --------------------------------------------------------------------- |
| RAM                | En az 64 GB, önerilen 128 GB                                          |
| Disk               | Yerel NVMe SSD, mainnet için en az 1.1 TB boş                        |
| İşletim Sistemi    | Ubuntu 22.04 veya üzeri (Debian tabanlı)                              |
| Docker             | Script kurmuyorsa kendisi kurar                                       |
| Ethereum L1        | Bir execution RPC **ve** bir beacon adresi. İkisi de zorunlu          |
| L1 arşiv desteği   | Execution adresi eski bloklarda `eth_getLogs` cevaplayabilmeli        |

Bugün ölçtüğüm snapshot boyutları:

| Snapshot türü  | Mainnet     | Testnet     |
| -------------- | ----------- | ----------- |
| `pruned`       | **466 GB**  | 233 GB      |
| `full-path`    | 449 GB      | 277 GB      |
| `archive-path` | 701 GB      | 3.669 GB    |

Normal bir RPC node için `pruned` yeterli. Eski blokların state'ine erişmeniz gerekmiyorsa
arşive ihtiyacınız yok.

---

## Ethereum L1 Bağlantısı

Bu adımı en başa koyuyorum çünkü kurulumun asıl maliyeti burada ve çoğu rehber bunu atlıyor.

Robinhood Chain verisini Ethereum'a **blob** olarak yazar. Node'un bu veriyi okuyabilmesi için
iki ayrı adres gerekir:

1. **L1 execution RPC**, sıradan bir Ethereum RPC adresi.
2. **L1 beacon adresi**, blob verisi sadece burada durur, execution tarafında yoktur.

Kendi Ethereum node'unuz varsa ikisi de sizde vardır. Yoksa bir sağlayıcıdan alacaksınız.
Beacon adresi vermeyen sağlayıcılar var, aldığınızın verdiğinden emin olun.

Bir şey daha: **execution adresiniz arşiv sorgusu destekliyor olmalı.** Node açılırken L1'de eski
bir blok aralığına `eth_getLogs` atıyor. Ücretsiz public adreslerin çoğu bunu reddediyor ve node
veritabanını kuramadan ölüyor. Bunu gerçek bir kurulumda test ederken şu hatayla karşılaştım:

```
ERROR error initializing database
err="failed getting delayed messages ...: 403 Forbidden:
     Archive requests require a personal token"
```

Script bu üç şeyi de kurulumu başlatmadan önce test ediyor: L1 doğru ağ mı, arşiv sorgusu
çalışıyor mu, beacon cevap veriyor mu.

---

## Sunucu Önerileri

Bu iş için kiralık VPS değil, dedicated ya da yüksek RAM'li bir makine gerekiyor.

- **Hetzner** dedicated sunucular → 64 GB RAM ve NVMe seçenekleri makul fiyatlı.
- **OVH** ya da **Contabo** dedicated → benzer aralıkta.
- Kendi makineniz varsa en iyisi o, çünkü diskin yerel NVMe olması önemli. Ağ üzerinden bağlı
  disk (network storage) bu iş için yavaş kalır.

---

## 1- Sunucuya Bağlanma

```bash
ssh root@[Sunucu_IP]
```

- "[Sunucu_IP]" kısmına sunucunuzun IP adresini girin.

Windows kullanıyorsanız önce WSL kurulumu rehberimi takip edin:
https://x.com/UfukDegen/status/1944066889346429338

---

## 2- Scripti İndirme

```bash
git clone https://github.com/UfukNode/robinhood-rpc-setup.git
cd robinhood-rpc-setup
chmod +x script.sh
```

---

## 3- Önce Kuru Deneme

Kurulumu başlatmadan önce her şeyin yerinde olduğunu görün. Bu adım hiçbir şey kurmaz, sadece
kontrol eder: L1 adresleriniz doğru mu, disk yetiyor mu, config dosyaları iniyor mu, snapshot
erişilebilir mi.

```bash
sudo ./script.sh --dry-run \
  --l1-rpc [L1_RPC_ADRESINIZ] \
  --l1-beacon [BEACON_ADRESINIZ]
```

- "[L1_RPC_ADRESINIZ]" kısmına Ethereum execution RPC adresinizi girin.
- "[BEACON_ADRESINIZ]" kısmına beacon adresinizi girin.

Aşağıdaki gibi bitiyorsa hazırsınız:

```
[tamam] Her şey yolunda. Gerçek kurulum için --dry-run olmadan çalıştırın.

  Ağ            : mainnet (chainId 4663)
  L1 execution  : doğrulandı (chainId 1)
  L1 beacon     : Lighthouse/v8.2.2-e423a66/x86_64-linux
  Snapshot      : https://robinhood-snapshots.offchainlabs.com/robinhood%20chain/...
```

Hata alırsanız kurulumu başlatmayın, önce onu çözün. 466 GB indirdikten sonra yanlış adres
yüzünden baştan başlamak istemezsiniz.

---

## 4- Kurulum

```bash
sudo ./script.sh \
  --l1-rpc [L1_RPC_ADRESINIZ] \
  --l1-beacon [BEACON_ADRESINIZ]
```

Script sırasıyla şunları yapar:

- RAM ve diski kontrol eder, yetersizse uyarır.
- Docker yoksa kurar.
- L1 adreslerinizi test eder, yanlış ağa bağlıysanız durdurur.
- Config dosyalarını Robinhood CDN'inden indirir ve chainId'sini doğrular.
- Arbitrum indeksinden en güncel snapshot adresini bulur.
- `robinhood-rpc` adında bir systemd servisi yazar ve başlatır.

Snapshot indirmeyi node'un kendisi yapar. 466 GB, hattınıza göre saatler sürer.

---

## 5- Logları İzleme

```bash
journalctl -u robinhood-rpc -f
```

İlk saatlerde blok numarasının ilerlememesi normaldir, snapshot iniyordur. Log akıyorsa her şey
yolundadır.

---

## 6- Senkron Kontrolü

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}'
```

- Cevap `false` olduğunda senkron bitmiştir.

Blok numarasına bakmak için:

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'
```

Çıkan sayıyı explorer'daki son blokla karşılaştırın: https://robinhoodchain.blockscout.com

---

## 7- RPC'yi Kullanma

Node senkronlandıktan sonra kendi RPC adresiniz hazır demektir:

```text
HTTP       : http://127.0.0.1:8547
WebSocket  : ws://127.0.0.1:8548
Chain ID   : 4663
```

Cüzdanınıza ya da aracınıza ekleyeceğiniz ağ bilgileri de bunlar. Gaz tokeni ETH.

Node'a başka bir makineden erişmek isterseniz kurulumu şu bayraklarla yapın:

```bash
sudo ./script.sh --expose-rpc yes --allowed-ip [SIZIN_IP] \
  --l1-rpc [L1_RPC_ADRESINIZ] --l1-beacon [BEACON_ADRESINIZ]
```

- "[SIZIN_IP]" kısmına bağlanacağınız makinenin IP adresini girin.
- IP vermezseniz port tüm internete açılır ve node'unuzu herkes kullanır. Script bunu ayrıca
  sorar, farkında olmadan açılmasın diye.

---

## Komutlar

| Komut                                   | Açıklama                             |
| --------------------------------------- | ------------------------------------ |
| `journalctl -u robinhood-rpc -f`        | Logları canlı izle                   |
| `systemctl status robinhood-rpc`        | Servis durumu                        |
| `systemctl stop robinhood-rpc`          | Durdur                               |
| `systemctl start robinhood-rpc`         | Başlat                               |
| `systemctl restart robinhood-rpc`       | Yeniden başlat                       |
| `sudo ./script.sh --uninstall`          | Servisi kaldır (veri korunur)        |
| `sudo ./script.sh --help`               | Tüm seçenekler                       |

---

## Script Seçenekleri

| Seçenek                    | Ne işe yarar                                              |
| -------------------------- | --------------------------------------------------------- |
| `--network mainnet\|testnet` | Hangi ağ kurulacak (varsayılan mainnet)                  |
| `--l1-rpc <url>`           | Ethereum L1 execution adresi, zorunlu                     |
| `--l1-beacon <url>`        | Ethereum L1 beacon adresi, zorunlu                        |
| `--dry-run`                | Hiçbir şey kurmaz, sadece kontrol eder                    |
| `--expose-rpc yes`         | RPC'yi dışarı açar                                        |
| `--allowed-ip <ip>`        | Dışarı açarken sadece bu IP'ye izin verir                 |
| `--rpc-port <port>`        | HTTP portunu değiştirir (varsayılan 8547)                 |
| `--ws-port <port>`         | WebSocket portunu değiştirir (varsayılan 8548)            |
| `--data-dir <yol>`         | Veri ve config kökü (varsayılan `/root/rh`)               |
| `--snapshot-type <tür>`    | `pruned`, `full-path` veya `archive-path`                 |
| `--forwarding-target <url>` | İşlemlerin iletileceği adres, varsayılan ağın kendi RPC'si. Sadece okuma yapacaksanız `null` |
| `--no-snapshot`            | Snapshot indirmez, sıfırdan senkronlar (çok uzun sürer)   |
| `--non-interactive`        | Soru sormaz                                               |
| `--uninstall`              | Servisi ve config'i kaldırır, veriye dokunmaz             |

---

## ✅ Tavsiyeler

- Kurulumdan önce mutlaka `--dry-run` çalıştırın. 466 GB indirdikten sonra hata bulmak can sıkar.
- Diski `/root` altında değil, ayrı bir NVMe diskte tutmak isterseniz `--data-dir` kullanın.
- RPC'yi tüm internete açmayın. Açacaksanız `--allowed-ip` ile tek bir adrese kısıtlayın.
- Snapshot açılırken arşiv ve açılmış veri bir süre birlikte diskte durur. Disk hesabını buna
  göre yapın, tam sınırda başlamayın.
- Node durursa systemd kendisi yeniden başlatır. Sürekli yeniden başlıyorsa loga bakın, genelde
  sebep L1 bağlantısının kopmasıdır.
- Testnet kuracaksanız L1 adreslerinizin **Sepolia** olması gerekir. Script yanlış ağa bağlıysa
  size söyler.
- L1 için ücretsiz public adres kullanmayın. Ağ doğru olsa bile arşiv sorgusunu reddediyorlar ve
  node açılmıyor. Bunu ölçtüm, hata mesajını yukarıya koydum.

---

## Sorun Giderme

**"L1 execution adresi cevap vermedi"**
Adres yanlış, sağlayıcı kapalı ya da anahtarınız geçersiz. Şununla kendiniz test edin:

```bash
curl -s -X POST [L1_RPC_ADRESINIZ] -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
```

**"Yanlış L1: adres chainId ... döndü"**
Mainnet kuruyorsanız Ethereum mainnet, testnet kuruyorsanız Sepolia adresi vermelisiniz.

**"Beacon adresi cevap vermedi"**
Sağlayıcınız beacon API vermiyor olabilir. Şununla test edin:

```bash
curl -s [BEACON_ADRESINIZ]/eth/v1/node/version
```

**"Archive requests require a personal token" ya da benzeri 403**
Execution adresiniz eski blok sorgusuna izin vermiyor. Arşiv destekli bir adres gerekiyor.
Kendiniz şöyle test edebilirsiniz, `error` dönerse o adres bu iş için yeterli değildir:

```bash
curl -s -X POST [L1_RPC_ADRESINIZ] -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_getLogs","params":[{"fromBlock":"0x1400000","toBlock":"0x1400000"}]}'
```

**"ForwardingTarget not set and not sequencer"**
Bu hatayı görmeniz gerekmiyor, script gerekli bayrağı kendisi ekliyor. Resmi dokümandaki komutta
bu bayrak yok ama node onsuz hiç açılmıyor, gerçek kurulumda ortaya çıktı. Elle kuruyorsanız
`--execution.forwarding-target=https://rpc.mainnet.chain.robinhood.com` eklemeyi unutmayın.

**Servis sürekli yeniden başlıyor**
```bash
journalctl -u robinhood-rpc -n 100 --no-pager
```
Genelde L1 bağlantısı ya da disk dolmasıdır.

---

Kaynak: [Robinhood Chain resmi dokümanı](https://docs.robinhood.com/chain/run-a-full-node/)

Hazırlayan: [@UfukDegen](https://x.com/UfukDegen)
