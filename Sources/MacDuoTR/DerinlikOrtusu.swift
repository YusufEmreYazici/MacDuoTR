import AppKit
import Metal
import QuartzCore

/// Menü çubuğu ve tam ekran alanları dâhil her şeyin üstünde duran çerçevesiz
/// pencere. Hiçbir zaman odak almaz, tıklamaları da yutmaz.
final class OrtuPenceresi: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Görüntünün cam üzerinde nereye düştüğü.
///
/// Görüntü, ekranın alt kenarına menteşelenmiş bir yaprak gibi düşünülür ve
/// kapağın kat ettiği açı kadar dünya uzayında geriye yatırılır. Göz yerinde
/// durur, cam onun altında döner; bu yüzden izdüşüm hem o anki kapak açısını
/// hem de göz konumunu kullanır.
struct DerinlikGeometrisi {

    /// 90 dereceden sonra görüntü yüzünü camdan tamamen çevirir.
    var enFazlaAyrilmaDerecesi: Double = 88

    /// Sol alt, sağ alt, sağ üst, sol üst.
    func koseler(
        baslangicAcisi: Double,
        anlikAci: Double,
        izlemeMesafesiOrani: Double,
        geriYatma: Double,
        ekranBoyutu: CGSize
    ) -> [CGPoint] {
        let genislik = Double(ekranBoyutu.width)
        let yukseklik = Double(ekranBoyutu.height)
        let baslangic = baslangicAcisi * .pi / 180
        let anlik = anlikAci * .pi / 180
        let yol = max(baslangicAcisi - anlikAci, 0)
        let ayrilma = min(geriYatma * yol, enFazlaAyrilmaDerecesi) * .pi / 180

        // Göz, menteşe başlangıç noktasında olacak şekilde dünya eksenlerinde.
        let uzanim = yukseklik * izlemeMesafesiOrani + yukseklik / 2 * cos(baslangic)
        let yukselme = yukseklik / 2 * sin(baslangic)

        // Aynı göz, cam boyunca ve camdan uzağa ölçülmüş hâliyle.
        let boyunca = uzanim * cos(anlik) + yukselme * sin(anlik)
        let derinlik = max(uzanim * sin(anlik) - yukselme * cos(anlik), yukseklik / 10)

        let yari = genislik / 2
        func yansit(_ x: Double, _ y: Double) -> CGPoint {
            let olcek = derinlik / (derinlik + y * sin(ayrilma))
            return CGPoint(
                x: yari + (x - yari) * olcek,
                y: boyunca + (y * cos(ayrilma) - boyunca) * olcek
            )
        }
        return [yansit(0, 0), yansit(genislik, 0), yansit(genislik, yukseklik), yansit(0, yukseklik)]
    }
}

/// Tek bir karenin görünümünü belirleyen ayarlar.
struct DerinlikAyari {
    var izlemeMesafesi: Double = 2.7
    var geriYatma: Double = 2
    var bulaniklikYayilimi: Double = 0.4
    var karartmaYayilimi: Double = 0.7
    var enFazlaBulaniklik: Double = 55
    var enFazlaKarartma: Double = 0.4
}

private final class MetalTasiyiciGorunum: NSView {
    init(katman metalKatmani: CALayer, olcek: CGFloat) {
        super.init(frame: .zero)
        metalKatmani.contentsScale = olcek
        self.layer = metalKatmani
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) kullanılmıyor")
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}

/// Efektin bir çalışması boyunca örtü penceresinin sahibi.
@MainActor
final class DerinlikOrtusu {

    private var pencere: OrtuPenceresi?
    /// Sönerken duran önceki çalışmanın penceresi. AppKit onu sönmenin
    /// ötesinde de canlı tuttuğu için yeni çalışma kendisi indirmeli.
    private var sonenPencere: OrtuPenceresi?
    private var varlikPenceresi: OrtuPenceresi?
    /// Bir kez kurulur ve saklanır.
    private var cizici: DerinlikCizici?
    private var ciziciDenendi = false
    private var kurulumJetonu = 0
    private let kurulumKuyrugu = DispatchQueue(label: "MacDuoTR.goruntuYukleme", qos: .userInteractive)

