//
//  QuickAccessPinWindowManager.swift
//  Snapzy
//
//  Manages independent always-on-top pinned screenshot windows.
//

import AppKit
import SwiftUI

@MainActor
final class QuickAccessPinWindowManager {
  static let shared = QuickAccessPinWindowManager()

  private var controllers: [UUID: QuickAccessPinWindowController] = [:]

  private init() {}

  @discardableResult
  func show(item: QuickAccessItem, onUserClose: @escaping (UUID) -> Void) -> Bool {
    guard !item.isVideo else { return false }

    if let controller = controllers[item.id] {
      controller.update(item: item)
      controller.orderFront()
      return true
    }

    let controller = QuickAccessPinWindowController(item: item)
    controller.onUserClose = { [weak self] id in
      self?.controllers[id] = nil
      onUserClose(id)
    }
    controllers[item.id] = controller
    controller.show()
    return true
  }

  func update(item: QuickAccessItem, imageOverride: NSImage? = nil) {
    controllers[item.id]?.update(item: item, imageOverride: imageOverride)
  }

  /// Reload every pin showing `url` from disk. Covers edits saved by an editor that is
  /// not linked to a Quick Access item (so no item-id based update ever reaches the pin).
  func refresh(url: URL) {
    let target = url.standardizedFileURL
    for controller in controllers.values where controller.fileURL.standardizedFileURL == target {
      controller.reloadFromDisk()
    }
  }

  func pinnedImage(forURL url: URL) -> NSImage? {
    let target = url.standardizedFileURL
    return controllers.values.first { $0.fileURL.standardizedFileURL == target }?.currentImage
  }

  func close(id: UUID) {
    controllers.removeValue(forKey: id)?.close()
  }

  func closeAll() {
    for controller in controllers.values {
      controller.close()
    }
    controllers.removeAll()
  }

  func suspendAllMouseMonitors() {
    for controller in controllers.values {
      controller.suspendMouseMonitors()
    }
  }

  func resumeAllMouseMonitors() {
    for controller in controllers.values {
      controller.resumeMouseMonitors()
    }
  }

  func applyAppearance(roundedCorners: Bool, shadowEnabled: Bool) {
    for controller in controllers.values {
      controller.applyAppearance(roundedCorners: roundedCorners, shadowEnabled: shadowEnabled)
    }
  }
}

@MainActor
private final class QuickAccessPinWindowController {
  var onUserClose: ((UUID) -> Void)?

  private var item: QuickAccessItem
  private let state: QuickAccessPinWindowState
  private let window: QuickAccessPinWindow

  private var targetZoomFactor: CGFloat = 1
  private var zoomTimer: Timer?
  private var zoomCenter: CGPoint?
  private var isHiddenForEditing = false
  private var isEditorOpen = false
  private var revealFallbackTask: Task<Void, Never>?

  init(item: QuickAccessItem) {
    self.item = item

    let image = Self.loadImage(for: item)
    let screen = ScreenUtility.activeScreen()
    state = QuickAccessPinWindowState(
      id: item.id,
      url: item.url,
      image: image,
      thumbnail: item.thumbnail,
      baseSize: QuickAccessPinWindowSizing.baseSize(for: image.size)
    )

    let frame = QuickAccessPinWindowSizing.centeredFrame(size: state.displaySize, on: screen)
    window = QuickAccessPinWindow(contentRect: frame, state: state)
    window.contentView = hostingView(size: state.displaySize)
    window.applyAppearance(
      roundedCorners: QuickAccessManager.shared.pinWindowRoundedCorners,
      shadowEnabled: QuickAccessManager.shared.pinWindowShadowEnabled
    )
    window.onEscapeRequested = { [weak self] in
      self?.handleUserClose()
    }
    window.onCopyRequested = { [weak self] in
      self?.copyPinnedImage()
    }
    window.onEditRequested = { [weak self] in
      self?.openAnnotator()
    }
    window.onDoubleClickRequested = { [weak self] in
      self?.handleUserClose()
    }
    window.onZoomStepRequested = { [weak self] step in
      self?.handleZoomStep(step)
    }
  }

  func applyAppearance(roundedCorners: Bool, shadowEnabled: Bool) {
    window.applyAppearance(roundedCorners: roundedCorners, shadowEnabled: shadowEnabled)
  }

  func show() {
    window.alphaValue = 1.0
    orderFront()
  }

  func orderFront() {
    window.orderFrontRegardless()
    window.updateMousePassthrough()
  }

  func update(item: QuickAccessItem, imageOverride: NSImage? = nil) {
    stopZoomAnimationLoop()
    self.item = item
    let image = imageOverride ?? Self.loadImage(for: item)
    let newSize = state.update(
      url: item.url,
      image: image,
      thumbnail: item.thumbnail,
      baseSize: QuickAccessPinWindowSizing.baseSize(for: image.size)
    )
    targetZoomFactor = state.zoomFactor
    resize(to: newSize, animated: false)
  }

  var fileURL: URL { state.url }
  var currentImage: NSImage { state.image }

  func reloadFromDisk() {
    let access = SandboxFileAccessManager.shared.beginAccessingURL(state.url)
    defer { access.stop() }
    guard let image = NSImage(contentsOf: state.url) else { return }

    stopZoomAnimationLoop()
    let newSize = state.update(
      url: state.url,
      image: image,
      thumbnail: state.thumbnail,
      baseSize: QuickAccessPinWindowSizing.baseSize(for: image.size)
    )
    targetZoomFactor = state.zoomFactor
    resize(to: newSize, animated: false)
    if !isEditorOpen {
      revealAfterEditing()
    }
  }

