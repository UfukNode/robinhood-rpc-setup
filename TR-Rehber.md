# Robinhood Chain RPC Node Kurulum Rehberi

English guide: [README.md](README.md)

Bu rehber, Ubuntu sunucunuza tek script ile kendi Robinhood Chain RPC node'unuzu kurmanızı sağlar.
Birkaç soruyu cevapladıktan sonra sistem kontrolü, gerekli dosyalar, snapshot indirme ve servis
kurulumu otomatik yapılır.

Başlamadan önce yalnızca uygun bir sunucuya ve iki Ethereum sağlayıcı adresine ihtiyacınız var.
Aşağıdaki bölümlerde bu adresleri nereden alacağınız ve senkron bittikten sonra RPC'yi nasıl
kullanacağınız adım adım anlatılıyor.

Basitçe anlatmak gerekirse RPC, cüzdanınızın, botunuzun veya uygulamanızın Robinhood Chain ile
konuşmasını sağlayan bağlantıdır. Bu kurulumla ortak bir public RPC yerine kendi sunucunuzdaki
bağlantıyı kullanırsınız.

---

## Genel Bilgiler

| Özellik            | Açıklama                                                     |
| ------------------ | ------------------------------------------------------------ |
| Ağ                 | Robinhood Chain (mainnet)                                     |
| Chain ID           | 4663                                                          |
| Resmi doküman      | https://docs.robinhood.com/chain/run-a-full-node/             |
| Public RPC         | https://rpc.mainnet.chain.robinhood.com                        |
| Explorer           | https://robinhoodchain.blockscout.com                          |

---

## Sistem Gereksinimleri

| Gereksinim         | Detaylar                                                              |
| ------------------ | --------------------------------------------------------------------- |
| RAM                | En az 64 GB, önerilen 128 GB                                          |
| Disk               | Birkaç TB yerel NVMe; 4 TB veya üzeri önerilir                        |
| İşletim Sistemi    | Ubuntu 22.04 veya 24.04                                                |
| Docker             | Kurulu değilse script kendisi kurar                                   |
| Ethereum L1        | Bir execution RPC **ve** bir beacon adresi. İkisi de zorunlu          |

Script tamamlanmış en güncel snapshot'ı otomatik bulur ve kurulumdan önce boyutunu gösterir.
Snapshot, blockchain verisinin kuruluma hazır bir kopyasıdır. İndirme yüzlerce GB olabilir, fakat
tamamlanan veritabanı bundan çok daha büyüktür. Birkaç TB NVMe kullanın ve snapshot açılırken
fazladan boş alan bırakın.

---

## Ethereum L1 Bağlantısı

Kuruluma başlamadan önce bir RPC sağlayıcısından şu iki **Ethereum Mainnet** adresini alın:

1. **Execution RPC adresi**
2. **Beacon RPC adresi**

Bunlar Robinhood RPC adresi değil, Ethereum adresleridir. Kurulum scripti iki adresi de sizden ister
ve snapshot indirmeden önce çalışıp çalışmadıklarını kontrol eder.

İki adresi de veren sağlayıcılardan biri Alchemy'dir. Ethereum Mainnet uygulaması oluşturduktan sonra
adresler genellikle şöyle görünür:

```text
Execution: https://eth-mainnet.g.alchemy.com/v2/SIZIN_ANAHTARINIZ
Beacon:    https://eth-mainnetbeacon.g.alchemy.com/v2/SIZIN_ANAHTARINIZ
```

`SIZIN_ANAHTARINIZ` kısmını kendi anahtarınızla değiştirin. İlk senkron çok fazla istek gönderdiği
için ücretsiz paketin kotası yetmeyebilir. Paketinizin geçmiş Ethereum verilerini desteklediğinden
emin olun.

API anahtarınızı paylaşmayın. Nitro bu adresi loga yazabilir; ekran görüntüsü paylaşmadan önce
anahtarı gizleyin. Yanlışlıkla paylaşırsanız sağlayıcı panelinden hemen yenileyin.

<details>
<summary>Neden iki ayrı Ethereum adresi gerekiyor?</summary>

Robinhood Chain bazı verilerini Ethereum üzerinde tutar. Execution adresi normal Ethereum verisini,
beacon adresi ise blob verisini sağlar. Node zinciri kurabilmek ve doğrulayabilmek için ikisine de
ihtiyaç duyar. Script ayrıca execution sağlayıcısının eski bir `eth_getLogs` isteğine cevap verip
vermediğini kontrol eder. Beacon bağlantısının çalışması bütün eski blob verilerinin tutulduğunu tek
başına kanıtlamaz; sağlayıcınızdan historical blob desteğini doğrulayın.

