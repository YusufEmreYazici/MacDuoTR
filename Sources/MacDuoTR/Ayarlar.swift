import Combine
import Foundation

/// Kullanıcı ayarları. `UserDefaults` üzerinde saklanır; bütün veriler bu
/// Mac'te, bu kullanıcının alanında kalır, hiçbir yere gönderilmez.
@MainActor
final class Ayarlar: ObservableObject {
    static let ortak = Ayarlar()

    private enum Anahtar {
        static let etkin = "etkin"
        static let zamanAsimiEtkin = "zamanAsimiEtkin"
        static let esikAcisi = "esikAcisi"
        static let bulaniklikAraligi = "bulaniklikAraligi"
        static let enFazlaBulaniklik = "enFazlaBulaniklik"
        static let enFazlaKarartma = "enFazlaKarartma"
        static let izlemeMesafesi = "izlemeMesafesi"
        static let geriYatma = "geriYatma"
        static let bulaniklikYayilimi = "bulaniklikYayilimi"
        static let karartmaYayilimi = "karartmaYayilimi"
        static let menudeAciGoster = "menudeAciGoster"
        static let canliGoruntu = "canliGoruntu"

        // Klavye kilidi (temizlik modu)
        static let medyaTuslariniDaKilitle = "medyaTuslariniDaKilitle"

        static let tumu = [
            etkin, zamanAsimiEtkin, esikAcisi, bulaniklikAraligi, enFazlaBulaniklik,
            enFazlaKarartma, izlemeMesafesi, geriYatma, bulaniklikYayilimi,
            karartmaYayilimi, menudeAciGoster, canliGoruntu, medyaTuslariniDaKilitle,
        ]
    }

    private static let fabrika: [String: Any] = [
        Anahtar.etkin: true,
        Anahtar.zamanAsimiEtkin: false,
        Anahtar.esikAcisi: 90.0,
        Anahtar.bulaniklikAraligi: 60.0,
        Anahtar.enFazlaBulaniklik: 135.0,
        Anahtar.enFazlaKarartma: 1.0,
        Anahtar.izlemeMesafesi: 6.0,
        Anahtar.geriYatma: 1.0,
        Anahtar.bulaniklikYayilimi: 0.0,
        Anahtar.karartmaYayilimi: 0.5,
        Anahtar.menudeAciGoster: false,
        Anahtar.canliGoruntu: true,
        Anahtar.medyaTuslariniDaKilitle: false,
    ]

    /// Derinlik efektinin ana anahtarı.
    @Published var etkin: Bool {
        didSet { varsayilanlar.set(etkin, forKey: Anahtar.etkin) }
    }

    /// Kapak eşiğin altında sabit kaldığında efekti erken bitirir; yoksa
    /// kapağın eşiğin üstüne geri açılması beklenir.
    @Published var zamanAsimiEtkin: Bool {
        didSet { varsayilanlar.set(zamanAsimiEtkin, forKey: Anahtar.zamanAsimiEtkin) }
    }

    /// Bu açının altına kapanınca efekt başlar. Derece.
    @Published var esikAcisi: Double {
        didSet { varsayilanlar.set(esikAcisi, forKey: Anahtar.esikAcisi) }
    }

    /// Eşiğin kaç derece altında bulanıklığın tepeye ulaşacağı.
    @Published var bulaniklikAraligi: Double {
        didSet { varsayilanlar.set(bulaniklikAraligi, forKey: Anahtar.bulaniklikAraligi) }
    }

    /// Tam efektteki Gauss bulanıklık yarıçapı, punto cinsinden.
    @Published var enFazlaBulaniklik: Double {
        didSet { varsayilanlar.set(enFazlaBulaniklik, forKey: Anahtar.enFazlaBulaniklik) }
    }

    /// Bulanıklığın tepe yaptığı yerdeki siyah örtünün matlığı, 0...1.
    @Published var enFazlaKarartma: Double {
        didSet { varsayilanlar.set(enFazlaKarartma, forKey: Anahtar.enFazlaKarartma) }
    }

    /// Gözün ekran ortasına uzaklığı; ekran yüksekliğinin katı olarak.
    @Published var izlemeMesafesi: Double {
        didSet { varsayilanlar.set(izlemeMesafesi, forKey: Anahtar.izlemeMesafesi) }
    }

    /// Kapak her bir derece kapandığında görüntünün camdan kaç derece
    /// uzaklaşacağı. 1 değeri görüntüyü odada sabit tutar.
    @Published var geriYatma: Double {
        didSet { varsayilanlar.set(geriYatma, forKey: Anahtar.geriYatma) }
    }

    /// Menteşe kenarındaki bulanıklığın, karşı kenardakine oranı. 1 tüm
    /// görüntüyü eşit bulanıklaştırır.
    @Published var bulaniklikYayilimi: Double {
        didSet { varsayilanlar.set(bulaniklikYayilimi, forKey: Anahtar.bulaniklikYayilimi) }
    }

    /// Karartmanın tam güce ulaştığı yükseklik; ekran yüksekliğinin oranı.
    @Published var karartmaYayilimi: Double {
        didSet { varsayilanlar.set(karartmaYayilimi, forKey: Anahtar.karartmaYayilimi) }
    }

    /// Menü çubuğu simgesinin yanına anlık açıyı yazar.
    @Published var menudeAciGoster: Bool {
        didSet { varsayilanlar.set(menudeAciGoster, forKey: Anahtar.menudeAciGoster) }
    }

