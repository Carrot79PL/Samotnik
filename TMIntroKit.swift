import Cocoa
import MetalKit

/// Intro studia „Tomasz Marchewka STUDIO” (Swift + Metal) – wersja filmowa: pióro wieczne pisze podpis granatowym tuszem.
/// Użycie (jedno wywołanie zamiast starego intra):
///
///     TMIntro.play(in: window.contentView!) { /* menu / start gry */ }
///
/// Nakłada się na całe okno, trwa ok. 19,5 s (klik lub klawisz = pomiń), po zakończeniu samo znika i woła completion
/// (na głównym wątku). TMINTRO_MUTE=1 wycisza. Build: LogoData.swift Bake.swift PenSound.swift FilmSound.swift
/// TMIntroView.swift TMIntroKit.swift + frameworki Metal, MetalKit, MetalPerformanceShaders, AVFoundation.
enum TMIntro {
    @discardableResult
    static func play(in container: NSView, completion: @escaping () -> Void) -> NSView {
        let v = TMIntroView(frame: container.bounds)
        v.style = 0; v.fadeOut = true; v.letterbox = false
        v.soundEnabled = ProcessInfo.processInfo.environment["TMINTRO_MUTE"] == nil
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true; v.layer?.backgroundColor = NSColor.black.cgColor
        v.alphaValue = 0
        var done = false
        v.onFinish = { [weak v] in
            if done { return }; done = true
            DispatchQueue.main.async {
                completion()
                guard let v = v else { return }
                NSAnimationContext.runAnimationGroup({ c in c.duration = 0.7; v.animator().alphaValue = 0 }, completionHandler: { v.removeFromSuperview() })
            }
        }
        container.addSubview(v, positioned: .above, relativeTo: nil)
        container.window?.makeFirstResponder(v)
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.8; v.animator().alphaValue = 1 })
        v.start()
        return v
    }
}
