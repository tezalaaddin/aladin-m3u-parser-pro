# Kodun tüm mantığını baştan sona, örneklerle yazıyorum.

---

# AladinM3UParserService — Teknik Dokümantasyon (V4.0)

## 0. Genel Amaç

Bu servis, bir M3U playlist dosyasındaki her içerik kaydını satır satır okuyup yapılandırılmış bir veri modeline dönüştürür. Çıktı olarak her kayıt için şu alanlar üretilir:

- **aladinRawName** — ham, hiç dokunulmamış isim
- **aladinTitle** — UI ve Excel için temizlenmiş başlık
- **aladinRating** — IMDb puanı (varsa)
- **aladinYear** — yapım yılı (varsa)
- **aladinQuality** — kalite etiketi (varsa)
- **aladinGroup** — kategori/grup adı
- **aladinLogo** — poster/logo URL'si
- **aladinUrl** — stream linki
- **aladinType** — içerik tipi: `tv`, `movie`, `series`
- **aladinSeason / aladinEpisode** — sezon/bölüm veya yayın tarihi
- **aladinSeriesTitle** — dizi adı (series tipinde)
- **aladinHeaders** — stream açmak için gereken HTTP başlıkları (varsa)
- **aladinContainer** — stream format uzantısı (mkv, mp4, m3u8 vb.)
- **aladinKey** — tekil tanımlayıcı (duplicate tespiti için)
- Debug alanları: `aladinTypeReason`, `aladinGroupRaw`, `aladinLineIndex` vb.

---

## 1. Neden Arka Planda (Isolate) Çalışır?

M3U dosyaları onlarca hatta yüz binlerce kayıt içerebilir. Parse işlemi ana uygulama thread'inde yapılsaydı kullanıcı arayüzü parse tamamlanana kadar tamamen donardı. Bu sorunu çözmek için servis, Dart'ın `compute()` mekanizmasını kullanır.

`compute()` çağrısı, parse fonksiyonunu ayrı bir **isolate** içinde çalıştırır. Isolate, ana thread ile bellek paylaşmayan bağımsız bir yürütme birimidir. Parse işlemi orada yürürken kullanıcı arayüzü kesintisiz çalışmaya devam eder. İşlem bittiğinde sonuç ana thread'e aktarılır.

---

## 2. Dosyayı Satırlara Bölme

Gelen M3U içeriği önce satırlara ayrılır. Parser her satırı sırayla gezer ve yalnızca `#EXTINF:` ile başlayan satırları bir kaydın başlangıcı olarak kabul eder. Diğer satırlar URL, opsiyon veya yorum satırı olarak değerlendirilir.

Standart bir M3U kaydı şu yapıdadır:

```
#EXTINF:-1 tvg-id="" tvg-name="TVP | Matrix Reloaded (2003) [IMDb: 7.1]" tvg-logo="https://..." group-title="TR/FILM ► TV PLUS",TVP | Matrix Reloaded (2003) [IMDb: 7.1]
http://eu.zortv1.com:8080/movie/yyy/xxx/595814.mkv
```

---

## 3. URL Tarama ve Header Toplama

`#EXTINF:` satırı bulunduktan sonra parser bir sonraki satıra geçer ve URL'yi arar. Ancak bazı listelerde URL hemen gelmez; araya `#EXTVLCOPT:` opsiyon satırları girebilir:

```
#EXTINF:-1 ... ,2M Monde (360p)
#EXTVLCOPT:http-referrer=http://www.radio2m.ma/
#EXTVLCOPT:http-user-agent=Mozilla/5.0 ...
https://cdn-globecast.akamaized.net/...
```

Bu durumda parser şu adımları izler: `#EXTVLCOPT:` satırlarından `user-agent` ve `referrer` değerlerini bir header haritasına toplar, ardından `http` ile başlayan ilk satırı URL olarak kabul eder. Eğer yeni bir `#EXTINF:` satırına ulaşılırsa mevcut kayıt için URL bulunamadığı sonucuna varılır ve o kayıt atlanır.

Header bilgisi ayrıca `#EXTINF:` satırının kendi içinden de okunabilir:

```
#EXTINF:-1 http-user-agent="Mozilla/5.0" http-referrer="http://..." ...
```

Her iki kaynaktan gelen header'lar birleştirilir.

---

## 4. İsim Kaynakları ve aladinRawName