    /// Efektin altındaki görüntüyü canlı tutar; kapalıyken eşik anındaki tek
    /// kare dondurulur.
    @Published var canliGoruntu: Bool {
        didSet { varsayilanlar.set(canliGoruntu, forKey: Anahtar.canliGoruntu) }
    }

    // MARK: - Klavye kilidi

    /// Ses, parlaklık ve oynatma tuşlarını da engelle.
    @Published var medyaTuslariniDaKilitle: Bool {
        didSet { varsayilanlar.set(medyaTuslariniDaKilitle, forKey: Anahtar.medyaTuslariniDaKilitle) }
    }

    // MARK: - Perspektif kaydırıcısının uçları

    /// Göz mesafesinin perspektif kaydırıcısındaki iki ucu. Panel gücü sunar,
    /// güç ise mesafenin tersi yönde artar.
    static let enUzakGoz: Double = 6
    static let enYakinGoz: Double = 1
    static let gozAraligi: Double = enUzakGoz - enYakinGoz

    /// Ön ısıtmanın çalışabileceği, eşiğin üstündeki en yüksek açı farkı.
    let onIsitmaTavani: Double = 70

    /// Ön ısıtmayı başlatan kapanma hızı, saniyede derece.
    let kapanmaHizi: Double = 8

    /// Kapak durduktan sonra ön ısıtmanın ne kadar süreceği.
    let onIsitmaSarkmasi: TimeInterval = 2

    /// Ön ısıtma ekran görüntüleri arasındaki süre.
    let onIsitmaAraligi: TimeInterval = 0.25

    /// Örtünün bırakılması için eşiğin kaç derece üstüne çıkılması gerektiği.
    let histerezis: Double = 4

    /// Önceki sürümlerden kalan, açılışta silinen ayarlar. Kilit artık süreli
    /// değil ve panel her zaman gösteriliyor.
    private static let emekli = ["kilitSuresi", "kilitPaneliGoster"]

    private let varsayilanlar = UserDefaults.standard

    // Bilerek satır içi değer yok: Swift, bir özelliği ilk kez atayan
    // atamada özellik gözlemcilerini çalıştırmaz.
    private init() {
        let varsayilanlar = UserDefaults.standard
        varsayilanlar.register(defaults: Self.fabrika)
        for anahtar in Self.emekli { varsayilanlar.removeObject(forKey: anahtar) }
        etkin = varsayilanlar.bool(forKey: Anahtar.etkin)
        zamanAsimiEtkin = varsayilanlar.bool(forKey: Anahtar.zamanAsimiEtkin)
        esikAcisi = varsayilanlar.double(forKey: Anahtar.esikAcisi)
        bulaniklikAraligi = varsayilanlar.double(forKey: Anahtar.bulaniklikAraligi)
        enFazlaBulaniklik = varsayilanlar.double(forKey: Anahtar.enFazlaBulaniklik)
        enFazlaKarartma = varsayilanlar.double(forKey: Anahtar.enFazlaKarartma)
        izlemeMesafesi = varsayilanlar.double(forKey: Anahtar.izlemeMesafesi)
        geriYatma = varsayilanlar.double(forKey: Anahtar.geriYatma)
        bulaniklikYayilimi = varsayilanlar.double(forKey: Anahtar.bulaniklikYayilimi)
        karartmaYayilimi = varsayilanlar.double(forKey: Anahtar.karartmaYayilimi)
        menudeAciGoster = varsayilanlar.bool(forKey: Anahtar.menudeAciGoster)
        canliGoruntu = varsayilanlar.bool(forKey: Anahtar.canliGoruntu)
        medyaTuslariniDaKilitle = varsayilanlar.bool(forKey: Anahtar.medyaTuslariniDaKilitle)
    }

    func varsayilanlaraDon() {
        for anahtar in Anahtar.tumu {
            varsayilanlar.removeObject(forKey: anahtar)
        }
        etkin = varsayilanlar.bool(forKey: Anahtar.etkin)
        zamanAsimiEtkin = varsayilanlar.bool(forKey: Anahtar.zamanAsimiEtkin)
        esikAcisi = varsayilanlar.double(forKey: Anahtar.esikAcisi)
        bulaniklikAraligi = varsayilanlar.double(forKey: Anahtar.bulaniklikAraligi)
        enFazlaBulaniklik = varsayilanlar.double(forKey: Anahtar.enFazlaBulaniklik)
        enFazlaKarartma = varsayilanlar.double(forKey: Anahtar.enFazlaKarartma)
        izlemeMesafesi = varsayilanlar.double(forKey: Anahtar.izlemeMesafesi)
        geriYatma = varsayilanlar.double(forKey: Anahtar.geriYatma)
        bulaniklikYayilimi = varsayilanlar.double(forKey: Anahtar.bulaniklikYayilimi)
        karartmaYayilimi = varsayilanlar.double(forKey: Anahtar.karartmaYayilimi)
        menudeAciGoster = varsayilanlar.bool(forKey: Anahtar.menudeAciGoster)
        canliGoruntu = varsayilanlar.bool(forKey: Anahtar.canliGoruntu)
        medyaTuslariniDaKilitle = varsayilanlar.bool(forKey: Anahtar.medyaTuslariniDaKilitle)
    }
}