</details>

---

## Sunucu Seçimi

Sunucuyu yalnızca sağlayıcı adına bakarak seçmeyin. Pakette şunlar bulunmalı:

- En az 8 çekirdekli modern işlemci
- En az 64 GB RAM; önerilen 128 GB
- Birkaç TB yerel NVMe; 4 TB veya üzeri daha güvenli bir başlangıçtır
- Ubuntu 22.04 veya 24.04

HDD veya yavaş ağ diski kullanmayın. Snapshot açılırken indirme dosyası ve oluşan veritabanı aynı
anda diskte durur. Yalnızca indirme dosyasının sığdığı bir disk yeterli değildir.

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

![Repository klonlama ve script izni](assets/tr/ekran-goruntusu-01-repo-kurulumu.png)

---

## 3- Kurulum

```bash
sudo ./script.sh
```

---

## 4- Dil Seçimi ve Diğer Seçimler:

Script başlayınca dil sorar. Burada seçeceğiniz dil ile sorular ve yardım ekranı seçtiğiniz dilde
çıkar.

![Türkçe dil seçimi](assets/tr/ekran-goruntusu-02-dil-secimi.png)

Script sırasıyla şunları yapar:

- RAM ve diski kontrol eder, yetersizse uyarır.
- Docker yoksa kurar.
- Verdiğiniz iki Ethereum adresini kontrol eder.
- Resmî Robinhood ağ dosyalarını indirir ve doğrular.
- Tamamlanmış en güncel snapshot'ı bulur ve kontrol eder.
- Robinhood RPC servisini kurup başlatır.

![Sistem, L1, config ve snapshot ön kontrolleri](assets/tr/ekran-goruntusu-03-on-kontroller.png)

Snapshot boyutu zamanla değişir. Script güncel boyutu başlamadan önce ekrana yazar; indirmeyi Nitro
kendi yapar ve bu işlem saatler sürebilir.

Kurulum bittiğinde servis, güvenlik duvarı ve yerel RPC bilgileri tek ekranda gösterilir:

![Robinhood RPC kurulumunun tamamlanması](assets/tr/ekran-goruntusu-04-kurulum-tamamlandi.png)

---

## 5- Logları İzleme

```bash
journalctl -u robinhood-rpc -f
```

Log ekranında node'un başlayıp başlamadığını ve snapshot indirmesinin ilerleyip ilerlemediğini
görürsünüz:

![Robinhood RPC canlı servis logları](assets/tr/ekran-goruntusu-05-canli-loglar.png)

İlk indirme saatler sürebilir. `transferred ... bytes` değeri artıyorsa node çalışmaya devam ediyor
demektir. Snapshot indirilip açılana kadar `8547` portu cevap vermeyebilir. Bu normaldir.

---

## 6- Senkron Kontrolü

Bu komutu RPC sunucusunda çalıştırın:

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_syncing","params":[]}'
```

Komut henüz cevap vermiyorsa snapshot hazırlanmaya devam ediyordur; daha sonra tekrar deneyin.
Cevap `false` olduğunda senkron bitmiştir. Ardından doğru ağı kullandığınızı kontrol edin:

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
```

Senkron tamamlandıktan sonra örnek doğrulama görünümü:

![Senkron ve Robinhood Chain ID doğrulaması](assets/tr/ekran-goruntusu-06-rpc-dogrulama.png)

`0x1237` onaltılık tabanda **4663** demektir, yani Robinhood Chain. Farklı bir sayı görüyorsanız
yanlış config ile açılmışsınızdır.

Son blokları https://robinhoodchain.blockscout.com adresinden takip edebilirsiniz.

---

## 7- RPC'yi Kullanma

Senkron bittikten sonra RPC'niz hazırdır. Nasıl bağlanacağınız, cüzdanınızın, botunuzun veya
uygulamanızın nerede çalıştığına göre değişir.

### Seçenek A: Uygulama RPC sunucusunda çalışıyor

Aynı sunucuda çalışan uygulamanıza şu adresleri doğrudan yazın:

```text
HTTP       : http://127.0.0.1:8547
WebSocket  : ws://127.0.0.1:8548
```

Bu durumda SSH tüneline ihtiyacınız yoktur.