M3U formatında bir kaydın ismi iki ayrı yerde bulunabilir.

**Birinci kaynak — tvg-name attribute:**
```
tvg-name="TVP | Matrix Reloaded (2003) [IMDb: 7.1]"
```

**İkinci kaynak — virgülden sonrası (display name):**
```
...,TVP | Matrix Reloaded (2003) [IMDb: 7.1]
```

Bu iki kaynak bazı listelerde birebir aynıdır. Bazı listelerde ise `tvg-name` IMDb ve yıl gibi zengin metadata içerirken virgülden sonrası yalnızca sade isim içerir.

**aladinRawName kuralı:** `tvg-name` doluysa ham isim olarak o kullanılır. `tvg-name` boşsa virgülden sonraki display name kullanılır. Ham isim **hiçbir koşulda temizlenmez veya değiştirilmez.**

**Display name okuma güvenliği:** Virgülden sonrasını almak için `lastIndexOf(',')` kullanılır. Sebebi şudur: `group-title` değeri kendi içinde virgül barındırabilir ve bu durumda yanlış parça alınabilir. En son virgülden sonrasını almak bu riski ortadan kaldırır.

---

## 5. metaSource: Metadata Arama Metni

IMDb, yıl ve kalite bilgilerini aramak için hem `tvg-name` hem de display name birleştirilir. Bu birleşik metne `metaSource` denir.

**Neden gerekli?**

Bazı listelerde metadata yalnızca `tvg-name` içindedir, bazılarında yalnızca display name'de, bazılarında her ikisinde de vardır. Tek bir kaynağa bakılsaydı metadata kaçabilirdi. Her iki kaynak birleştirilerek bu sorun giderilir.

Örnek:
- `tvg-name` → `"Ölümlü Dünya 2 [IMDb: 6.1]"`
- display name → `"Ölümlü Dünya 2 [IMDb: 6.1]"`
- metaSource → `"Ölümlü Dünya 2 [IMDb: 6.1] Ölümlü Dünya 2 [IMDb: 6.1]"`

Regex arama bu birleşik metin üzerinde yapılır.

---

## 6. Ayraç Satırlarını Eleme

Bazı listeler gerçek içerik olmayan dekoratif ayraç satırları içerir:

```
**** ULUSAL KANALLAR UHD ****
#### SİNEMA ####
```

Bu satırlar `#EXTINF:` ile tanımlandıklarından parser onları da işlemeye çalışır. Ancak isimleri belirli kalıplara uyduğu için ayraç olarak tespit edilir ve atlanır. Tespit kriterleri: ismin `####` veya `****` içermesi ya da yalnızca `# * - _ =` gibi özel karakterlerden oluşmasıdır.

---

## 7. Logo ve Grup

`tvg-logo` attribute'undan poster veya logo URL'si okunur. `group-title` attribute'undan kategori adı okunur. Kategori adındaki fazladan boşluklar temizlenir. Eğer `group-title` yoksa ya da boşsa kategori `Genel` olarak atanır.

Örnek:
- `tvg-logo` → `https://image.tmdb.org/.../poster.jpg`
- `group-title` → `TR/FILM ► TV PLUS`

---

## 8. İçerik Tipi Tespiti (tv / movie / series)

İçerik tipi tespiti sırasıyla şu kurallara göre yapılır:

### 8.1 Series (Dizi)

Aşağıdaki koşullardan herhangi biri sağlanıyorsa içerik `series` olarak işaretlenir:

**Kural A — URL içinde `/series/` geçiyor:**
```
http://panel.xyz:8080/series/kullanici/sifre/12345.m3u8
```

**Kural B — İsimde SxxExx pattern'ı var:**
```
Börü 2039 S01 E05
Breaking Bad S03E07
```

**Kural C — İsim DIZI ile başlıyor (catch-up kayıtları):**
```
DIZI CUMA : Arka Sokaklar (10.04.2026)
```

### 8.2 Movie (VOD)

Aşağıdaki koşullardan herhangi biri sağlanıyorsa içerik `movie` olarak işaretlenir (series koşulu sağlanmamışsa):

**Kural A — URL içinde `/movie/` geçiyor:**
```
http://eu.zortv1.com:8080/movie/xxxx47/yyyy56/595814.mkv
```

