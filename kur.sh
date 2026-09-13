#!/usr/bin/env bash
#
# MacDuoTR — kaynaktan kur.
#
#   ./kur.sh            derle, /Applications altına kur ve başlat
#   ./kur.sh --paket    dağıtılabilir bir .zip üret (build/ altına)
#
# Hazır uygulamayı indirmek isteyenlerin bu betiğe ihtiyacı yok:
# https://github.com/YusufEmreYazici/MacDuoTR/releases

set -euo pipefail
cd "$(dirname "$0")"

UYGULAMA="MacDuoTR"
PAKET="build/${UYGULAMA}.app"
KIMLIK_ADI="MacDuoTR Yerel Imza"

YESIL=$'\033[32m'; SARI=$'\033[33m'; KIRMIZI=$'\033[31m'
KALIN=$'\033[1m'; SOLUK=$'\033[2m'; SIFIR=$'\033[0m'
tamam() { printf '  %s✓%s %s\n' "$YESIL" "$SIFIR" "$1"; }
bilgi() { printf '  %s·%s %s\n' "$SOLUK" "$SIFIR" "$1"; }
uyari() { printf '  %s!%s %s\n' "$SARI" "$SIFIR" "$1"; }
hata()  { printf '  %s✗%s %s\n' "$KIRMIZI" "$SIFIR" "$1" >&2; }
baslik(){ printf '\n%s%s%s\n' "$KALIN" "$1" "$SIFIR"; }

# Kendinden imzalı, kalıcı bir kod imzalama kimliği üretir. macOS sertifikaya
# güvenmek için bir kez parola sorar; parola doğrudan macOS'un penceresine
# girilir, bu betik onu hiç görmez.
sertifika_kur() {
  local gecici; gecici="$(mktemp -d)"
  trap 'rm -rf "$gecici"' RETURN

  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$gecici/anahtar.pem" -out "$gecici/sertifika.pem" \
    -subj "/CN=$KIMLIK_ADI" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1 || return 1

  openssl pkcs12 -export -legacy -out "$gecici/paket.p12" \
    -inkey "$gecici/anahtar.pem" -in "$gecici/sertifika.pem" -passout pass: >/dev/null 2>&1 \
    || openssl pkcs12 -export -out "$gecici/paket.p12" \
         -inkey "$gecici/anahtar.pem" -in "$gecici/sertifika.pem" -passout pass: >/dev/null 2>&1 \
    || return 1

  local anahtarlik="$HOME/Library/Keychains/login.keychain-db"
  security import "$gecici/paket.p12" -k "$anahtarlik" -P "" -T /usr/bin/codesign -A >/dev/null 2>&1 || return 1

  printf "\n  macOS şimdi parolanızı soracak — sertifikaya güvenmek için.\n\n"
  security add-trusted-cert -r trustRoot -p codeSign -k "$anahtarlik" "$gecici/sertifika.pem" || return 1
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$anahtarlik" >/dev/null 2>&1 || true

  security find-identity -v -p codesigning | grep -q "$KIMLIK_ADI" || return 1
  tamam "Kalıcı imza kimliği kuruldu."
}

SADECE_PAKET=false
for arg in "$@"; do
  case "$arg" in
    --paket|--package) SADECE_PAKET=true ;;
    *) hata "Bilinmeyen argüman: $arg"; exit 1 ;;
  esac
done

printf '\n%s%s%s  kaynaktan kurulum\n' "$KALIN" "$UYGULAMA" "$SIFIR"

# --- Ortam ------------------------------------------------------------------
baslik "Ortam"
SURUM="$(sw_vers -productVersion)"
if (( ${SURUM%%.*} < 14 )); then
  hata "macOS 14 veya üstü gerekiyor (bu makinede $SURUM)."
  exit 1
fi
tamam "macOS $SURUM"

if ! command -v swift >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
  hata "Xcode gerekiyor. App Store'dan kurun, sonra Xcode'u bir kez açın."
  exit 1
fi
tamam "Swift $(swift --version 2>&1 | grep -oE 'Swift version [0-9.]+' | head -1 | awk '{print $3}')"

