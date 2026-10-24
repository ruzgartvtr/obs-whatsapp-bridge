# OBS WhatsApp Bridge (macOS)

WhatsApp görüntülü aramalarda **OBS sahnenizi kamera**, **OBS sesinizi mikrofon** olarak kullanın.

OBS’in kendi sanal kamerası yalnızca görüntü taşır. Bu proje sesi de WhatsApp’a bağlar ve WhatsApp’ın sanal kamerayı engellemesini gevşetir.

## Tek komutla kurulum

Terminal’i açın (Uygulamalar → Yardımcı Programlar → Terminal) ve yapıştırın:

```bash
curl -fsSL https://raw.githubusercontent.com/ruzgartvtr/obs-whatsapp-bridge/main/install.sh | bash
```

Kurulum şunları yapar:

1. **BlackHole 2ch** sanal mikrofonunu kurar (yoksa Homebrew ile)
2. OBS script’ini `~/Library/Application Support/obs-studio/scripts/` altına kopyalar
3. WhatsApp’ta OBS sanal kamerasının görünmesi için gerekli imza ayarını uygular (şifre sorar)

## OBS’te 2 dakika

1. OBS’i açın (açıksa kapatıp yeniden açın)
2. **Tools → Scripts → +** → şu dosyayı seçin:

   `~/Library/Application Support/obs-studio/scripts/whatsapp-bridge.lua`

3. Script panelinde **Ses köprüsünü aç**
4. OBS’te **Start Virtual Camera**

## WhatsApp’ta

1. WhatsApp’ı tamamen kapatıp açın (Force Quit)
2. Görüntülü arama başlatın
3. Kamera / mikrofon seçimi:

| Rol | Seçim |
|-----|--------|
| Kamera | **OBS Virtual Camera** |
| Mikrofon | **BlackHole 2ch** |

Karşı taraf OBS önizlemenizi görür; sahne sesiniz (müzik, tarayıcı, masaüstü sesi vb.) mikrofon üzerinden gider.

## Gereksinimler

- macOS 13 veya üzeri
- [OBS Studio](https://obsproject.com/)
- [WhatsApp Desktop](https://www.whatsapp.com/download) (Mac)
- İnternet (kurulum sırasında Homebrew / paketler için)

## Sorun giderme

**Kamerada “OBS Virtual Camera” yok**  
Kurulumdaki WhatsApp adımı atlandıysa veya WhatsApp güncellendiyse tekrar çalıştırın:

```bash
curl -fsSL https://raw.githubusercontent.com/ruzgartvtr/obs-whatsapp-bridge/main/scripts/enable-whatsapp.sh | bash
```

**Ses gelmiyor**  
- Scripts’te köprü açık mı?  
- WhatsApp mikrofonu **BlackHole 2ch** mi?  
- BlackHole yeni kurulduysa Mac’i bir kez yeniden başlatın  
- Sistem Ayarları → Gizlilik ve Güvenlik → Mikrofon → WhatsApp açık olsun  

**WhatsApp giriş bozuldu / sürekli yeniden başlıyor**  
WhatsApp’ı App Store’dan yeniden yükleyin, sonra `enable-whatsapp.sh` script’ini bir kez daha çalıştırın.

**Alternatif kamera (NDI)**  
Bazı Mac’lerde NDI Virtual Input daha stabil olabilir: [NDI Tools](https://ndi.video/) + OBS NDI eklentisi. Ses için yine BlackHole + bu script kullanılır.

## Elle kurulum (curl istemiyorsanız)

```bash
git clone https://github.com/ruzgartvtr/obs-whatsapp-bridge.git
cd obs-whatsapp-bridge
./install.sh
```

## Geliştiriciler

Native OBS eklentisi (C++/ObjC++) ve isteğe bağlı `OBS Bridge Mic` Audio Server Plugin kaynakları `src/` ve `mac/` altındadır. Derleme: `./scripts/build-macos.sh` (`OBS_PATH` gerekir). Normal kullanıcıların buna ihtiyacı yoktur; `install.sh` + Lua script yeterlidir.

## Lisans

MIT — [LICENSE](LICENSE)