**Kural B — URL bilinen bir video uzantısıyla bitiyor:**
Kabul edilen uzantılar: `mkv`, `mp4`, `avi`, `mov`, `wmv`, `flv`, `mpg`, `mpeg`, `m4v`

### 8.3 TV

Yukarıdaki iki kategoriye girmeyen her kayıt `tv` olarak işaretlenir. Film oynatan lineer TV kanalları da bu kategoriye girer çünkü stream URL'leri `/movie/` içermez ve video uzantısıyla bitmez.

---

## 9. DIZI Özel Format (Tarih Tabanlı)

Bazı paneller dizi bölümlerini bölüm numarası yerine yayın tarihiyle gönderir:

```
DIZI CUMA : Arka Sokaklar (10.04.2026)
DIZI CUMARTESI : Gönül Dağı (11.04.2026)
DIZI PAZAR : Teskilat (12.04.2026)
```

Bu format tespit edildiğinde şu ayrıştırma yapılır:

1. Başındaki `DIZI GUN :` bloğu soyulur.
2. `dd.MM.yyyy` formatındaki tarih bulunur.
3. Tarihten yıl bilgisi çıkarılır.
4. Kalan metin dizi adı olarak alınır.

Sonuç:
- `aladinType` → `series`
- `aladinSeriesTitle` → `Arka Sokaklar`
- `aladinSeason` → `2026`
- `aladinEpisode` → `10.04.2026`

---

## 10. IMDb Puanı (aladinRating)

`metaSource` üzerinde IMDb araması yapılır. Kabul edilen formatlar:

- `[IMDb: 6.7]`
- `IMDb: 6.7`
- `IMDB 6,7`
- `IMDb-8.5`

Yakalama kuralları:
- Virgülle yazılmışsa (`6,7`) noktaya çevrilir → `6.7`
- Değer `0`, `0.0` veya `0,0` ise alan boş bırakılır
- Kayıtta IMDb metni yoksa alan boş bırakılır, asla varsayılan değer atanmaz

Örnek:
```
TVP | Matrix Reloaded (2003) [IMDb: 7.1]
→ aladinRating: 7.1

The Matrix Resurrections
→ aladinRating: (boş)
```

---

## 11. Yıl (aladinYear)

`metaSource` üzerinde yıl araması yapılır. Yalnızca parantez, köşeli parantez veya süslü parantez içindeki 4 haneli yıllar kabul edilir:

- `(2003)` → geçerli
- `[2003]` → geçerli
- `{2003}` → geçerli
- `Blade Runner 2049` → **geçersiz** (parantez yok)
- `Börü 2039` → **geçersiz** (parantez yok)

Bu kural bilinçli bir tasarım tercihidir. Parantez zorunluluğu, filmin ya da dizinin adının bir parçası olan sayıların yanlışlıkla yıl olarak algılanmasını engeller.

Birden fazla yıl ifadesi varsa en sondaki alınır.

---

## 12. Kalite (aladinQuality)

`metaSource` üzerinde kalite etiketi araması yapılır. Tanınan etiketler:

`SD`, `HD`, `HD+`, `720P`, `FHD`, `1080P`, `UHD`, `4K`, `HEVC`, `50FPS`, `60FPS`

Birden fazla etiket bulunursa hepsi toplanır ve belirli bir sıraya göre birleştirilir. Sıralama: HEVC → 4K → UHD → FHD → 1080P → HD+ → HD → 720P → SD → 60FPS → 50FPS

Örnek:
```
TR | TRT 1 HD      → aladinQuality: HD
TR | TRT 1 FHD     → aladinQuality: FHD
TR | TRT 2 HD+     → aladinQuality: HD+
(kalite etiketi yok) → aladinQuality: (boş)
```

Kalite bilgisi yoksa alan boş bırakılır. Asla varsayılan değer (`SD` gibi) atanmaz.

---

## 13. Temiz Başlık (aladinTitle)

`aladinTitle`, kullanıcı arayüzünde arama ve listeleme için ham isimden üretilen temizlenmiş başlıktır. Aşağıdaki işlemler sırayla uygulanır:

**Adım 1 — IMDb metni silinir:**
```
TVP | Matrix Reloaded (2003) [IMDb: 7.1]
→ TVP | Matrix Reloaded (2003) []
```

**Adım 2 — Yıl parantezi silinir:**
```
TVP | Matrix Reloaded (2003) []
→ TVP | Matrix Reloaded  []
```

