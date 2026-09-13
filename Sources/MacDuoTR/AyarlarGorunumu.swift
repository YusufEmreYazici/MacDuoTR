import AppKit
import ServiceManagement
import SwiftUI

struct AyarlarGorunumu: View {
    @ObservedObject var ayarlar: Ayarlar
    @ObservedObject var denetleyici: KapakDenetleyici
    @ObservedObject var kilit: KlavyeKilidi
    @ObservedObject var izinler: IzinDurumu

    /// Boş değer sistem dilini izlemek demek.
    @AppStorage("arayuzDili") private var dilKodu = ""

    private var dil: Dil { Dil(rawValue: dilKodu) ?? .tercihEdilen }
    private func yazi(_ anahtar: String) -> String { dil.yazi(anahtar) }

    @State private var giristeBaslar = SMAppService.mainApp.status == .enabled
    @State private var ayarlarAcilamadi = false
    @State private var kilitBasarisiz = false

    /// Kilidi açıp kapatır. Menü çubuğu denetleyicisi yürütür.
    var kilidiDegistir: () -> KlavyeKilidi.Sonuc
    var cikis: () -> Void

    private static let genislik: CGFloat = 320
    private static let ickenar: CGFloat = 14
    private static let govdeYuksekligi: CGFloat = 430
    private static let ekranKaydiAyarlariURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            baslik
                .padding(.horizontal, Self.ickenar)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    klavyeKilidiBolumu
                    Divider()
                    if izinler.yenidenBaslatmakGerekiyor { yenidenBaslatUyarisi }
                    if denetleyici.sensorVar {
                        anahtarlar
                        if !izinler.ekranKaydi { ekranIzniUyarisi }
                        baslangicGrubu
                        gorunumGrubu
                        perspektifGrubu
                    } else {
                        Text(yazi("genel.sensorYok"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Self.ickenar)
                .padding(.vertical, 10)
            }
            .frame(height: Self.govdeYuksekligi)
            Divider()
            uygulamaGrubu
                .padding(.horizontal, Self.ickenar)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .frame(width: Self.genislik)
        .onAppear { izinler.tazele() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            izinler.tazele()
        }
    }

    // MARK: - Başlık