### Seçenek B: Kendi bilgisayarınızdan bağlanma

Aşağıdaki komutu RPC sunucusunda değil, **kendi bilgisayarınızda** çalıştırın. `[SUNUCU_IP]` kısmını
sunucunuzun IP adresiyle değiştirin:

```bash
ssh -N -L 8547:127.0.0.1:8547 -L 8548:127.0.0.1:8548 root@[SUNUCU_IP]
```

Sorulduğunda sunucu şifrenizi girin ve bu terminal penceresini kapatmayın. Bu komut güvenli bir SSH
tüneli açar. Artık bilgisayarınızdaki uygulamalar şu adresleri kullanabilir:

```text
HTTP       : http://127.0.0.1:8547
WebSocket  : ws://127.0.0.1:8548
```

Bu yöntemde RPC portunu internete açmanız gerekmez.

### MetaMask veya başka bir cüzdana ekleme

SSH tüneli açıkken cüzdanınıza şu özel ağı ekleyin:

```text
Ağ adı       : Robinhood Chain
RPC URL      : http://127.0.0.1:8547
Chain ID     : 4663
Para birimi  : ETH
Explorer     : https://robinhoodchain.blockscout.com
```

Bağlantıyı kontrol etmek için bilgisayarınızda ikinci bir terminal açıp çalıştırın:

```bash
curl -s -X POST http://127.0.0.1:8547 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
```

Çalışan Robinhood RPC `0x1237` sonucunu döndürür. Bu değer 4663 chain ID'sidir.

### Seçenek C: Başka bir sunucuya erişim verme

Bu gelişmiş bir seçenektir. Yalnızca bağlanacak diğer sunucunun sabit IP adresi varsa kullanın.
Kurulum sırasında şu komutu çalıştırın:


```bash
sudo ./script.sh --expose-rpc yes --allowed-ip [SIZIN_IP] \
  --l1-rpc [L1_RPC_ADRESINIZ] --l1-beacon [BEACON_ADRESINIZ]
```

`[SIZIN_IP]` kısmına RPC'yi kullanacak bilgisayarın veya sunucunun public IP adresini yazın.
`--allowed-ip` olmadan `--expose-rpc yes` kullanmayın. Herkese açık bir üretim RPC'si ayrıca Nginx
veya Caddy üzerinden TLS, kimlik doğrulama ve hız sınırı gerektirir.

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

<details>
<summary>Gelişmiş script seçeneklerini göster</summary>

| Seçenek                    | Ne işe yarar                                              |
| -------------------------- | --------------------------------------------------------- |
| `--lang tr\|en`            | Arayüz dili. Verilmezse başta sorulur                      |
| `--network mainnet\|testnet` | Hangi ağ kurulacak (varsayılan mainnet)                  |
| `--l1-rpc <url>`           | Ethereum L1 execution adresi, zorunlu                     |
| `--l1-beacon <url>`        | Ethereum L1 beacon adresi, zorunlu                        |
| `--dry-run`                | Node/Docker servisini kurmaz; ön kontrolleri çalıştırır   |
| `--expose-rpc yes`         | RPC'yi dışarı açar                                        |
| `--allowed-ip <ip>`        | Dışarı açarken sadece bu IP'ye izin verir                 |
| `--rpc-port <port>`        | HTTP portunu değiştirir (varsayılan 8547)                 |
| `--ws-port <port>`         | WebSocket portunu değiştirir (varsayılan 8548)            |
| `--data-dir <yol>`         | Veri ve config kökü (varsayılan `/root/rh`)               |
| `--snapshot-type <tür>`    | `pruned`, `full-path` veya `archive-path`; çok parçalıysa güvenli biçimde durur |
| `--forwarding-target <url>` | İşlemlerin iletileceği adres; varsayılan resmi sequencer endpoint'i. Sadece okuma: `null` |
| `--no-snapshot`            | Snapshot indirmez, sıfırdan senkronlar (çok uzun sürer)   |
| `--non-interactive`        | Soru sormaz                                               |
| `--uninstall`              | Servisi ve config'i kaldırır, veriye dokunmaz             |

</details>

---

## Tavsiyeler

