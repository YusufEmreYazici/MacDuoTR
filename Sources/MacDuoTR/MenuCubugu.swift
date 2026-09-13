import AppKit
import Combine
import SwiftUI

/// Menü çubuğu ögesi, ayarlar balonu ve klavye kilidinin düzenlenmesi.
@MainActor
final class MenuCubugu: NSObject, NSPopoverDelegate {

    private let ogeMenuCubugunda: NSStatusItem
    private let balon = NSPopover()
    private let ayarlar: Ayarlar
    private let denetleyici: KapakDenetleyici
    private let kilit: KlavyeKilidi
    private let kilitPaneli = KilitPaneli()
    private let izinler = IzinDurumu()

    private var baslikSayaci: Timer?
    private var cubukPenceresiTasindi: NSObjectProtocol?
    private var abonelikler = Set<AnyCancellable>()

    init(denetleyici: KapakDenetleyici, ayarlar: Ayarlar, kilit: KlavyeKilidi) {
        self.denetleyici = denetleyici
        self.ayarlar = ayarlar
        self.kilit = kilit
        ogeMenuCubugunda = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let dugme = ogeMenuCubugunda.button {
            dugme.imagePosition = .imageLeading
            dugme.target = self
            dugme.action = #selector(balonuDegistir(_:))
        }
        simgeyiTazele()

        balon.behavior = .transient
        balon.animates = true
        balon.delegate = self

        let barindiran = NSHostingController(
            rootView: AyarlarGorunumu(
                ayarlar: ayarlar,
                denetleyici: denetleyici,
                kilit: kilit,
                izinler: izinler,
                kilidiDegistir: { [weak self] in self?.kilidiDegistir() ?? .basarisiz },
                cikis: { NSApp.terminate(nil) }
            )
        )
        // Bu olmadan balon varsayılan yüksekliğinde kalır ve içeriği keser.
        barindiran.sizingOptions = [.preferredContentSize]
        balon.contentViewController = barindiran

        let sayac = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.basligiTazele() }
        }
        RunLoop.main.add(sayac, forMode: .common)
        baslikSayaci = sayac
        basligiTazele()
        cubukPenceresiniIzle()

        // Kilit durumu değişince paneli ve simgeyi eşitler. Otomatik süre
        // sonunda kilit kendi kendine açıldığında da bu yol çalışır.
        kilit.$kilitli
            .removeDuplicates()
            .sink { [weak self] kilitli in
                MainActor.assumeIsolated { self?.kilitDurumuDegisti(kilitli) }
            }
            .store(in: &abonelikler)
    }

    deinit {
        baslikSayaci?.invalidate()
        if let cubukPenceresiTasindi {
            NotificationCenter.default.removeObserver(cubukPenceresiTasindi)
        }
    }

    // MARK: - Klavye kilidi

    @discardableResult
    func kilidiDegistir() -> KlavyeKilidi.Sonuc {
        if kilit.kilitli {
            kilit.kilidiAc()
            return .tamam
        }
        kilit.medyaTuslariniDaEngelle = ayarlar.medyaTuslariniDaKilitle
        let sonuc = kilit.kilitle()
        if sonuc == .tamam {
            // Kilit kurulduğuna göre balonun yolu kapatmasına gerek yok.
            balon.performClose(nil)
        }
        return sonuc
    }

    private func kilitDurumuDegisti(_ kilitli: Bool) {
        simgeyiTazele()
        // Panel her zaman gösterilir: süreli açılma olmadığı için kilidi
        // açmanın en görünür yolu bu.
        guard kilitli else {
            kilitPaneli.gizle()
            return
        }
        kilitPaneli.goster(dil: gecerliDil) { [weak self] in
            self?.kilit.kilidiAc()
        }
    }

    private var gecerliDil: Dil {
        let saklanan = UserDefaults.standard.string(forKey: "arayuzDili") ?? ""
        return Dil(rawValue: saklanan) ?? .tercihEdilen
    }

    // MARK: - Menü çubuğu ögesi

    private func simgeyiTazele() {
        guard let dugme = ogeMenuCubugunda.button else { return }
        let ad = kilit.kilitli ? "keyboard.badge.eye" : "laptopcomputer"
        let simge = NSImage(systemSymbolName: ad, accessibilityDescription: "MacDuoTR")
            ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "MacDuoTR")
        // Şablon simge: menü çubuğu açık/koyu görünümüne kendisi uyar. Sabit
        // bir renk vermek simgeyi bazı duvar kâğıtlarında okunmaz kılıyordu;
        // kilitli durum yalnızca simgenin kendisiyle anlatılır.
        simge?.isTemplate = true
        dugme.image = simge
        dugme.contentTintColor = nil
        dugme.toolTip = kilit.kilitli ? gecerliDil.yazi("kilit.durum.kilitli") : "MacDuoTR"
    }

    @objc private func balonuDegistir(_ gonderen: Any?) {
        guard let dugme = ogeMenuCubugunda.button else { return }
        if balon.isShown {
            balon.performClose(gonderen)
        } else {
            // Balon her açılışta izinleri yeniden okur: kullanıcı Sistem
            // Ayarları'ndan izin verdiyse uyarı hemen kaybolmalı.
            izinler.tazele()
            NSApp.activate()
            sabitle(dugme)
            balon.contentViewController?.view.window?.makeKey()
        }
    }

    /// Açıyı göstermek düğme genişliğini değiştirir ve menü çubuğundaki durum
    /// ögesi penceresi yaklaşık onda bir saniye sonra kayar. AppKit balonu
    /// genişlik değişiminde, kaymadan önce yerleştirdiği için pencere oturana
    /// kadar bir düğme genişliği uzağa düşer.
    private func cubukPenceresiniIzle() {
        cubukPenceresiTasindi = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: nil,
            queue: .main
        ) { [weak self] bildirim in
            MainActor.assumeIsolated {
                guard let self, self.balon.isShown,
                      let dugme = self.ogeMenuCubugunda.button,
                      let tasinan = bildirim.object as? NSWindow,
                      tasinan === dugme.window else { return }
                // Animasyon sürerken yeniden göstermek balonu titretir.
                let animasyon = self.balon.animates
                self.balon.animates = false
                self.sabitle(dugme)
                self.balon.animates = animasyon
            }
        }
    }

    /// Boş bir dikdörtgen düğmenin kendi sınırları demek.
    private func sabitle(_ dugme: NSStatusBarButton) {
        balon.show(relativeTo: .zero, of: dugme, preferredEdge: .minY)
    }

    private func basligiTazele() {
        guard let dugme = ogeMenuCubugunda.button else { return }
        if ayarlar.menudeAciGoster, denetleyici.sensorVar {
            dugme.title = String(format: " %.0f°", denetleyici.anlikAci)
        } else if !dugme.title.isEmpty {
            dugme.title = ""
        }
    }
}
