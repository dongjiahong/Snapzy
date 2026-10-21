//
//  QuickAccessPinWindow.swift
//  Snapzy
//
//  Borderless pin window with Snipaste-style copy, annotate, dismiss, and zoom.
//

import AppKit
import Carbon.HIToolbox

@MainActor
final class QuickAccessPinWindow: NSPanel {
  private static let pinnedWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
  internal static let scrollZoomSensitivityPrecise: CGFloat = 0.0015
  internal static let scrollZoomSensitivityCoarse: CGFloat = 0.02
  internal static let magnificationZoomSensitivity: CGFloat = 0.2
  private static let copyKeyCode = UInt16(kVK_ANSI_C)
  private static let editKeyCode = UInt16(kVK_ANSI_E)
  private static let hotKeySignature = OSType(0x5A51_5043)
  private static let copyHotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
  private static let editHotKeyID = EventHotKeyID(signature: hotKeySignature, id: 2)

  var onEscapeRequested: (() -> Void)?
  var onCopyRequested: (() -> Void)?
  var onEditRequested: (() -> Void)?
  var onDoubleClickRequested: (() -> Void)?
  var onZoomStepRequested: ((CGFloat) -> Void)?

  private var localMouseMonitor: Any?
  private var globalMouseMonitor: Any?
  private var localKeyMonitor: Any?
  private var isMouseMonitorsSuspended = false

  private static weak var activeHotKeyWindow: QuickAccessPinWindow?
  private static var copyHotKeyRef: EventHotKeyRef?
  private static var editHotKeyRef: EventHotKeyRef?
  private static var hotKeyHandler: EventHandlerRef?

  init(contentRect: NSRect, state _: QuickAccessPinWindowState) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configure()
    installMouseMonitors()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    if handleKeyDownIfNeeded(event) {
      return
    }

