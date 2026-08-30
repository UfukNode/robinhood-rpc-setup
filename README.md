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

İkisini birden tek yerden almak isterseniz **Alchemy** hem RPC hem beacon adresi veriyor:
https://www.alchemy.com/rpc/ethereum

Ücretsiz adresleri de tek tek denedim, arşiv sorgusuna cevap verenler şunlar:

| Adres                                    | Arşiv sorgusu |
| ---------------------------------------- | ------------- |
| `https://eth.drpc.org`                   | çalışıyor     |
| `https://rpc.flashbots.net`              | çalışıyor     |
| `https://eth-mainnet.public.blastapi.io` | çalışıyor     |
| `https://1rpc.io/eth`                    | çalışıyor     |
| `https://ethereum-rpc.publicnode.com`    | reddediyor    |
| `https://rpc.ankr.com/eth`               | anahtar ister |
| `https://cloudflare-eth.com`             | hata veriyor  |

Bunlar kuru denemede işinizi görür ama uzun senkron sırasında hız sınırına takılabilirsiniz.
Gerçek kurulum için kendi node'unuz ya da anahtarlı bir sağlayıcı daha sağlam olur.

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

## 3- Dil Seçimi

Script başlayınca dil sorar:

```text
  Dil seçin / Choose language

    1) Türkçe
    2) English

  [1/2]:
```

Sormadan geçmek isterseniz `--lang tr` ya da `--lang en` verin. Bütün mesajlar, sorular ve yardım
ekranı seçtiğiniz dilde çıkar.

---

## 4- Önce Kuru Deneme

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

Ekranda göreceğiniz şey aynen bu:

```text
[bilgi] L1 execution adresi doğrulanıyor...
[tamam] L1 execution doğru: chainId 1 (Ethereum mainnet)
[bilgi] L1 arşiv sorgusu destekliyor mu, kontrol ediliyor...
[tamam] L1 arşiv sorgusu çalışıyor.
[bilgi] L1 beacon adresi doğrulanıyor...
[tamam] Beacon cevap verdi: Lighthouse/v8.2.2-e423a66/x86_64-linux

========== CONFIG DOSYALARI ==========

[bilgi] İndiriliyor: robinhood-chain-info.json
[tamam] robinhood-chain-info.json (4.0K)
[bilgi] İndiriliyor: robinhood-genesis.json
[tamam] robinhood-genesis.json (616K)
[tamam] Config doğrulandı: chainId 4663

========== SNAPSHOT ==========

[bilgi] Arbitrum snapshot indeksinden en güncel pruned aranıyor...
[bilgi] Tarih  : 2026-08-26
[bilgi] Boyut  : 465 GB (1 parça)
[bilgi] Adres  : https://robinhood-snapshots.offchainlabs.com/robinhood%20chain/2026-08-26-29670eab/pruned.tar.part0000
[bilgi] Adres erişilebilir mi, kontrol ediliyor...
[tamam] Snapshot hazır. İndirmeyi node'un kendisi yapacak.
[uyarı] 465 GB indirilecek. Hattınıza göre saatler sürebilir, bu normal.

========== KURU DENEME BİTTİ ==========

[tamam] Her şey yolunda. Gerçek kurulum için --dry-run olmadan çalıştırın.

  Ağ            : mainnet (chainId 4663)
  L1 execution  : doğrulandı (chainId 1)
  L1 beacon     : Lighthouse/v8.2.2-e423a66/x86_64-linux
  Config        : /tmp/rh/config
  Snapshot      : https://robinhood-snapshots.offchainlabs.com/robinhood%20chain/2026-08-26-29670eab/pruned.tar.part0000
  Docker imajı  : offchainlabs/nitro-node:v3.11.2-3599aca (çekilmedi)
```

Hata alırsanız kurulumu başlatmayın, önce onu çözün. 466 GB indirdikten sonra yanlış adres
yüzünden baştan başlamak istemezsiniz.

---

## 5- Kurulum

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

Kurulum bittiğinde ekran şöyle görünür:

```text
========== SERVİS ==========

[bilgi] Docker imajı çekiliyor: offchainlabs/nitro-node:v3.11.2-3599aca (yaklaşık 1.4 GB)
[tamam] İmaj hazır.
[tamam] Servis yazıldı: robinhood-rpc.service

========== GÜVENLİK DUVARI ==========

[bilgi] RPC dışarı açılmadı. Sadece bu sunucudan erişilebilir.
[bilgi] Sonradan açmak için: ufw allow from <ip> to any port 8547 proto tcp

========== BAŞLATILIYOR ==========

[tamam] Servis çalışıyor.

Kurulum tamamlandı.

  Ağ         : mainnet (chainId 4663)
  RPC        : http://127.0.0.1:8547
  WebSocket  : ws://127.0.0.1:8548
  Veri       : /root/rh/robinhood-nitro-data
  Config     : /root/rh/config

Sık kullanılan komutlar

  Log izle        : journalctl -u robinhood-rpc -f
  Durum           : systemctl status robinhood-rpc
  Durdur          : systemctl stop robinhood-rpc
  Başlat          : systemctl start robinhood-rpc
  Kaldır          : sudo ./script.sh --uninstall

Senkron kontrolü

  curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}'

  Cevap false olduğunda senkron bitmiştir. O ana kadar blok numarası
  geriden gelir, bu normaldir.

  curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'

[uyarı] Snapshot indirme ve açma işlemi saatler sürer. İlk saatlerde blok
[uyarı] numarasının ilerlememesi normaldir, log akıyorsa her şey yolundadır.
```

