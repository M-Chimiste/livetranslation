//
//  SubtitleOverlayWindowController.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class SubtitleOverlayWindowController: NSObject, ObservableObject {
    fileprivate static let minimumFrameSize = CGSize(width: 360, height: 96)
    private static let defaultFrameSize = CGSize(width: 1_200, height: 160)

    private let settingsStore: SettingsStore
    private let displayModel: SubtitleDisplayModel
    private var cancellables = Set<AnyCancellable>()
    private var panel: SubtitleOverlayPanel?
    private var isApplyingFrameProgrammatically = false

    @Published private(set) var isVisible = false

    init(settingsStore: SettingsStore, displayModel: SubtitleDisplayModel) {
        self.settingsStore = settingsStore
        self.displayModel = displayModel

        super.init()

        settingsStore.$settings
            .map(\.overlay)
            .removeDuplicates()
            .sink { [weak self] overlaySettings in
                Task { @MainActor in
                    self?.applyOverlaySettings(overlaySettings)
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        let panel = ensurePanel()
        let frame = sanitizedFrame(settingsStore.settings.overlay.frame.cgRect)
        setPanelFrame(frame, display: true, persist: true)
        applyOverlaySettings(settingsStore.settings.overlay)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggleVisibility() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func setLocked(_ isLocked: Bool) {
        settingsStore.settings.overlay.isLocked = isLocked
        applyOverlaySettings(settingsStore.settings.overlay)
    }

    func toggleLocked() {
        setLocked(!settingsStore.settings.overlay.isLocked)
    }

    func resetFrame() {
        let frame = defaultFrame()
        setPanelFrame(frame, display: true, persist: true)
    }

    private func ensurePanel() -> SubtitleOverlayPanel {
        if let panel {
            return panel
        }

        let panel = SubtitleOverlayPanel(
            contentRect: sanitizedFrame(settingsStore.settings.overlay.frame.cgRect),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        let rootView = SubtitleOverlayView(
            displayModel: displayModel,
            settingsStore: settingsStore
        )
        let hostingView = SubtitleOverlayHostingView(rootView: rootView)
        hostingView.isOverlayInteractionEnabled = !settingsStore.settings.overlay.isLocked
        hostingView.didEndInteraction = { [weak self] frame in
            Task { @MainActor in
                self?.persistFrame(frame)
            }
        }
        panel.contentView = hostingView

        self.panel = panel
        applyOverlaySettings(settingsStore.settings.overlay)
        return panel
    }

    private func applyOverlaySettings(_ overlaySettings: OverlaySettings) {
        guard let panel else { return }

        panel.isOverlayLocked = overlaySettings.isLocked
        panel.ignoresMouseEvents = overlaySettings.isLocked

        if let hostingView = panel.contentView as? SubtitleOverlayHostingView<SubtitleOverlayView> {
            hostingView.isOverlayInteractionEnabled = !overlaySettings.isLocked
        }
    }

    private func persistFrame(_ frame: CGRect) {
        let sanitizedFrame = sanitizedFrame(frame)

        if panel?.frame != sanitizedFrame {
            setPanelFrame(sanitizedFrame, display: true, persist: false)
        }

        if settingsStore.settings.overlay.frame.cgRect != sanitizedFrame {
            settingsStore.settings.overlay.frame = OverlayFrame(sanitizedFrame)
        }
    }

    private func setPanelFrame(_ frame: CGRect, display: Bool, persist: Bool) {
        let sanitizedFrame = sanitizedFrame(frame)

        isApplyingFrameProgrammatically = true
        panel?.setFrame(sanitizedFrame, display: display)
        isApplyingFrameProgrammatically = false

        if persist, settingsStore.settings.overlay.frame.cgRect != sanitizedFrame {
            settingsStore.settings.overlay.frame = OverlayFrame(sanitizedFrame)
        }
    }

    private func sanitizedFrame(_ frame: CGRect) -> CGRect {
        let visibleFrame = screen(for: frame)?.visibleFrame ?? NSScreen.main?.visibleFrame

        guard let visibleFrame else {
            return frame.withMinimumSize(Self.minimumFrameSize)
        }

        let minimumSize = Self.minimumFrameSize
        let width = min(max(frame.width, minimumSize.width), visibleFrame.width)
        let height = min(max(frame.height, minimumSize.height), visibleFrame.height)

        if !frame.intersects(visibleFrame) {
            return defaultFrame(for: visibleFrame)
        }

        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func defaultFrame() -> CGRect {
        if let visibleFrame = NSScreen.main?.visibleFrame {
            return defaultFrame(for: visibleFrame)
        }

        return OverlayFrame.defaults.cgRect
    }

    private func defaultFrame(for visibleFrame: CGRect) -> CGRect {
        let width = min(Self.defaultFrameSize.width, visibleFrame.width * 0.9)
        let height = min(Self.defaultFrameSize.height, visibleFrame.height * 0.18)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.minY + visibleFrame.height * 0.16

        return CGRect(x: x, y: y, width: width, height: height)
            .withMinimumSize(Self.minimumFrameSize)
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)

        if let containingScreen = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) }) {
            return containingScreen
        }

        if let intersectingScreen = NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
        }), intersectingScreen.visibleFrame.intersects(frame) {
            return intersectingScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}