# --- İmza kimliği -----------------------------------------------------------
# Ad-hoc imzada uygulamanın kimliği her derlemede değişir ve macOS, Ekran Kaydı
# ile Erişilebilirlik izinlerini her seferinde sıfırlar. Sabit bir kimlik bunu
# bitirir: TCC kaydı cdhash yerine sertifikaya bağlanır.
baslik "İmza"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID"; then
  IMZA="$(security find-identity -v -p codesigning | grep "Developer ID" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
  tamam "Developer ID: $IMZA"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$KIMLIK_ADI"; then
  IMZA="$KIMLIK_ADI"
  tamam "Kalıcı yerel imza — izinler yeniden derlemelerde korunur."
else
  IMZA="-"
  uyari "Kalıcı imza kimliği yok; ad-hoc imzayla derlenecek."
  bilgi "Bu durumda macOS izinleri her yeniden derlemede sıfırlar."
  if [ -t 0 ] && ! "$SADECE_PAKET"; then
    echo
    read -r -p "  Kalıcı bir yerel sertifika kurulsun mu? (macOS bir kez parola sorar) [E/h] " CEVAP
    if [[ "${CEVAP:-E}" =~ ^[EeYy]$ ]] && sertifika_kur; then
      IMZA="$KIMLIK_ADI"
    fi
  fi
fi

# --- Derle ------------------------------------------------------------------
baslik "Derleme"
swift build -c release --product MacDuoTR
swift build -c release --product sensorkontrol
BIN="$(swift build -c release --show-bin-path)"
tamam "Derlendi"

rm -rf "$PAKET"
mkdir -p "$PAKET/Contents/MacOS" "$PAKET/Contents/Resources"
cp "$BIN/MacDuoTR" "$PAKET/Contents/MacOS/MacDuoTR"
# SwiftPM, Bundle.module'ü uygulama paketine göre çözer.
cp -R "$BIN/MacDuoTR_MacDuoTR.bundle" "$PAKET/Contents/Resources/"
cp Kaynaklar/Info.plist "$PAKET/Contents/Info.plist"
cp LICENSE NOTICE "$PAKET/Contents/Resources/"
[ -f Kaynaklar/AppIcon.icns ] && cp Kaynaklar/AppIcon.icns "$PAKET/Contents/Resources/"
cp "$BIN/sensorkontrol" build/sensorkontrol

codesign --force --options runtime --timestamp=none --sign "$IMZA" "$PAKET"
codesign --verify --strict "$PAKET"
tamam "İmzalandı ($IMZA)"

if "$SADECE_PAKET"; then
  SURUM_NO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Kaynaklar/Info.plist)"
  ZIP="build/${UYGULAMA}-${SURUM_NO}.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$PAKET" "$ZIP"
  tamam "Paket: $ZIP"
  printf '\n'
  exit 0
fi

# --- Kur --------------------------------------------------------------------
baslik "Kurulum"
pkill -x MacDuoTR 2>/dev/null || true
sleep 0.5
# Eski derlemelerden kalan TCC kayıtları yeni cdhash ile eşleşmez; macOS o
# durumda izni her açılışta sorar ama kaydetmez. Kaydı silmek döngüyü kırar.
PAKET_KIMLIGI="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Kaynaklar/Info.plist)"
if [ "$IMZA" = "-" ]; then
  tccutil reset ScreenCapture "$PAKET_KIMLIGI" >/dev/null 2>&1 || true
  tccutil reset Accessibility "$PAKET_KIMLIGI" >/dev/null 2>&1 || true
fi
rm -rf "/Applications/${UYGULAMA}.app"
ditto "$PAKET" "/Applications/${UYGULAMA}.app"
codesign --verify --strict "/Applications/${UYGULAMA}.app"
tamam "/Applications/${UYGULAMA}.app"

open "/Applications/${UYGULAMA}.app"
tamam "Başlatıldı — menü çubuğunda dizüstü bilgisayar simgesi."

cat <<SON

  Uygulamayı menü çubuğundan açın. İzin gerektiğinde panel size söyler ve
  Sistem Ayarları'nı kendi açar:

    Ekran ve Ses Kaydı  → derinlik efekti
    Erişilebilirlik     → klavye kilidi

SON
