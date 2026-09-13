import AppKit
import Combine
import KapakSensoru
import QuartzCore

/// Dahili ekranın kimliği. `NSApplication` arka ışık değişiminde de ekran
/// bildirimi gönderir; bu yapı ikisini birbirinden ayırmaya yarar.
struct EkranDuzeni: Equatable {
    var ekranKimligi: CGDirectDisplayID?
    var cerceve: CGRect?
}

/// Kapak açısını izler ve derinlik efektini yönetir.
///
/// Bir sayaç sensörü yoklar; bir ekran bağlantısı da yayı ekran tazeleme
/// hızında ilerleterek okumalar arasındaki geçişi yumuşak tutar.
@MainActor
final class KapakDenetleyici: ObservableObject {

    @Published private(set) var anlikAci: Double = 0
    @Published private(set) var sensorVar = false
    @Published private(set) var efektCalisiyor = false

    let goruntuAlici = EkranGoruntusu()

    private let ayarlar: Ayarlar
    private let sensor = KapakAcisiSensoru()
    private let ortu = DerinlikOrtusu()
    private let akis = EkranAkisi()

    private var etkinAbonelik: AnyCancellable?
    private var goruntuGorevi: Task<Void, Never>?
    private var yoklamaSayaci: Timer?
    private var yoklamaAraligi: TimeInterval = 0
    private var ekranBaglantisi: CADisplayLink?
    private var sonKareZamani: CFTimeInterval = 0
    private var sonYayinZamani: CFTimeInterval = 0

    private var hamAci: Double = 0
    /// Saniyede derece; kapak kapanırken negatif.
    private var acisalHiz: Double = 0
    private var sonDegisenAci: Double?
    private var sonDegisimZamani: CFTimeInterval = 0
    private var sonKapanmaZamani: CFTimeInterval = -.greatestFiniteMagnitude
    private var gorselAci = SonumluYay()
    private var artArdaBasarisizOkuma = 0
    private var baslamaZamani: CFTimeInterval = 0
    private var onizleme: OnizlemeKosusu?
    private var askida = false
    private var yakalamaBekliyor = false
    private var sonAsagiHareketZamani: CFTimeInterval = -.greatestFiniteMagnitude
    /// Kapağın `zamanAsimiHareketEsigi`nden fazla son taşındığı yer ve zaman.
    /// Zaman aşımı oradan sayılır.
    private var zamanAsimiReferansAcisi: Double?
    private var zamanAsimiReferansZamani: CFTimeInterval = 0
    /// Zaman aşımı efekti bitirdiğinde kurulur, kapak eşiğin üstüne çıkınca
    /// temizlenir. Aynı yerden daha fazla kapanmak efekti yeniden tetiklememeli.
    private var zamanAsimiSerbestBekliyor = false
    /// Ayarın son görülen hâli; değiştirilince bayat izleme atılır.
    private var oncekiZamanAsimiEtkin = false
    /// `kapanisaBasla()` görüntüyü düzlüğe geri yumuşatırken doğru.
    private var kapanisSuruyor = false
    private var kapanisBaslangici: CFTimeInterval = 0
    private var dahiliDuzen = EkranDuzeni()

    private static let bostaYoklamaAraligi: TimeInterval = 1.0 / 8
    private static let etkinYoklamaAraligi: TimeInterval = 1.0 / 30
    private static let acilmaSuresi: TimeInterval = 0.07
    /// Ön ısıtma bölgesinin kaç derece üstünde yoklamanın hızlanacağı.
    private static let hizliYoklamaPayi: Double = 20

    /// Bilinçli bir kapatma sayılan kapanma hızı, saniyede derece. Duran bir
    /// kapak 0,5'in altını okur.
    private static let tetikKapanmaHizi: Double = 2

    /// Kapak son kez aşağı hareket ettikten sonra efektin başlayabileceği süre.
    private static let kapanmaHafizasi: TimeInterval = 1.5

    private static let tahminHizTabani: Double = 40

    /// Okumanın kendi yaşına eklenen sensör gecikmesi.
    private static let tahminGecikmesi: TimeInterval = 0.04

    /// Örtü en az bu kadar ekranda kalır. Son okuma hâlâ bırakma açısının
    /// üstündeyken bir tahmin tetiklenebilir.
    private static let enKisaEfektSuresi: TimeInterval = 0.35

    /// Bu kadar derecelik hareket "duruyor" sayılır.
    private static let zamanAsimiHareketEsigi: Double = 2