  func close() {
    stopZoomAnimationLoop()
    revealFallbackTask?.cancel()
    window.close()
  }

  func suspendMouseMonitors() {
    window.suspendMouseMonitors()
  }

  func resumeMouseMonitors() {
    window.resumeMouseMonitors()
  }

  private func hostingView(size: CGSize) -> QuickAccessPinHostingView {
    let view = QuickAccessPinWindowView(state: state)
    let hostingView = QuickAccessPinHostingView(rootView: view)
    hostingView.onMagnify = { [weak self] magnification in
      self?.window.requestMagnifyZoom(magnification: magnification)
    }
    hostingView.frame = NSRect(origin: .zero, size: size)
    return hostingView
  }

  private func handleUserClose() {
    QuickAccessManager.shared.setWindowOpen(id: item.id, isOpen: false)
    self.close()
    self.onUserClose?(item.id)
  }

  /// ⌘E on a focused pin window: open the pinned screenshot in the annotator. The pin
  /// steps aside while editing and comes back showing the saved result.
  private func openAnnotator() {
    guard !item.isVideo else { return }

    if AnnotateManager.shared.isOpen(for: item.id) {
      AnnotateManager.shared.openAnnotation(for: item)
      return
    }

    isHiddenForEditing = true
    isEditorOpen = true
    window.orderOut(nil)
    window.updateMousePassthrough()

    AnnotateManager.shared.openAnnotation(for: item) { [weak self] didSave in
      self?.handleEditorClosed(didSave: didSave)
    }
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Pinned screenshot opened in the annotator",
      context: ["fileName": item.url.lastPathComponent]
    )
  }

  private func handleEditorClosed(didSave: Bool) {
    isEditorOpen = false
    guard isHiddenForEditing else { return }
    guard didSave else {
      revealAfterEditing()
      return
    }

    // The editor writes the file after its window closes; `reloadFromDisk` reveals the
    // pin once the new image is in. The timeout only covers saves that never write.
    revealFallbackTask?.cancel()
    revealFallbackTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else { return }
      self?.revealAfterEditing()
    }
  }

  private func revealAfterEditing() {
    guard isHiddenForEditing else { return }
    isHiddenForEditing = false
    revealFallbackTask?.cancel()
    revealFallbackTask = nil
    orderFront()
  }

  private func copyPinnedImage() {
    ClipboardHelper.copyImage(from: state.url)
    DiagnosticLogger.shared.log(
      .info,
      .clipboard,
      "Pinned screenshot copied to clipboard",
      context: ["fileName": state.url.lastPathComponent]
    )
  }

  private func resize(to size: CGSize, animated: Bool) {
    let currentFrame = window.frame
    let center = zoomCenter ?? CGPoint(x: currentFrame.midX, y: currentFrame.midY)
    let proposedFrame = NSRect(
      x: center.x - size.width / 2,
      y: center.y - size.height / 2,
      width: size.width,
      height: size.height
    )
    let screen = window.screen ?? ScreenUtility.activeScreen()
    let targetFrame = QuickAccessPinWindowSizing.constrainedFrame(proposedFrame, on: screen)
    window.setFrame(targetFrame, display: true, animate: animated)
    window.contentView?.frame = NSRect(origin: .zero, size: targetFrame.size)
    window.updateMousePassthrough()
  }

  private func handleZoomStep(_ step: CGFloat) {
    if zoomTimer == nil {
      targetZoomFactor = state.zoomFactor
      let currentFrame = window.frame
      zoomCenter = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
    }
    let newTarget = targetZoomFactor + step
    targetZoomFactor = state.clampedZoomFactor(newTarget)
    startZoomAnimationLoop()
  }

  private func startZoomAnimationLoop() {
    guard zoomTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tickZoomAnimation()
      }
    }
    zoomTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopZoomAnimationLoop() {
    zoomTimer?.invalidate()
    zoomTimer = nil
    zoomCenter = nil
  }

  private func tickZoomAnimation() {
    let diff = targetZoomFactor - state.zoomFactor
    if abs(diff) < 0.001 {
      state.updateZoomFactor(targetZoomFactor)
      stopZoomAnimationLoop()
    } else {
      state.updateZoomFactor(state.zoomFactor + diff * 0.2)
    }
    resize(to: state.displaySize, animated: false)
  }

  private func resizeForCurrentZoom(animated: Bool) {
    stopZoomAnimationLoop()
    targetZoomFactor = state.zoomFactor
    resize(to: state.displaySize, animated: animated)
  }

  private static func loadImage(for item: QuickAccessItem) -> NSImage {
    let access = SandboxFileAccessManager.shared.beginAccessingURL(item.url)
    defer { access.stop() }
    return NSImage(contentsOf: item.url) ?? item.thumbnail
  }
}

@MainActor
private final class QuickAccessPinHostingView: NSHostingView<QuickAccessPinWindowView> {
  var onMagnify: ((CGFloat) -> Void)?

  private var lastMagnification: CGFloat = 0

  required init(rootView: QuickAccessPinWindowView) {
    super.init(rootView: rootView)
    setupGestureRecognizer()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupGestureRecognizer()
  }

  private func setupGestureRecognizer() {
    let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnificationGesture(_:)))
    addGestureRecognizer(recognizer)
  }

  @objc private func handleMagnificationGesture(_ sender: NSMagnificationGestureRecognizer) {
    switch sender.state {
    case .began:
      lastMagnification = 0
    case .changed:
      let delta = sender.magnification - lastMagnification
      lastMagnification = sender.magnification
      onMagnify?(delta)
    case .ended, .cancelled:
      lastMagnification = 0
    default:
      break
    }
  }
}