extension SubtitleOverlayWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrameProgrammatically else { return }
        persistFrame((notification.object as? NSWindow)?.frame ?? .zero)
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingFrameProgrammatically else { return }
        persistFrame((notification.object as? NSWindow)?.frame ?? .zero)
    }
}

private final class SubtitleOverlayPanel: NSPanel {
    var isOverlayLocked = true

    override var canBecomeKey: Bool {
        !isOverlayLocked
    }

    override var canBecomeMain: Bool {
        !isOverlayLocked
    }
}

private final class SubtitleOverlayHostingView<Content: View>: NSHostingView<Content> {
    private enum DragMode {
        case move
        case resize
    }

    private struct DragContext {
        let mode: DragMode
        let initialMouseLocation: CGPoint
        let initialFrame: CGRect
    }

    var isOverlayInteractionEnabled = false
    var didEndInteraction: ((CGRect) -> Void)?

    private var dragContext: DragContext?

    override func mouseDown(with event: NSEvent) {
        guard isOverlayInteractionEnabled, let window else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let isResizeHandle = location.x >= bounds.maxX - 44 && location.y <= bounds.minY + 44
        let mode: DragMode = isResizeHandle ? .resize : .move

        dragContext = DragContext(
            mode: mode,
            initialMouseLocation: NSEvent.mouseLocation,
            initialFrame: window.frame
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard isOverlayInteractionEnabled,
              let window,
              let dragContext
        else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - dragContext.initialMouseLocation.x
        let deltaY = currentMouseLocation.y - dragContext.initialMouseLocation.y

        switch dragContext.mode {
        case .move:
            var frame = dragContext.initialFrame
            frame.origin.x += deltaX
            frame.origin.y += deltaY
            window.setFrame(frame, display: true)

        case .resize:
            let initialFrame = dragContext.initialFrame
            let newWidth = max(SubtitleOverlayWindowController.minimumFrameSize.width, initialFrame.width + deltaX)
            let newHeight = max(SubtitleOverlayWindowController.minimumFrameSize.height, initialFrame.height - deltaY)
            let topY = initialFrame.maxY

            let frame = CGRect(
                x: initialFrame.minX,
                y: topY - newHeight,
                width: newWidth,
                height: newHeight
            )
            window.setFrame(frame, display: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let frame = window?.frame {
            didEndInteraction?(frame)
        }

        dragContext = nil
        super.mouseUp(with: event)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }

    func withMinimumSize(_ minimumSize: CGSize) -> CGRect {
        CGRect(
            x: origin.x,
            y: origin.y,
            width: max(width, minimumSize.width),
            height: max(height, minimumSize.height)
        )
    }
}