    /// Zaman aşımının efekti bitirmesi için kapağın ne kadar durması gerektiği.
    private static let zamanAsimiDurmaSuresi: TimeInterval = 2

    /// Yumuşatılmış açının düzlüğe ne kadar yaklaşması gerektiği. Yarım derece
    /// eksikte bile karartma eğrisi görüntünün üstünü yüzde birkaç karartır ve
    /// sönme altındaki daha parlak ekranı ele verir.
    private static let kapanisOturmaPayi: Double = 0.05

    /// Yay hiç oturmazsa diye güvenlik sınırı.
    private static let kapanisEnUzunSure: TimeInterval = 1.2

    /// Kapak hareket etmeden efekti göstermek için kullanılan betimlenmiş açı
    /// süpürmesi. Sensörle aynı yoldan beslenir.
    private struct OnizlemeKosusu {
        let baslangic: CFTimeInterval
        let acik: Double
        let kapali: Double
        let kapanma: CFTimeInterval = 1.4
        let bekleme: CFTimeInterval = 0.8
        let acilma: CFTimeInterval = 0.6

        /// Koşu bitince `nil`.
        func aci(_ simdi: CFTimeInterval) -> Double? {
            let gecen = simdi - baslangic
            if gecen < kapanma { return acik + (kapali - acik) * (gecen / kapanma) }
            if gecen < kapanma + bekleme { return kapali }
            if gecen < kapanma + bekleme + acilma {
                return kapali + (acik - kapali) * ((gecen - kapanma - bekleme) / acilma)
            }
            return nil
        }
    }

    init(ayarlar: Ayarlar) {
        self.ayarlar = ayarlar
        etkinAbonelik = ayarlar.$etkin
            .removeDuplicates()
            .sink { [weak self] etkin in
                guard !etkin else { return }
                self?.efektiKapat()
            }
    }

    // MARK: - Yaşam döngüsü

    func baslat() {
        sensorVar = sensor.kullanilabilir
        guard sensorVar else { return }

        if let aci = sensor.aci() {
            hamAci = aci
            anlikAci = aci
            gorselAci.sifirla(aci)
        }
        yoklamaAraligiAyarla(Self.bostaYoklamaAraligi)
        dahiliDuzen = EkranDuzeni(
            ekranKimligi: NSScreen.dahili?.ekranKimligi,
            cerceve: NSScreen.dahili?.frame
        )
        sistemOlaylariniIzle()
        ortu.onIsit()
        Task {
            await goruntuAlici.suzgeciIsit()
            // Örtü varlık penceresini kurduktan sonra, böylece süzgeç bu
            // uygulamayı adıyla dışarıda bırakabilir.
            try? await Task.sleep(nanoseconds: 500_000_000)
            await akis.suzgeciIsit()
        }
    }

    func durdur() {
        yoklamaSayaci?.invalidate()
        yoklamaSayaci = nil
        yoklamaAraligi = 0
        efektiVeYakalamayiDurdur()
    }

    private func efektiVeYakalamayiDurdur() {
        goruntuGorevi?.cancel()
        goruntuGorevi = nil
        yakalamaBekliyor = false
        kapanisSuruyor = false
        ekranBaglantisiniDurdur()
        ortu.kapat(animasyonlu: false)
        goruntuAlici.durdur()
        akis.durdur()
        ortu.canliBirak()
        onizleme = nil
        efektCalisiyor = false
    }

    private func efektiKapat() {
        efektiVeYakalamayiDurdur()
        sonDegisenAci = nil
        acisalHiz = 0
        sonKapanmaZamani = -.greatestFiniteMagnitude
        sonAsagiHareketZamani = -.greatestFiniteMagnitude
        if yoklamaSayaci != nil { yoklamaAraligiAyarla(Self.bostaYoklamaAraligi) }
    }

    /// Efekti o anki ekran içeriği üzerinde bir kez oynatır.
    func onizlemeOynat() {
        guard ayarlar.etkin, !askida, onizleme == nil, !efektCalisiyor else { return }
        // Tetik açısının epey üstünden başlar, böylece süpürme ön ısıtmayı
        // gerçek bir kapanmadaki gibi çalıştırır.
        onizleme = OnizlemeKosusu(
            baslangic: CACurrentMediaTime(),
            acik: min(ayarlar.esikAcisi + 35, 130),
            kapali: max(ayarlar.esikAcisi - ayarlar.bulaniklikAraligi * 1.15, 5)
        )
        yoklamaAraligiAyarla(Self.etkinYoklamaAraligi)
    }

