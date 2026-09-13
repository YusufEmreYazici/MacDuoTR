import Foundation
import KapakSensoru

// Kapak açısı sensörünü terminalden test eden küçük araç.
//
//   ./build/sensorkontrol          bir kez okur
//   ./build/sensorkontrol --surekli  Ctrl+C'ye kadar okumayı sürdürür

let surekli = CommandLine.arguments.contains("--surekli")
    || CommandLine.arguments.contains("--watch")

let sensor = KapakAcisiSensoru()

guard sensor.kullanilabilir else {
    print("Kapak açısı sensörü bulunamadı.")
    print("Yalnızca bazı MacBook modellerinde bu sensör bulunur.")
    let iz = sensor.sonOkuma
    print("Son okuma durumu: 0x\(String(iz.durum, radix: 16)), \(iz.uzunluk) bayt")
    exit(1)
}

print("Sensör bulundu — çözünürlük: \(sensor.cozunurluk?.aciklama ?? "bilinmiyor")")

func yaz() {
    if let aci = sensor.aci() {
        print(String(format: "Kapak açısı: %6.2f°", aci))
    } else {
        let iz = sensor.sonOkuma
        print("Okuma başarısız — durum 0x\(String(iz.durum, radix: 16)), \(iz.uzunluk) bayt")
    }
}

if surekli {
    while true {
        yaz()
        Thread.sleep(forTimeInterval: 0.1)
    }
} else {
    yaz()
}
