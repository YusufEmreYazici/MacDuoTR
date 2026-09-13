import QuartzCore
import simd

/// Bir dikdörtgeni herhangi bir dörtgene yansıtan izdüşüm dönüşümü.
enum Homografi {

    /// (0, 0) ile (`genislik`, `yukseklik`) arasındaki dikdörtgeni `koseler`
    /// dörtgenine eşler. Köşe sırası: sol alt, sağ alt, sağ üst, sol üst.
    ///
    /// Sütun vektörü düzeni: `ekran = matris * (x, y, 1)`, sonuç üçüncü
    /// bileşene bölünür.
    static func matris(genislik: Double, yukseklik: Double, koseler: [SIMD2<Double>]) -> simd_double3x3 {
        precondition(koseler.count == 4, "dört köşe bekleniyor")
        let (x0, y0) = (koseler[0].x, koseler[0].y)
        let (x1, y1) = (koseler[1].x, koseler[1].y)
        let (x2, y2) = (koseler[2].x, koseler[2].y)
        let (x3, y3) = (koseler[3].x, koseler[3].y)

        // Heckbert'in birim kare -> dörtgen çözümü.
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        var g = 0.0
        var h = 0.0
        if abs(dx3) > 1e-9 || abs(dy3) > 1e-9 {
            let determinant = dx1 * dy2 - dx2 * dy1
            if abs(determinant) > 1e-12 {
                g = (dx3 * dy2 - dx2 * dy3) / determinant
                h = (dx1 * dy3 - dx3 * dy1) / determinant
            }
        }
        let a = x1 - x0 + g * x1
        let b = x3 - x0 + h * x3
        let c = x0
        let d = y1 - y0 + g * y1
        let e = y3 - y0 + h * y3
        let f = y0

        // u = x / genislik ve v = y / yukseklik ölçeklemesini matrise katar.
        return simd_double3x3(columns: (
            SIMD3(a / genislik, d / genislik, g / genislik),
            SIMD3(b / yukseklik, e / yukseklik, h / yukseklik),
            SIMD3(c, f, 1)
        ))
    }
}