    // MARK: - Yoklama

    private func yoklamaAraligiAyarla(_ aralik: TimeInterval) {
        guard yoklamaAraligi != aralik else { return }
        yoklamaAraligi = aralik
        yoklamaSayaci?.invalidate()
        let sayac = Timer(timeInterval: aralik, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.yokla() }
        }
        RunLoop.main.add(sayac, forMode: .common)
        yoklamaSayaci = sayac
    }

    private func yokla() {
        guard !askida else { return }

        let aci: Double
        if let kosu = onizleme {
            guard let betimlenen = kosu.aci(CACurrentMediaTime()) else {
                onizleme = nil
                return
            }
            aci = betimlenen
        } else {
            guard let okunan = sensor.aci() else {
                artArdaBasarisizOkuma += 1
                if artArdaBasarisizOkuma > 30, efektCalisiyor {
                    Gunluk.kapak.notice(
                        "bırakılıyor: sensör \(self.artArdaBasarisizOkuma) kez üst üste okunamadı"
                    )
                    calisiyorAyarla(false)
                }
                return
            }
            artArdaBasarisizOkuma = 0
            aci = okunan
        }

        hamAci = aci
        yayinla(aci: aci)

        if ayarlar.etkin {
            hiziGuncelle(aci: aci)
            uyumla(aci: aci)
        }

        let onIsitmaBolgesi = ayarlar.esikAcisi + ayarlar.onIsitmaTavani
        let hizliYoklamaIsteniyor = ayarlar.etkin
            && (onizleme != nil || efektCalisiyor || aci <= onIsitmaBolgesi + Self.hizliYoklamaPayi)
        yoklamaAraligiAyarla(hizliYoklamaIsteniyor ? Self.etkinYoklamaAraligi : Self.bostaYoklamaAraligi)
    }

    /// Bu açıda görüntünün ekranda olup olmaması gerektiği. Bırakma açısını
    /// genişletir ve eşiğin altında tutulan kapağı gösterir durumda bırakır —
    /// zaman aşımı önce bitirmezse.
    private func efektIsteniyor(aci: Double) -> Bool {
        guard ayarlar.etkin, NSScreen.dahili != nil else { return false }
        if ayarlar.zamanAsimiEtkin != oncekiZamanAsimiEtkin {
            zamanAsimiReferansAcisi = nil
            zamanAsimiSerbestBekliyor = false
            oncekiZamanAsimiEtkin = ayarlar.zamanAsimiEtkin
        }

        let esik = ayarlar.esikAcisi
        if efektCalisiyor {
            guard CACurrentMediaTime() - baslamaZamani > Self.enKisaEfektSuresi else { return true }
            if aci >= esik + ayarlar.histerezis { return false }
            if ayarlar.zamanAsimiEtkin, zamanAsiminiGecti(aci: aci) {
                zamanAsimiSerbestBekliyor = true
                return false
            }
            return true
        }

        if ayarlar.zamanAsimiEtkin, zamanAsimiSerbestBekliyor {
            guard aci >= esik else { return false }
            zamanAsimiSerbestBekliyor = false
        }

        // Eşiğin altında duran bir kapak kendiliğinden başlatmamalı.
        let kapaniyor = CACurrentMediaTime() - sonAsagiHareketZamani < Self.kapanmaHafizasi
        return kapaniyor && tahminiAci() <= esik
    }

    /// Açı, son anlamlı konumunun `zamanAsimiHareketEsigi` kadar yakınında
    /// `zamanAsimiDurmaSuresi` boyunca kaldıysa doğru.
    private func zamanAsiminiGecti(aci: Double) -> Bool {
        let simdi = CACurrentMediaTime()
        if let referans = zamanAsimiReferansAcisi,
           abs(aci - referans) <= Self.zamanAsimiHareketEsigi {
            return simdi - zamanAsimiReferansZamani >= Self.zamanAsimiDurmaSuresi
        }
        zamanAsimiReferansAcisi = aci
        zamanAsimiReferansZamani = simdi
        return false
    }

    /// Her örnekte ekranı `efektIsteniyor` ile hizalar. Ekran görüntüsü
    /// başarısız olan bir koşu burada yeniden denenir.
    private func uyumla(aci: Double) {
        guard ayarlar.etkin, !askida else { return }
        let istenen = efektIsteniyor(aci: aci)
        if istenen != efektCalisiyor {
            Gunluk.kapak.notice(
                """
                \(istenen ? "başla" : "bitir", privacy: .public) ham \(aci, format: .fixed(precision: 2)) \
                tahmin \(self.tahminiAci(), format: .fixed(precision: 2)) \
                hız \(self.acisalHiz, format: .fixed(precision: 1)) derece/sn
                """
            )
            calisiyorAyarla(istenen)
            return
        }
        if efektCalisiyor {
            if !ortu.gorunur, !yakalamaBekliyor { goruntuyuGoster() }
            // Bağlantısı olmayan görünür bir örtü ilk karesinde takılı kalır.
            if ortu.gorunur, ekranBaglantisi == nil { ekranBaglantisiniBaslat() }
        } else if !kapanisSuruyor {
            // Düzlüğe dönüş hâlâ canlı görüntüyü çiziyor; bu onu boşaltırdı.
            onIsitmayiGuncelle(aci: aci, tavan: ayarlar.esikAcisi + ayarlar.onIsitmaTavani)
        }
    }

    private func hiziGuncelle(aci: Double) {
        let simdi = CACurrentMediaTime()
        guard let son = sonDegisenAci else {
            sonDegisenAci = aci
            sonDegisimZamani = simdi
            return
        }
        if aci != son {
            let dt = simdi - sonDegisimZamani
            if dt > 0.001 {
                let anlik = (aci - son) / dt
                acisalHiz = 0.5 * anlik + 0.5 * acisalHiz
            }
            sonDegisenAci = aci
            sonDegisimZamani = simdi
        } else if simdi - sonDegisimZamani > 0.4 {
            acisalHiz = 0
        }
        if acisalHiz <= -Self.tetikKapanmaHizi {
            sonAsagiHareketZamani = simdi
        }
        if acisalHiz <= -ayarlar.kapanmaHizi {
            sonKapanmaZamani = simdi
        }
    }

    /// Yalnızca kapak kapanırken çalışır; kapağı sabit tutmak arkada bir
    /// yakalama döngüsü bırakmasın.
    private func onIsitmayiGuncelle(aci: Double, tavan: Double) {
        let yakinZamandaKapandi = CACurrentMediaTime() - sonKapanmaZamani < ayarlar.onIsitmaSarkmasi
        guard aci <= tavan, yakinZamandaKapandi else {
            goruntuAlici.onIsitmayiBitir()
            akis.durdur()
            ortu.canliBirak()
            return
        }
        guard ayarlar.canliGoruntu else {
            akis.durdur()
            ortu.canliBirak()
            goruntuAlici.onIsitmayiBaslat(aralik: ayarlar.onIsitmaAraligi)
            return
        }
        // Yalnızca akış. Aynı anda ScreenCaptureKit'ten ekran görüntüsü de
        // istemek ikisini birden yavaşlatır.
        goruntuAlici.onIsitmayiBitir()
        akis.baslat()
    }

    /// Bir okuma tam bir sensör tazelemesi kadar eski olabilir; bu yüzden hızlı
    /// kapanışta son okuma yerine kapağın gittiği yer kullanılır.
    private func tahminiAci() -> Double {
        guard acisalHiz < -Self.tahminHizTabani else { return hamAci }
        let bayatlik = min(CACurrentMediaTime() - sonDegisimZamani, 0.12)
        return hamAci + acisalHiz * (bayatlik + Self.tahminGecikmesi)
    }

    private func yayinla(aci: Double) {
        let simdi = CACurrentMediaTime()
        guard simdi - sonYayinZamani > 0.08 else { return }
        sonYayinZamani = simdi
        if abs(anlikAci - aci) > 0.001 { anlikAci = aci }
    }

    // MARK: - Derinlik efekti

    private func calisiyorAyarla(_ calisiyor: Bool) {
        efektCalisiyor = calisiyor
        if calisiyor {
            kapanisSuruyor = false
            baslamaZamani = CACurrentMediaTime()
            if ayarlar.zamanAsimiEtkin {
                zamanAsimiReferansAcisi = hamAci
                zamanAsimiReferansZamani = baslamaZamani
            }
            gorselAci.sifirla(hamAci)
            goruntuAlici.onIsitmayiBitir()
            yoklamaAraligiAyarla(Self.etkinYoklamaAraligi)
            goruntuyuGoster()
        } else {
            goruntuAlici.birak()
            zamanAsimiReferansAcisi = nil
            kapanisaBasla()
        }
    }

    /// Örtü sönmeden önce görüntüyü düzlüğe geri yumuşatır. Efekti kapak hâlâ
    /// kapalıyken bitirmek, çarpık bir görüntünün sönmesine yol açardı.
    /// Yumuşatmayı `adim(_:)` sürdürür ve `kapanisiBitir()`i çağırır.
    private func kapanisaBasla() {
        // Görüntü henüz yokken ya da çizecek bağlantı yokken yumuşatacak bir
        // şey de yok.
        guard ortu.gorunur, ekranBaglantisi != nil else {
            ekranBaglantisiniDurdur()
            ortu.kapat(animasyonlu: true)
            return
        }
        kapanisSuruyor = true
        kapanisBaslangici = CACurrentMediaTime()
    }

    private func kapanisiBitir() {
        kapanisSuruyor = false
        ekranBaglantisiniDurdur()
        ortu.kapat(animasyonlu: true)
    }

    /// Elde tutulan ekran görüntüsünü gösterir ya da birini bekler. Zaten süren
    /// bir ön ısıtma yakalaması o bekleme yerine geçer.
    private func goruntuyuGoster() {
        guard ayarlar.etkin, !askida, efektCalisiyor else { return }
        if ayarlar.canliGoruntu, let ekran = NSScreen.dahili,
           ortu.canliGoster(
               ekran: ekran,
               baslangicAcisi: ayarlar.esikAcisi,
               ayar: gecerliAyar,
               acilmaSuresi: Self.acilmaSuresi
           ) {
            ekranBaglantisiniBaslat()
            if let kare = akis.yeniKare() {
                ortu.kareyiAl(kare)
                return
            }
            // Hızlı bir kapanış, akış kare üretmeden eşiğe ulaşabilir. Tek bir
            // ekran görüntüsü görüntüyü başlatır.
            if let resim = goruntuAlici.sonResim {
                ortu.tohumla(resim: resim)
                return
            }
            tohumIste()
            return
        }

        if let resim = goruntuAlici.sonResim, let ekran = goruntuAlici.sonEkran {
            goster(resim: resim, ekran: ekran)
            return
        }
        yakalamaBekliyor = true
        goruntuGorevi?.cancel()
        goruntuGorevi = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.goruntuAlici.birKezYakala()
            guard !Task.isCancelled else { return }
            self.goruntuGorevi = nil
            self.yakalamaBekliyor = false
            guard self.efektCalisiyor, !self.ortu.gorunur,
                  let resim = self.goruntuAlici.sonResim,
                  let ekran = self.goruntuAlici.sonEkran else { return }
            self.goster(resim: resim, ekran: ekran)
        }
    }

    /// Gösterecek hiçbir şeyi olmayan canlı örtü için tek bir ekran görüntüsü
    /// alır. Önce gelen bir akış karesi bunu gereksiz kılar.
    private func tohumIste() {
        yakalamaBekliyor = true
        goruntuGorevi?.cancel()
        goruntuGorevi = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.goruntuAlici.birKezYakala()
            guard !Task.isCancelled else { return }
            self.goruntuGorevi = nil
            self.yakalamaBekliyor = false
            guard self.efektCalisiyor, !self.ortu.goruntuHazir,
                  let resim = self.goruntuAlici.sonResim else { return }
            self.ortu.tohumla(resim: resim)
        }
    }

    private func goster(resim: CGImage, ekran: NSScreen) {
        ortu.goster(
            resim: resim,
            ekran: ekran,
            baslangicAcisi: ayarlar.esikAcisi,
            ayar: gecerliAyar,
            acilmaSuresi: Self.acilmaSuresi
        )
        // Bağlantı örtü penceresine ait.
        ekranBaglantisiniBaslat()
    }

    private func bulaniklikIlerlemesi(aci: Double) -> Double {
        let aralik = max(ayarlar.bulaniklikAraligi, 1)
        return min(max((ayarlar.esikAcisi - aci) / aralik, 0), 1)
    }

    // MARK: - Animasyon

    private func ekranBaglantisiniBaslat() {
        ekranBaglantisiniDurdur()
        guard let pencere = ortu.tasiyiciPencere else { return }
        let baglanti = pencere.displayLink(target: self, selector: #selector(adim(_:)))
        baglanti.add(to: .main, forMode: .common)
        sonKareZamani = CACurrentMediaTime()
        ekranBaglantisi = baglanti
    }

    private func ekranBaglantisiniDurdur() {
        ekranBaglantisi?.invalidate()
        ekranBaglantisi = nil
    }

    @objc private func adim(_ baglanti: CADisplayLink) {
        let simdi = CACurrentMediaTime()
        let hamAralik = simdi - sonKareZamani
        let dt = min(max(hamAralik, 1.0 / 240), 1.0 / 20)
        sonKareZamani = simdi
        if let kare = akis.yeniKare() {
            ortu.kareyiAl(kare)
        }
        let hedef = kapanisSuruyor ? ayarlar.esikAcisi : hamAci
        gorselAci.ilerlet(hedef: hedef, dt: dt)

        guard kapanisSuruyor else {
            gorseliUygula(aci: gorselAci.deger)
            return
        }
        // Eşikte ya da üstünde görüntü zaten düz; eşiği geçip açılan bir kapak
        // için hemen biter.
        let oturdu = gorselAci.deger >= hedef - Self.kapanisOturmaPayi
        let sureDoldu = simdi - kapanisBaslangici > Self.kapanisEnUzunSure
        guard oturdu || sureDoldu else {
            gorseliUygula(aci: gorselAci.deger)
            return
        }
        // Sönen kare arkasındaki ekranla birebir eşleşmeli; bu yüzden eşiğin
        // biraz altında değil, tam üstünde bitirilir.
        gorselAci.sifirla(hedef)
        gorseliUygula(aci: hedef)
        kapanisiBitir()
    }

    /// Geometri kapak açısının kendisini alır; yalnızca bulanıklık doyuma gider.
    private func gorseliUygula(aci: Double) {
        ortu.guncelle(
            ilerleme: bulaniklikIlerlemesi(aci: aci),
            anlikAci: aci,
            ayar: gecerliAyar
        )
    }

    private var gecerliAyar: DerinlikAyari {
        DerinlikAyari(
            izlemeMesafesi: ayarlar.izlemeMesafesi,
            geriYatma: ayarlar.geriYatma,
            bulaniklikYayilimi: ayarlar.bulaniklikYayilimi,
            karartmaYayilimi: ayarlar.karartmaYayilimi,
            enFazlaBulaniklik: ayarlar.enFazlaBulaniklik,
            enFazlaKarartma: ayarlar.enFazlaKarartma
        )
    }

    // MARK: - Sistem olayları

    private func sistemOlaylariniIzle() {
        let calismaAlani = NSWorkspace.shared.notificationCenter
        calismaAlani.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.askiyaAl() }
        }
        calismaAlani.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.surdur() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // macOS bu bildirimi arka ışık ve renk değişimleri için de gönderir.
                let ekran = NSScreen.dahili
                let duzen = EkranDuzeni(ekranKimligi: ekran?.ekranKimligi, cerceve: ekran?.frame)
                guard duzen != self.dahiliDuzen else { return }
                Gunluk.kapak.notice("ekran düzeni değişti")
                self.dahiliDuzen = duzen
                if self.efektCalisiyor { self.calisiyorAyarla(false) }
                self.akis.durdur()
                self.akis.suzgeciGecersizKil()
                Task { await self.akis.suzgeciIsit() }
                self.ortu.canliBirak()
                self.goruntuAlici.birak()
                Task { await self.goruntuAlici.suzgeciIsit() }
            }
        }
    }

    private func askiyaAl() {
        Gunluk.kapak.notice("askıya alındı")
        askida = true
        efektiVeYakalamayiDurdur()
    }

    private func surdur() {
        Gunluk.kapak.notice("sürdürülüyor")
        askida = false
        // Taze bir başlangıç: neredeyse kapalı bir kapakla uyanmak kapanma
        // hareketi gibi okunmasın.
        sonDegisenAci = nil
        acisalHiz = 0
        sonKapanmaZamani = -.greatestFiniteMagnitude
        sonAsagiHareketZamani = -.greatestFiniteMagnitude
        zamanAsimiReferansAcisi = nil
        zamanAsimiSerbestBekliyor = false
        oncekiZamanAsimiEtkin = false
        kapanisSuruyor = false
        if let aci = sensor.aci() {
            hamAci = aci
            gorselAci.sifirla(aci)
        }
        yoklamaAraligiAyarla(Self.bostaYoklamaAraligi)
    }
}