    super.keyDown(with: event)
  }

  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .scrollWheel where handleScrollZoomIfNeeded(event):
      return
    case .leftMouseUp where handleDoubleClickIfNeeded(event):
      return
    default:
      super.sendEvent(event)
    }
  }

  override func close() {
    if Self.activeHotKeyWindow === self {
      Self.setActiveHotKeyWindow(nil)
    }
    if !isMouseMonitorsSuspended {
      removeMouseMonitorsOnly()
    }
    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
    isMouseMonitorsSuspended = false
    super.close()
  }

  func updateMousePassthrough() {
    // A pin hidden while its screenshot is being edited must not claim ⌘E / ⌃C.
    let isInside = isVisible && frame.contains(NSEvent.mouseLocation)
    ignoresMouseEvents = false

    if isInside {
      Self.setActiveHotKeyWindow(self)
      if !isKeyWindow {
        makeKey()
      }
    } else {
      if Self.activeHotKeyWindow === self {
        Self.setActiveHotKeyWindow(nil)
      }
      if isKeyWindow {
        if let otherWindow = NSApp.windows.first(where: { $0 != self && $0.canBecomeKey && $0.isVisible }) {
          otherWindow.makeKey()
        }
      }
    }
  }

  func applyAppearance(roundedCorners: Bool, shadowEnabled: Bool) {
    hasShadow = shadowEnabled
    applyCornerRadius(roundedCorners ? NSWindow.defaultCornerRadius : 0)
  }

  private func configure() {
    isFloatingPanel = true
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovableByWindowBackground = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    ignoresMouseEvents = false
    level = Self.pinnedWindowLevel
    becomesKeyOnlyIfNeeded = false
  }

  private func installMouseMonitors() {
    let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    if localMouseMonitor == nil {
      localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
        MainActor.assumeIsolated {
          self?.updateMousePassthrough()
        }
        return event
      }
    }

    if globalMouseMonitor == nil {
      globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
        Task { @MainActor in
          self?.updateMousePassthrough()
        }
      }
    }

    if localKeyMonitor == nil {
      localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        let didHandle = MainActor.assumeIsolated {
          guard let self else { return false }
          guard self.isVisible else { return false }
          guard self.isKeyWindow || self.frame.contains(NSEvent.mouseLocation) else { return false }
          return self.handleKeyDownIfNeeded(event)
        }
        return didHandle ? nil : event
      }
    }
  }

  private func removeMouseMonitorsOnly() {
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
      self.localMouseMonitor = nil
    }
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
      self.globalMouseMonitor = nil
    }
  }

  func suspendMouseMonitors() {
    guard !isMouseMonitorsSuspended else { return }
    isMouseMonitorsSuspended = true
    removeMouseMonitorsOnly()
  }

  func resumeMouseMonitors() {
    guard isMouseMonitorsSuspended else { return }
    isMouseMonitorsSuspended = false
    installMouseMonitors()
  }

  @discardableResult
  func handleKeyDownIfNeeded(_ event: NSEvent) -> Bool {
    if handleEscapeIfNeeded(event) {
      return true
    }
    if handleCopyIfNeeded(event) {
      return true
    }
    return handleEditIfNeeded(event)
  }

  @discardableResult
  func handleDoubleClickIfNeeded(_ event: NSEvent) -> Bool {
    guard event.clickCount == 2 else { return false }

    onDoubleClickRequested?()
    return true
  }

  private func handleEscapeIfNeeded(_ event: NSEvent) -> Bool {
    guard event.keyCode == 53 else { return false }
    guard isKeyWindow || frame.contains(NSEvent.mouseLocation) else { return false }

    onEscapeRequested?()
    return true
  }

  private func handleCopyIfNeeded(_ event: NSEvent) -> Bool {
    guard Self.isControlC(event) else { return false }

    performCopy()
    return true
  }

  private func performCopy() {
    onCopyRequested?()
  }

  private func handleEditIfNeeded(_ event: NSEvent) -> Bool {
    guard Self.isCommandE(event) else { return false }

    performEdit()
    return true
  }

  private func performEdit() {
    onEditRequested?()
  }

  private func handleScrollZoomIfNeeded(_ event: NSEvent) -> Bool {
    guard let step = Self.scrollZoomStep(
      scrollingDeltaX: event.scrollingDeltaX,
      scrollingDeltaY: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
    ), let onZoomStepRequested else { return false }

    onZoomStepRequested(step)
    return true
  }

  @discardableResult
  func requestMagnifyZoom(magnification: CGFloat) -> Bool {
    guard let step = Self.magnifyZoomStep(magnification: magnification),
          let onZoomStepRequested else { return false }

    onZoomStepRequested(step)
    return true
  }

  static func isControlC(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers.contains(.control),
          !modifiers.contains(.command),
          !modifiers.contains(.option),
          !modifiers.contains(.shift) else { return false }
    return event.keyCode == copyKeyCode
  }

  /// Whether the event is a bare ⌘E — the pin-window-scoped "open in annotator" key.
  static func isCommandE(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers.contains(.command),
          !modifiers.contains(.control),
          !modifiers.contains(.option),
          !modifiers.contains(.shift) else { return false }
    return event.keyCode == editKeyCode
  }

  static func scrollZoomStep(
    scrollingDeltaX deltaX: CGFloat = 0,
    scrollingDeltaY deltaY: CGFloat,
    hasPreciseScrollingDeltas: Bool
  ) -> CGFloat? {
    let magnitude = sqrt(deltaX * deltaX + deltaY * deltaY)
    guard magnitude.isFinite, magnitude != 0 else { return nil }

    let sign: CGFloat
    if deltaY != 0 {
      sign = deltaY > 0 ? 1.0 : -1.0
    } else {
      sign = deltaX > 0 ? 1.0 : -1.0
    }

    let combinedDelta = magnitude * sign
    let sensitivity = hasPreciseScrollingDeltas ? scrollZoomSensitivityPrecise : scrollZoomSensitivityCoarse
    return combinedDelta * sensitivity
  }

  static func magnifyZoomStep(magnification: CGFloat) -> CGFloat? {
    guard magnification.isFinite, magnification != 0 else { return nil }
    return magnification * magnificationZoomSensitivity
  }

  private static func setActiveHotKeyWindow(_ window: QuickAccessPinWindow?) {
    activeHotKeyWindow = window
    if window == nil {
      removeHotKeys()
    } else {
      installHotKeysIfNeeded()
    }
  }

  /// Registers the pin window's keys (⌃C copy, ⌘E annotate) only while the pointer
  /// is inside a pin window, so both combos stay free for other apps the rest of
  /// the time — the pin window itself is a non-activating panel that never owns
  /// the keyboard. Carbon consumes the keystroke, so the app underneath does not
  /// also react to it.
  private static func installHotKeysIfNeeded() {
    installHotKeyHandlerIfNeeded()
    installHotKey(
      keyCode: UInt32(copyKeyCode),
      modifiers: UInt32(controlKey),
      id: copyHotKeyID,
      ref: &copyHotKeyRef
    )
    installHotKey(
      keyCode: UInt32(editKeyCode),
      modifiers: UInt32(cmdKey),
      id: editHotKeyID,
      ref: &editHotKeyRef
    )
  }

  private static func installHotKey(
    keyCode: UInt32,
    modifiers: UInt32,
    id: EventHotKeyID,
    ref: inout EventHotKeyRef?
  ) {
    guard ref == nil else { return }

    var hotKeyRef: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      id,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    guard status == noErr, hotKeyRef != nil else {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Pin window hotkey registration failed",
        context: ["hotKeyId": "\(id.id)", "status": "\(status)"]
      )
      return
    }
    ref = hotKeyRef
  }

  private static func removeHotKeys() {
    if let copyHotKeyRef {
      UnregisterEventHotKey(copyHotKeyRef)
      self.copyHotKeyRef = nil
    }
    if let editHotKeyRef {
      UnregisterEventHotKey(editHotKeyRef)
      self.editHotKeyRef = nil
    }
  }

  private static func installHotKeyHandlerIfNeeded() {
    guard hotKeyHandler == nil else { return }

    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: OSType(kEventHotKeyPressed)
    )
    let callback: EventHandlerUPP = { _, event, _ in
      guard let event else { return OSStatus(eventNotHandledErr) }

      var hotKeyID = EventHotKeyID()
      GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
      )
      guard hotKeyID.signature == QuickAccessPinWindow.hotKeySignature else {
        return OSStatus(eventNotHandledErr)
      }

      let pressedHotKeyId = hotKeyID.id
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let window = QuickAccessPinWindow.activeHotKeyWindow else { return }
          if pressedHotKeyId == QuickAccessPinWindow.copyHotKeyID.id {
            window.performCopy()
          } else if pressedHotKeyId == QuickAccessPinWindow.editHotKeyID.id {
            window.performEdit()
          }
        }
      }
      return noErr
    }

    InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &spec,
      nil,
      &hotKeyHandler
    )
  }
}