---

## 6- Logları İzleme

```bash
journalctl -u robinhood-rpc -f
```

Node ayağa kalkarken göreceğiniz satırlar şunlar. `HTTP server started` ve `WebSocket enabled`
satırlarını gördüyseniz RPC'niz dinlemeye başlamış demektir:

```text
INFO [.....] Running Arbitrum nitro node       revision=v3.11.2-3599aca
INFO [.....] connected to l1 chain             l1url=https://... l1chainid=1
INFO [.....] Defaulting to pebble as the backing database
INFO [.....] HTTP server started               endpoint=[::]:8547 auth=false cors=* vhosts=*
INFO [.....] WebSocket enabled                 url=ws://[::]:8548
INFO [.....] InboxTracker                      sequencerBatchCount=1 messageCount=1 l1Block=24,994,238
```

İlk saatlerde blok numarasının ilerlememesi normaldir, snapshot iniyordur. Log akıyorsa her şey
yolundadır.

---

## 7- Senkron Kontrolü

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

Node'un doğru ağda olduğunu şöyle teyit edebilirsiniz:

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
```

```text
{"jsonrpc":"2.0","id":1,"result":"0x1237"}
```

`0x1237` onaltılık tabanda **4663** demektir, yani Robinhood Chain. Farklı bir sayı görüyorsanız
yanlış config ile açılmışsınızdır.

Çıkan blok numarasını explorer'daki son blokla karşılaştırın:
https://robinhoodchain.blockscout.com

---

## 8- RPC'yi Kullanma

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
| `--lang tr\|en`            | Arayüz dili. Verilmezse başta sorulur                      |
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

## Test Edildi

Script sıfırdan kurulan bir sunucuda uçtan uca çalıştırıldı. Doğrulananlar:

- Ubuntu 22.04 ve 24.04 üzerinde, hiçbir şey kurulu değilken (`jq` yok, `docker` yok) çalışıyor.
- Docker'ı kendisi kuruyor, nitro imajını çekiyor, systemd servisini yazıp başlatıyor.
- Node ayağa kalkıyor, L1'e bağlanıyor, HTTP 8547 ve WebSocket 8548 dinlemeye başlıyor.
- `eth_chainId` **4663** dönüyor, yani doğru ağ.
- `--uninstall` servisi ve config'i kaldırıyor, veri klasörüne dokunmuyor.
- Türkçe ve İngilizce, ikisi de uçtan uca çalışıyor. Dil sorusu, `--lang` bayrağı ve iki dildeki
  yardım ekranı ayrı ayrı denendi.
- Snapshot açıkken kurulum yapılıp systemd servisinin gerçekten başladığı ve node'un snapshot
  indirmeye geçtiği doğrulandı.
- Hata yolları da denendi: yanlış ağ, ulaşılamayan L1, arşiv desteklemeyen L1, cevapsız beacon.
  Hepsi ne olduğunu söyleyen bir mesajla duruyor.

Doğrulanmayan tek şey senkronun sonuna kadar gitmesi. Onun için 64 GB RAM ve 1.2 TB disk gerekiyor.

Resmi dokümanda olmayan üç şey gerçek çalıştırmada ortaya çıktı ve üçü de kurulumu baştan
bozuyordu:

`--execution.forwarding-target` olmadan node hiç açılmıyor, "ForwardingTarget not set and not
sequencer" deyip duruyor.

Arşiv sorgusu desteklemeyen bir L1 adresiyle veritabanı kurulamadan ölüyor.

Snapshot adresi boşluk yüzünden `%20` içeriyor ve systemd unit dosyasında `%` özel karakter.
Escape edilmeden yazılınca systemd servisi hiç başlatmıyor, `Unit robinhood-rpc.service has a bad
unit file setting` diyor. Bu hata sadece snapshot ile kurulunca çıkıyor, o yüzden ilk testlerde
görünmedi. Script artık `%%` yazıyor.

Üçünü de script hallediyor.

---

Kaynak: [Robinhood Chain resmi dokümanı](https://docs.robinhood.com/chain/run-a-full-node/)

Hazırlayan: [@UfukDegen](https://x.com/UfukDegen)