- Önce `sudo ./script.sh --dry-run` çalıştırın. Bu komut node'u kurmadan sunucuyu ve adresleri kontrol eder.
- Yeterli boş alanı olan NVMe disk kullanın.
- RPC'yi tüm internete açmayın. Yukarıda anlatılan SSH tünelini kullanın.
- İlk senkron çok fazla istek gönderdiği için ücretsiz Ethereum adreslerinden kaçının.
- Testnet kuracaksanız Ethereum Mainnet yerine Sepolia execution ve beacon adresleri kullanın.

---

## Sorun Giderme

<details>
<summary>Sık karşılaşılan hataları ve çözümlerini aç</summary>

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
Execution sağlayıcınız geçmiş log sorgusuna izin vermiyor. Bu mesaj, mutlaka Ethereum archive-state
node'u gerektiği anlamına gelmez; sağlayıcınızın historical `eth_getLogs` vermesi gerekir. Mainnet
Rollup kontratının kurulduğu blok için şöyle test edebilirsiniz:

```bash
curl -s -X POST [L1_RPC_ADRESINIZ] -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_getLogs","params":[{"address":"0x23A19d23e89166adedbDcB432518AB01e4272D94","fromBlock":"0x17d61be","toBlock":"0x17d61be"}]}'
```

**"ForwardingTarget not set and not sequencer"**
Bu hatayı görmeniz gerekmiyor, script gerekli bayrağı kendisi ekliyor. Resmi dokümandaki komutta
bu bayrak yok ama node onsuz hiç açılmıyor, gerçek kurulumda ortaya çıktı. Elle kuruyorsanız
`--execution.forwarding-target=https://sequencer.mainnet.chain.robinhood.com` eklemeyi unutmayın.

**"no space left on device"**
Snapshot dosyası sıkıştırılmış halde yüzlerce GB'dir ve açılırken hem arşiv hem veritabanı aynı anda
diskte bulunur. `df -h` ile boş alanı kontrol edin. Nitro'nun tavsiye ettiği hesabı kullanın; yalnızca
snapshot indirme boyutuna bakmayın.

**"stream error: INTERNAL_ERROR" veya "attempt 1 failed: unexpected EOF"**
İki mesaj da uzun snapshot indirmesinde CDN bağlantısının kesildiğini gösterir. Nitro'nun kullandığı
indirici `Range` desteğiyle mevcut dosyanın sonundan devam eder; dosya büyümeye devam ediyorsa tek
başına bu satır veri kaybı anlamına gelmez. Script Nitro istemcisi için `GODEBUG=http2client=0`
ayarlayarak snapshot transferini HTTP/1.1 üzerinden yapar. Snapshot veritabanının dışındaki kalıcı
`snapshot-download` dizinine iner; servis yeniden başlarsa kaldığı byte'tan devam eder. Import
tamamlanıp RPC cevap verdiğinde yardımcı `robinhood-rpc-snapshot-cleanup` servisi indirilen arşivi
otomatik siler. İlerlemenin sürdüğünü dosya boyutuyla kontrol edebilirsiniz:

```bash
watch -n 10 'du -h /root/rh/robinhood-nitro-data/snapshot-download/'
```

**"found unexpected files in database directory, including: tmp"**
Önceki sürüm snapshot'ı Nitro veritabanının kendi `tmp` dizinine indiriyordu. İndirme sırasında servis
durdurulursa bu dizin sonraki başlangıcı engelliyordu. Güncel script ayrı ve yeniden kullanılabilir
`snapshot-download` dizini kullandığı için yeni kurulumlarda bu hata oluşmaz.

**Logda veri yolu `/home/user/.arbitrum/...` görünüyor**
Bu doğrudur. Robinhood rehberindeki Docker komutu `/home/nitro` gösterse de rehberin sabitlediği
`v3.11.2-3599aca` imajı gerçek kontrolde `uid=1000(user)` ve `HOME=/home/user` ile çalıştı;
`/home/nitro` dizini imajda yoktu. Script bu nedenle host veri dizinini `/home/user/.arbitrum`
yoluna bağlar ve UID 1000'e yazma izni verir. Önceki `/home/nitro` mount'unda veri host diske değil,
Docker'ın geçici katmanına gidiyor ve konteyner silinince kayboluyordu.

**Servis sürekli yeniden başlıyor**
```bash
journalctl -u robinhood-rpc -n 100 --no-pager
```
Genelde L1 bağlantısı ya da disk dolmasıdır.

</details>

---

Kaynak: [Robinhood Chain resmi dokümanı](https://docs.robinhood.com/chain/run-a-full-node/)

Hazırlayan: [@UfukDegen](https://x.com/UfukDegen)