    private var baslik: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "MacDuoTR").font(.title2.weight(.semibold))
            Spacer()
            if denetleyici.sensorVar {
                Text(String(format: "%.1f°", denetleyici.anlikAci))
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(yazi("genel.kapakAcisi"))
            }
        }
    }

    // MARK: - Klavye kilidi

    private var klavyeKilidiBolumu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(yazi("grup.klavyeKilidi"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                kilitBasarisiz = false
                let sonuc = kilidiDegistir()
                switch sonuc {
                case .tamam:
                    break
                case .izinYok:
                    izinler.tazele()
                    KlavyeKilidi.erisimIzniIste()
                case .basarisiz:
                    kilitBasarisiz = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: kilit.kilitli ? "lock.open.fill" : "keyboard.badge.eye")
                    Text(kilit.kilitli ? yazi("kilit.durdur") : yazi("kilit.baslat"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(kilit.kilitli ? .orange : .accentColor)
            .controlSize(.large)

            Text(kilit.kilitli ? yazi("kilit.durum.aciklama") : yazi("kilit.aciklama"))
                .font(.caption2)
                .foregroundStyle(kilit.kilitli ? .secondary : .tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if !izinler.erisilebilirlik {
                erisimIzniUyarisi
            }
            if kilitBasarisiz {
                Text(yazi("kilit.basarisiz"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            anahtarSatiri(
                yazi("kilit.medyaTuslari"),
                secim: $ayarlar.medyaTuslariniDaKilitle,
                ipucu: yazi("kilit.medyaTuslari.aciklama")
            )
            .disabled(kilit.kilitli)

            Text(yazi("kilit.uyari"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var erisimIzniUyarisi: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(yazi("kilit.izinGerekli"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(yazi("kilit.izinAc")) {
                    KlavyeKilidi.erisimAyarlariniAc()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Derinlik efekti

    private var anahtarlar: some View {
        VStack(alignment: .leading, spacing: 4) {
            anahtarSatiri(
                yazi("anahtar.derinlikEfekti"),
                secim: $ayarlar.etkin,
                ipucu: yazi("anahtar.derinlikEfekti.aciklama")
            )
            anahtarSatiri(
                yazi("anahtar.canliGoruntu"),
                secim: $ayarlar.canliGoruntu,
                ipucu: yazi("anahtar.canliGoruntu.aciklama")
            )
            .disabled(!ayarlar.etkin)
            HStack {
                Spacer()
                Button(yazi("genel.onizle")) { denetleyici.onizlemeOynat() }
                    .controlSize(.small)
                    .disabled(!ayarlar.etkin)
            }
        }
    }

    private var baslangicGrubu: some View {
        grup(yazi("grup.baslangic")) {
            anahtarSatiri(
                yazi("ayar.zamanAsimi"),
                secim: $ayarlar.zamanAsimiEtkin,
                ipucu: yazi("ayar.zamanAsimi.aciklama")
            )
            kaydirici(
                yazi("ayar.baslangicAcisi"), deger: $ayarlar.esikAcisi, aralik: 5...130, bicim: "%.0f°",
                ipucu: yazi("ayar.baslangicAcisi.aciklama")
            )
            kaydirici(
                yazi("ayar.tamEfekt"), deger: $ayarlar.bulaniklikAraligi, aralik: 5...60, bicim: "%.0f°",
                ipucu: yazi("ayar.tamEfekt.aciklama")
            )
        }
    }

    private var gorunumGrubu: some View {
        grup(yazi("grup.gorunum")) {
            kaydirici(
                yazi("ayar.bulaniklik"), deger: $ayarlar.enFazlaBulaniklik, aralik: 10...160, bicim: "%.0f pt",
                ipucu: yazi("ayar.bulaniklik.aciklama")
            )
            kaydirici(
                yazi("ayar.bulaniklikYayilimi"), deger: $ayarlar.bulaniklikYayilimi, aralik: 0...1,
                bicim: "%.0f%%", olcek: 100,
                ipucu: yazi("ayar.bulaniklikYayilimi.aciklama")
            )
            kaydirici(
                yazi("ayar.karartma"), deger: $ayarlar.enFazlaKarartma, aralik: 0...1,
                bicim: "%.0f%%", olcek: 100,
                ipucu: yazi("ayar.karartma.aciklama")
            )
            kaydirici(
                yazi("ayar.karartmaYayilimi"), deger: $ayarlar.karartmaYayilimi, aralik: 0.2...1,
                bicim: "%.0f%%", olcek: 100,
                ipucu: yazi("ayar.karartmaYayilimi.aciklama")
            )
        }
    }

    private var perspektifGrubu: some View {
        grup(yazi("grup.perspektif")) {
            kaydirici(
                yazi("ayar.geriYatma"), deger: $ayarlar.geriYatma, aralik: 0...3, bicim: "%.1f×",
                ipucu: yazi("ayar.geriYatma.aciklama")
            )
            kaydirici(
                yazi("ayar.perspektif"), deger: perspektif, aralik: 0...1, bicim: "%.0f%%", olcek: 100,
                ipucu: yazi("ayar.perspektif.aciklama")
            )
        }
    }

    /// Ekran kaydı izni süreç başladıktan sonra verildiğinde çıkar. macOS bir
    /// süreci bir kez reddettiyse o süreç ömrü boyunca reddedilmiş kalır.
    private var yenidenBaslatUyarisi: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(yazi("izin.yenidenBaslatGerekli"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(yazi("izin.yenidenBaslat")) { izinler.yenidenBaslat() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var ekranIzniUyarisi: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(yazi("izin.ekranKaydi"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(yazi("izin.sistemAyarlariniAc")) { ekranKaydiAyarlariniAc() }
                    .controlSize(.small)
            }
            if ayarlarAcilamadi {
                Text(yazi("izin.acilamadi"))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Uygulama

    private var uygulamaGrubu: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(yazi("uygulama.dil"))
                Spacer()
                Picker("", selection: $dilKodu) {
                    Text(yazi("uygulama.dil.sistem")).tag("")
                    ForEach(Dil.allCases, id: \.rawValue) { secenek in
                        Text(secenek.gorunenAd).tag(secenek.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(yazi("uygulama.dil"))
            }
            anahtarSatiri(yazi("uygulama.menudeAci"), secim: $ayarlar.menudeAciGoster, ipucu: nil)
                .disabled(!denetleyici.sensorVar)
            anahtarSatiri(yazi("uygulama.giristeBaslat"), secim: $giristeBaslar, ipucu: nil)
                .onChange(of: giristeBaslar) { _, yeni in
                    giristeBaslatmayiAyarla(yeni)
                }
            HStack {
                Button(yazi("uygulama.sifirla")) { ayarlar.varsayilanlaraDon() }
                Spacer()
                Button(yazi("uygulama.cik"), action: cikis)
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
    }

    // MARK: - Küçük parçalar

    private func anahtarSatiri(_ baslik: String, secim: Binding<Bool>, ipucu: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(baslik)
                Spacer()
                Toggle("", isOn: secim)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel(baslik)
            }
            aciklama(ipucu)
        }
    }

    @ViewBuilder
    private func aciklama(_ metin: String?) -> some View {
        if let metin {
            Text(metin)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var perspektif: Binding<Double> {
        Binding(
            get: { (Ayarlar.enUzakGoz - ayarlar.izlemeMesafesi) / Ayarlar.gozAraligi },
            set: { ayarlar.izlemeMesafesi = Ayarlar.enUzakGoz - $0 * Ayarlar.gozAraligi }
        )
    }

    private func ekranKaydiAyarlariniAc() {
        ayarlarAcilamadi = false
        Task { @MainActor in
            do {
                let yapilandirma = NSWorkspace.OpenConfiguration()
                yapilandirma.activates = true
                _ = try await NSWorkspace.shared.open(Self.ekranKaydiAyarlariURL, configuration: yapilandirma)
            } catch {
                ayarlarAcilamadi = true
            }
        }
    }

    private func grup<Icerik: View>(
        _ baslik: String,
        @ViewBuilder icerik: () -> Icerik
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(baslik)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            icerik()
        }
        .disabled(!ayarlar.etkin)
    }

    private func kaydirici(
        _ baslik: String,
        deger: Binding<Double>,
        aralik: ClosedRange<Double>,
        bicim: String,
        olcek: Double = 1,
        ipucu: String? = nil
    ) -> some View {
        let okuma = String(format: bicim, deger.wrappedValue * olcek)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(baslik)
                Spacer()
                Text(okuma)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: deger, in: aralik)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(baslik)
                .accessibilityValue(okuma)
            aciklama(ipucu)
        }
    }

    private func giristeBaslatmayiAyarla(_ etkin: Bool) {
        do {
            if etkin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            giristeBaslar = SMAppService.mainApp.status == .enabled
        }
    }
}