**Adım 3 — Kalite etiketleri silinir:**
(Bu örnekte kalite etiketi yok; varsa silinirdi.)

**Adım 4 — Platform suffix'leri silinir:**
Sona yapışmış platform ve kaynak kısaltmaları temizlenir:
```
The Friend (2025) AMZN  →  The Friend
War Machine (2026) NF   →  War Machine
Hayalet Filler DSNP     →  Hayalet Filler
Chuck'ın Hayatı TVP     →  Chuck'ın Hayatı
Bir Film YERLI          →  Bir Film
```
Tanınan suffix'ler: `NF`, `AMZN`, `DSNP`, `TVP`, `YERLI`, `HBO`, `MAX`, `APLUS`, `PRMR`, `APPLE`, `MUBI`, `GAIN`, `BLUTV`, `EXXEN`, `DISNEY`

**Adım 5 — Nokta ve alt çizgi boşluğa çevrilir:**
```
Breaking.Bad.S03E07  →  Breaking Bad S03E07
```

**Adım 6 — Başlıktaki prefix kalıpları silinir:**
`TR |`, `TVP |`, `BlueTV`, `### `, `► ` gibi önek kalıpları temizlenir:
```
TR | TRT 1 HD    →  TRT 1 HD  (kalite sonraki adımda silinir)
TVP | Matrix...  →  Matrix...
```

**Adım 7 — Kalan parantez blokları silinir:**
IMDb ve yıl temizlendikten sonra geriye kalan boş veya doldu parantez, köşeli, süslü bloklar silinir:
```
Ölümlü Dünya 2 (Komedi)  →  Ölümlü Dünya 2
```

**Adım 8 — `#` karakteri silinir.**

**Adım 9 — Çoklu boşluklar tek boşluğa indirilir, baştaki ve sondaki boşluklar temizlenir.**

DIZI formatındaki kayıtlarda `aladinTitle` bu pipeline'dan geçmez; doğrudan `aladinSeriesTitle` değerine eşitlenir.

---

## 14. Key (aladinKey)

Her kayıt için tekil bir anahtar üretilir. Amaçları:

- Duplicate (tekrarlı kayıt) tespiti
- Aynı içeriğin farklı kalite varyantlarını gruplama
- Excel'de filtreleme ve birleştirme

Key yapısı: `tip|url|diziAdı|sezon|bölüm`

Örnek:
```
movie|http://eu.zortv1.com:8080/movie/xxxx47/yyyy56/595814.mkv|||
series|http://.../271506.mkv|Arka Sokaklar|2026|10.04.2026
```

---

## 15. Container Tespiti (aladinContainer)

URL'nin uzantısından stream formatı tespit edilir. Bu bilgi player'ın codec ve demuxer seçimi için kullanılabilir.

Tanınan formatlar: `m3u8`, `mpd`, `mkv`, `mp4`, `avi`, `mov`, `wmv`, `flv`, `mpg`, `mpeg`, `m4v`

URL'de sorgu parametresi (`?token=...` gibi) varsa uzantı tespitinden önce soyulur. Uzantı bulunamazsa alan boş bırakılır.

---

## 16. Tüm Akışın Özet Diyagramı

```
M3U dosyası
    │
    ▼
compute() → Isolate başlatılır (UI thread serbest kalır)
    │
    ▼
Satır satır gezilir
    │
    ├─ #EXTINF: değilse → atla
    │
    ▼
URL taranır (#EXTVLCOPT header'ları toplanır)
    │
    ├─ URL yoksa veya http değilse → atla
    │
    ▼
tvg-name, display name, logo, group okunur
    │
    ▼
rawNameOriginal belirlenir (tvg-name > displayName)
metaSource oluşturulur (tvg-name + displayName)
    │
    ├─ Ayraç satırı mı? → atla
    │
    ▼
Type tespiti (series > movie > tv)
    │
    ▼
IMDb / Yıl / Kalite → metaSource üzerinden yakalanır
    │
    ▼
aladinTitle → rawName üzerinden temizlenir
(IMDb → Yıl → Kalite → Suffix → Prefix → Parantez → boşluk)
    │
    ▼
Key üretilir
    │
    ▼
AladinIPTVItem nesnesi oluşturulur
    │
    ▼
Liste döndürülür → UI / Excel export'a aktarılır
```