import AppKit
import SwiftUI

/// Klavye kilitliyken ekranda duran, fareyle kapatılabilen panel.
///
/// Uygulama etkin duruma geçmeden tıklanabilmesi için `.nonactivatingPanel`
/// kullanılır ve barındıran görünüm ilk tıklamayı da kabul eder — kilitliyken
/// kullanıcının elindeki tek araç fare olduğu için bu önemli.
@MainActor
final class KilitPaneli {

    private var pencere: NSPanel?

    var gorunur: Bool { pencere != nil }

    func goster(dil: Dil, kilidiAc: @escaping () -> Void) {
        gizle()

        let icerik = IlkTiklamayiKabulEdenGorunum(
            rootView: KilitPaneliGorunumu(dil: dil, kilidiAc: kilidiAc)
        )
        icerik.frame = NSRect(x: 0, y: 0, width: 420, height: 230)

        let panel = NSPanel(
            contentRect: icerik.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = icerik
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        // Tam ekran uygulamaların ve menü çubuğunun üstünde kalsın.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let ekran = Self.imlecinBulunduguEkran()
        let alan = ekran.visibleFrame
        let boyut = icerik.fittingSize == .zero ? icerik.frame.size : icerik.fittingSize
        panel.setContentSize(boyut)
        panel.setFrameOrigin(NSPoint(
            x: alan.midX - boyut.width / 2,
            y: alan.midY - boyut.height / 2
        ))
        panel.orderFrontRegardless()
        pencere = panel
    }

    func gizle() {
        guard let pencere else { return }
        self.pencere = nil

        // Tıklamaları hemen bırak. Bu satır şart: kilidi açan düğme panelin
        // kendi içinde olduğu için `gizle()` çoğu zaman panelin kendi olay
        // gönderimi sırasında çağrılır, AppKit de o sırada istenen kapatmayı
        // sonraki döngüye erteler. Ertelenen aralıkta pencere görünmez hâlde
        // ekranda kalır ve — `acceptsFirstMouse` yüzünden — bulunduğu
        // dikdörtgendeki tıklamaları yutmayı sürdürür.
        pencere.ignoresMouseEvents = true
        pencere.alphaValue = 0

        // Kapatmanın kendisi de olay gönderiminin dışına alınır. Pencere
        // yerelde tutulduğu için, bu arada açılan yeni bir panel etkilenmez.
        DispatchQueue.main.async {
            pencere.contentView = nil
            pencere.orderOut(nil)
            pencere.close()
        }
    }

    private static func imlecinBulunduguEkran() -> NSScreen {
        let nokta = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(nokta, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

/// Etkin olmayan bir panelde ilk tıklamanın da düğmeye ulaşmasını sağlar.
private final class IlkTiklamayiKabulEdenGorunum<Icerik: View>: NSHostingView<Icerik> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct KilitPaneliGorunumu: View {
    let dil: Dil
    let kilidiAc: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.badge.eye")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dil.yazi("panel.baslik"))
                        .font(.title2.weight(.semibold))
                    Text(dil.yazi("panel.altyazi"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: kilidiAc) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open.fill")
                    Text(dil.yazi("panel.kilidiAc"))
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)

            Text(dil.yazi("kilit.uyari"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
