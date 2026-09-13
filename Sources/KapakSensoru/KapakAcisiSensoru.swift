import Foundation
import IOKit
import IOKit.hid

/// MacBook menteşesinin açıklık açısını donanım sensöründen okur.
///
/// Apple'ın dahili yönelim sensörleri HID kullanım sayfası `0x20`, kullanım
/// `0x8A` altında bulunur. Belirli bir ürün kimliğine bağlanmaz; makinede
/// dahili olarak işaretlenmiş uygun sensör aranır. Açı bilgisi
/// `kIOHIDReportTypeFeature` raporlarından gelir:
///
/// - Rapor 1: 3 bayt `[0x01, düşük, yüksek]`, tam derece, 0...360.
/// - Rapor 7: 5 bayt `[0x07, b0, b1, b2, b3]`, küçük uçlu, derecenin yüzde
///   biri çözünürlüğünde. Her model bildirmediği için rapor 1 yedektir.
///
/// Değer yaklaşık 100 ms'de bir tazelenir ve hiçbir izin gerektirmez.
public final class KapakAcisiSensoru {

    /// Sensörün hangi raporla yanıt verdiği. Açılışta bir kez belirlenir.
    public enum Cozunurluk {
        /// Rapor 7, 0,01 derece adımlarla.
        case yuzdeBirDerece
        /// Rapor 1, 1 derece adımlarla.
        case tamDerece

        public var raporNo: Int {
            switch self {
            case .yuzdeBirDerece: return 7
            case .tamDerece: return 1
            }
        }

        public var aciklama: String {
            switch self {
            case .yuzdeBirDerece: return "rapor 7 (0,01°)"
            case .tamDerece: return "rapor 1 (1°)"
            }
        }
    }

    /// Son `aci()` çağrısında ne olduğu. Başarısız okuma `nil` döner ve
    /// nedenini burada bırakır.
    public struct OkumaIzi {
        /// `IOHIDDeviceGetReport` sonucu.
        public var durum: IOReturn = kIOReturnSuccess
        /// Aygıtın yazdığı bayt sayısı.
        public var uzunluk: Int = 0
        public var baytlar: [UInt8] = []
        /// 0...360 aralığının dışına düşen çözümlenmiş değer.
        public var reddedilenDerece: Double?
    }

    public private(set) var sonOkuma = OkumaIzi()
    public private(set) var cozunurluk: Cozunurluk?

    private var yonetici: IOHIDManager?
    private var aygit: IOHIDDevice?
    private var tampon = [UInt8](repeating: 0, count: 32)

    /// Bu Mac'te kullanılabilir bir kapak açısı sensörü var mı.
    public var kullanilabilir: Bool { aygit != nil && cozunurluk != nil }

    public init() {
        ac()
    }

    deinit {
        if let yonetici {
            IOHIDManagerClose(yonetici, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    /// Kapağın o anki açısı, derece cinsinden. Okuma başarısızsa `nil`.
    ///
    /// 0 kapalı demektir; bir MacBook kabaca 130 dereceye kadar açılır.
    public func aci() -> Double? {
        guard let cozunurluk else { return nil }
        guard let baytlar = oku(raporNo: cozunurluk.raporNo) else { return nil }
        guard baytlar.first == UInt8(cozunurluk.raporNo) else { return nil }

        let derece: Double
        switch cozunurluk {
        case .yuzdeBirDerece:
            guard baytlar.count >= 5 else { return nil }
            let ham = UInt32(baytlar[1])
                | UInt32(baytlar[2]) << 8
                | UInt32(baytlar[3]) << 16
                | UInt32(baytlar[4]) << 24
            derece = Double(ham) / 100
        case .tamDerece:
            guard baytlar.count >= 3 else { return nil }
            derece = Double(UInt16(baytlar[1]) | UInt16(baytlar[2]) << 8)
        }

        guard derece >= 0, derece <= 360 else {
            sonOkuma.reddedilenDerece = derece
            return nil
        }
        return derece
    }

    // MARK: - Aygıt

    private func ac() {
        let yonetici = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let eslesme: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,          // Apple
            kIOHIDDeviceUsagePageKey: 0x20,     // Sensör
            kIOHIDDeviceUsageKey: 0x8A,         // Yönelim
        ]
        IOHIDManagerSetDeviceMatching(yonetici, eslesme as CFDictionary)

        guard IOHIDManagerOpen(yonetici, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return
        }
        self.yonetici = yonetici

        guard let aygitlar = IOHIDManagerCopyDevices(yonetici) as? Set<IOHIDDevice> else { return }
        for aday in aygitlar {
            // Harici ekranların sensörlerini dışarıda bırakır.
            guard (IOHIDDeviceGetProperty(aday, "Built-In" as CFString) as? NSNumber)?.boolValue == true else {
                continue
            }
            aygit = aday
            for bicim in [Cozunurluk.yuzdeBirDerece, .tamDerece] {
                cozunurluk = bicim
                if aci() != nil { return }
            }
        }
        aygit = nil
        cozunurluk = nil
    }

    private func oku(raporNo: Int) -> [UInt8]? {
        sonOkuma = OkumaIzi()
        guard let aygit else {
            sonOkuma.durum = kIOReturnNoDevice
            return nil
        }
        var uzunluk = CFIndex(tampon.count)
        let sonuc = tampon.withUnsafeMutableBufferPointer { isaretci -> IOReturn in
            guard let taban = isaretci.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceGetReport(aygit, kIOHIDReportTypeFeature, CFIndex(raporNo), taban, &uzunluk)
        }
        sonOkuma.durum = sonuc
        sonOkuma.uzunluk = Int(uzunluk)
        guard sonuc == kIOReturnSuccess, uzunluk > 0 else { return nil }
        let baytlar = Array(tampon[0..<Int(uzunluk)])
        sonOkuma.baytlar = baytlar
        return baytlar
    }
}