    private var ekranBoyutu: CGSize = .zero
    private var baslangicAcisi: Double = 90
    private var geometri = DerinlikGeometrisi()
    private var egri = BulaniklikEgrisi()
    private var ayar = DerinlikAyari()
    private var acilmaSuresi: TimeInterval = 0.07
    private var gosterildi = false

    var gorunur: Bool { pencere != nil }
    var goruntuHazir: Bool { cizici?.hazir ?? false }
    var tasiyiciPencere: NSWindow? { pencere }

    @discardableResult
    func onIsit() -> Bool {
        if !ciziciDenendi {
            ciziciDenendi = true
            cizici = DerinlikCizici()
        }
        varligiKoru()
        return cizici != nil
    }

    /// Bir punto genişliğinde, hiçbir şey göstermeyen pencere.
    ///
    /// ScreenCaptureKit yalnızca penceresi olan uygulamaları listeler; akışın
    /// örtüyü kendi görüntüsünden çıkarabilmesi için bu uygulamayı adıyla
    /// dışarıda bırakması gerekir.
    private func varligiKoru() {
        guard varlikPenceresi == nil else { return }
        let pencere = OrtuPenceresi(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        pencere.isOpaque = false
        pencere.backgroundColor = .clear
        pencere.hasShadow = false
        pencere.ignoresMouseEvents = true
        pencere.isReleasedWhenClosed = false
        pencere.level = .normal
        pencere.alphaValue = 0.004
        pencere.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        pencere.orderFrontRegardless()
        varlikPenceresi = pencere
    }

    /// Canlı akış için pencere açar. İlk kare alınana kadar saydam kalır.
    @discardableResult
    func canliGoster(
        ekran: NSScreen,
        baslangicAcisi: Double,
        ayar: DerinlikAyari,
        acilmaSuresi: TimeInterval
    ) -> Bool {
        kapat(animasyonlu: false)
        guard let ekranID = ekran.ekranKimligi, ekranID == NSScreen.dahili?.ekranKimligi else { return false }
        guard onIsit(), let cizici else { return false }
        self.baslangicAcisi = baslangicAcisi
        self.ayar = ayar
        self.acilmaSuresi = acilmaSuresi
        ekranBoyutu = ekran.frame.size

        let pikselOlcegi = Double(ekran.backingScaleFactor)
        guard cizici.canliBaslat(ekranBoyutu: ekranBoyutu, pikselOlcegi: CGFloat(pikselOlcegi)) else { return false }
        kurulumJetonu += 1
        pencereUret(ekran: ekran, pikselOlcegi: pikselOlcegi)
        return pencere != nil
    }

    /// Tek bir canlı kareyi çiziciye verir ve ilki geldiğinde pencereyi açar.
    func kareyiAl(_ kare: YakalananKare) {
        guard pencere != nil, let cizici else { return }
        cizici.kareyiAl(kare)
        acigaCikar()
    }

    /// Canlı örtüyü dondurulmuş tek kareyle başlatır.
    func tohumla(resim: CGImage) {
        guard pencere != nil, let cizici, cizici.tohumla(resim: resim) else { return }
        acigaCikar()
    }

    func canliBirak() {
        cizici?.canliBirak()
    }

    func goster(
        resim: CGImage,
        ekran: NSScreen,
        baslangicAcisi: Double,
        ayar: DerinlikAyari,
        acilmaSuresi: TimeInterval
    ) {
        kapat(animasyonlu: false)
        guard let ekranID = ekran.ekranKimligi, ekranID == NSScreen.dahili?.ekranKimligi else { return }
        guard onIsit(), let cizici else { return }
        self.baslangicAcisi = baslangicAcisi
        self.ayar = ayar
        self.acilmaSuresi = acilmaSuresi
        ekranBoyutu = ekran.frame.size

        let pikselOlcegi = ekran.frame.width > 0
            ? Double(resim.width) / Double(ekran.frame.width)
            : Double(ekran.backingScaleFactor)

        pencereUret(ekran: ekran, pikselOlcegi: pikselOlcegi)
        guard let pencere else { return }

        kurulumJetonu += 1
        let jeton = kurulumJetonu
        let boyut = ekranBoyutu
        kurulumKuyrugu.async { [weak self, weak cizici] in
            guard let cizici else { return }
            let goruntu = cizici.goruntuHazirla(
                resim: resim,
                ekranBoyutu: boyut,
                pikselOlcegi: CGFloat(pikselOlcegi)
            )
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.kurulumJetonu == jeton, self.pencere === pencere,
                          let goruntu else { return }
                    cizici.devral(goruntu)
                    self.guncelle(ilerleme: 0, anlikAci: self.baslangicAcisi, ayar: self.ayar)
                    self.acigaCikar()
                }
            }
        }
    }

    private func pencereUret(ekran: NSScreen, pikselOlcegi: Double) {
        guard let cizici else { return }
        let gorunum = MetalTasiyiciGorunum(katman: cizici.katmanUret(), olcek: CGFloat(pikselOlcegi))
        gorunum.frame = NSRect(origin: .zero, size: ekranBoyutu)
        gorunum.autoresizingMask = [.width, .height]

        let pencere = OrtuPenceresi(
            contentRect: ekran.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        pencere.contentView = gorunum
        pencere.isOpaque = false
        pencere.backgroundColor = .clear
        pencere.hasShadow = false
        pencere.ignoresMouseEvents = true
        pencere.isReleasedWhenClosed = false
        pencere.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        pencere.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        pencere.setFrame(ekran.frame, display: false)
        pencere.alphaValue = 0
        pencere.orderFrontRegardless()
        gosterildi = false
        self.pencere = pencere
    }

    /// Pencereyi yalnızca bir kez ve yalnızca çizilecek bir şey olduğunda açar.
    private func acigaCikar() {
        guard let pencere, !gosterildi, cizici?.hazir == true else { return }
        gosterildi = true
        NSAnimationContext.runAnimationGroup { baglam in
            baglam.duration = acilmaSuresi
            baglam.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pencere.animator().alphaValue = 1
        }
    }

    func guncelle(ilerleme: Double, anlikAci: Double, ayar: DerinlikAyari) {
        guard let cizici, cizici.hazir else { return }
        self.ayar = ayar
        cizici.ciz(
            koseler: geometri.koseler(
                baslangicAcisi: baslangicAcisi,
                anlikAci: anlikAci,
                izlemeMesafesiOrani: ayar.izlemeMesafesi,
                geriYatma: ayar.geriYatma,
                ekranBoyutu: ekranBoyutu
            ),
            bulaniklikGucu: egri.bulaniklikGucu(ilerleme: ilerleme),
            karartmaGucu: egri.karartmaGucu(ilerleme: ilerleme),
            bulaniklikTabani: ayar.bulaniklikYayilimi,
            karartmaTabani: egri.karartmaTabani,
            karartmaErimi: ayar.karartmaYayilimi,
            enFazlaBulaniklik: ayar.enFazlaBulaniklik,
            enFazlaKarartma: ayar.enFazlaKarartma
        )
    }

    func kapat(animasyonlu: Bool, sure: TimeInterval = 0.22) {
        sonenPencereyiKapat()
        guard let pencere else { return }
        self.pencere = nil
        kurulumJetonu += 1
        cizici?.birak()

        guard animasyonlu else {
            pencere.orderOut(nil)
            pencere.close()
            return
        }

        sonenPencere = pencere
        NSAnimationContext.runAnimationGroup { baglam in
            baglam.duration = sure
            baglam.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pencere.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.sonenPencere === pencere { self.sonenPencere = nil }
                pencere.orderOut(nil)
                pencere.close()
            }
        }
    }

    /// Hâlâ sönmekte olan pencereyi indirir.
    private func sonenPencereyiKapat() {
        guard let sonenPencere else { return }
        self.sonenPencere = nil
        sonenPencere.orderOut(nil)
        sonenPencere.close()
    }
}
