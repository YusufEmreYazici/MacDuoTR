import CoreVideo
import Metal

/// Yakalanmış bir kare. Core Video sahibini birlikte tutmak, GPU hâlâ okurken
/// piksel arabelleğinin havuza geri verilmesini engeller.
struct YakalananKare: @unchecked Sendable {
    let doku: MTLTexture
    private let sahip: CVMetalTexture

    init?(_ sahip: CVMetalTexture) {
        guard let doku = CVMetalTextureGetTexture(sahip) else { return nil }
        self.doku = doku
        self.sahip = sahip
    }
}
