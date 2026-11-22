//
//  TextEditOverlay.swift
//  Snapzy
//
//  SwiftUI overlay for inline text annotation editing
//

import AppKit
import SwiftUI

/// Overlay for editing text annotations inline on the canvas
struct TextEditOverlay: View {
  @ObservedObject var state: AnnotateState
  let scale: CGFloat
  let canvasBounds: CGRect

  @State private var editingText: String = ""

  // MARK: - Constants

  private let minTextFieldWidth: CGFloat = AnnotateTextLayout.minWidth

  var body: some View {
    GeometryReader { _ in
      if let editingId = state.editingTextAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == editingId }),
         case .text(let currentText) = annotation.type {

        let displayBounds = calculateDisplayBounds(annotation.bounds)
        let logicalFont = AnnotateTextLayout.font(
          size: annotation.properties.fontSize,
          fontName: annotation.properties.fontName
        )
        let logicalSize = CGSize(
          width: max(annotation.bounds.width, minTextFieldWidth),
          height: max(annotation.bounds.height, 1)
        )
        let fieldWidth = max(displayBounds.width, minTextFieldWidth * max(scale, 0.0001))
        let fieldHeight = max(displayBounds.height, 1)
        let logicalInset = AnnotateTextLayout.textEditorInset(
          scale: 1,
          presentation: annotation.properties.textPresentation,
          fontSize: annotation.properties.fontSize
        )
        let tailTarget = annotation.properties.calloutTailTarget.map {
          TextBubbleGeometry.resolvedTailTarget(
            in: annotation.bounds,
            requestedTarget: $0,
            fontSize: annotation.properties.fontSize
          )
        }.map(calculateDisplayPoint)
        let relativeTailTarget = tailTarget.map {
          CGPoint(x: $0.x - displayBounds.minX, y: $0.y - displayBounds.minY)
        }

        ZStack(alignment: .topLeading) {
          if annotation.properties.textPresentation != .plain {
            TextBubbleShape(
              tailTarget: annotation.properties.textPresentation == .callout ? relativeTailTarget : nil,
              fontSize: logicalFont.pointSize * max(scale, 0.0001),
              cornerRadius: annotation.properties.cornerRadius * scale
            )
              .fill(annotation.properties.fillColor)
          }

          InlineAnnotationTextEditor(
            editingId: editingId,
            text: $editingText,
            font: logicalFont,
            logicalSize: logicalSize,
            textContainerInset: logicalInset,
            textColor: NSColor(annotation.properties.strokeColor),
            onCommit: { commitEdit(id: editingId) },
            onCancel: cancelEdit,
            onUndo: { state.undo() },
            onRedo: { state.redo() }
          )
        }
          .frame(
            width: fieldWidth,
            height: fieldHeight,
            alignment: .topLeading
          )
          .position(
            x: displayBounds.minX + fieldWidth / 2,
            y: displayBounds.minY + fieldHeight / 2
          )
          .onAppear {
            editingText = currentText
          }
          .onChange(of: editingText) { newValue in
            // Live-update annotation text and bounds
            if let editingId = state.editingTextAnnotationId {
              state.updateAnnotationText(id: editingId, text: newValue)
            }
          }
      }
    }
  }

  /// Convert image bounds to display coordinates
  /// The parent view supplies a frame that matches the active canvas bounds.
  /// Crop offset is handled by this conversion, so we only:
  /// 1. Scale the bounds
  /// 2. Flip Y axis (AppKit bottom-left origin → SwiftUI top-left origin)
  private func calculateDisplayBounds(_ imageBounds: CGRect) -> CGRect {
    // Scale the bounds
    let scaledX = (imageBounds.origin.x - canvasBounds.minX) * scale
    let scaledWidth = imageBounds.width * scale
    let scaledHeight = imageBounds.height * scale

    // Flip Y axis: AppKit uses bottom-left origin, SwiftUI uses top-left
    // In AppKit: y=0 is bottom, y increases upward
    // In SwiftUI: y=0 is top, y increases downward
    let flippedY = (canvasBounds.maxY - imageBounds.origin.y - imageBounds.height) * scale

    return CGRect(
      x: scaledX,
      y: flippedY,
      width: scaledWidth,
      height: scaledHeight
    )
  }

  private func calculateDisplayPoint(_ imagePoint: CGPoint) -> CGPoint {
    CGPoint(
      x: (imagePoint.x - canvasBounds.minX) * scale,
      y: (canvasBounds.maxY - imagePoint.y) * scale
    )
  }

  private func commitEdit(id: UUID) {
    if state.editingTextAnnotationId == id {
      state.updateAnnotationText(id: id, text: editingText)
      state.commitTextEditing()
    }
  }

  private func cancelEdit() {
    // If it was a new annotation with empty text, delete it
    if let editingId = state.editingTextAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == editingId }),
       case .text(let text) = annotation.type,
       text.isEmpty {
      state.annotations.removeAll { $0.id == editingId }
      state.selectedAnnotationId = nil
    }
    state.finishTextEditing()
  }
}

private struct TextBubbleShape: Shape {
  let tailTarget: CGPoint?
  let fontSize: CGFloat
  let cornerRadius: CGFloat

  func path(in rect: CGRect) -> Path {
    let resolvedCornerRadius = cornerRadius > 0
      ? min(cornerRadius, min(rect.width, rect.height) * 0.46)
      : TextBubbleGeometry.cornerRadius(in: rect, fontSize: fontSize)
    return Path(
      TextBubbleGeometry.bubblePath(
        in: rect,
        cornerRadius: resolvedCornerRadius,
        tailTarget: tailTarget,
        fontSize: fontSize
      )
    )
  }
}

/// Flipped AppKit host view that locks `NSTextView` to the top-left of its frame
/// and scales its coordinate space cleanly from 1:1 logical typography to display size.
/// This eliminates both SwiftUI/AppKit non-flipped vertical drift on line wrap and
/// SF Pro optical-sizing wrap mismatches when `scale != 1.0`.
final class FlippedTextEditorContainerView: NSView {
  let textView: InlineAnnotationTextEditor.UndoIsolatedTextView
  var logicalSize: CGSize = .zero {
    didSet {
      guard logicalSize != oldValue else { return }
      syncLayout()
    }
  }

  override var isFlipped: Bool { true }

  init(textView: InlineAnnotationTextEditor.UndoIsolatedTextView) {
    self.textView = textView
    super.init(frame: .zero)
    autoresizesSubviews = false
    addSubview(textView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    syncLayout()
  }

  override func layout() {
    super.layout()
    syncLayout()
  }

  func syncLayout() {
    let targetLogicalSize = CGSize(
      width: max(logicalSize.width, 1),
      height: max(logicalSize.height, 1)
    )
    if frame.size.width > 0, frame.size.height > 0 {
      setBoundsOrigin(.zero)
      setBoundsSize(targetLogicalSize)
    }

    let textFrame = CGRect(origin: .zero, size: targetLogicalSize)
    if textView.frame != textFrame {
      textView.frame = textFrame
    }

    let contentWidth = max(
      targetLogicalSize.width - textView.textContainerInset.width * 2,
      AnnotateTextLayout.minContentWidth
    )
    if let textContainer = textView.textContainer {
      let containerSize = CGSize(width: contentWidth, height: AnnotateTextLayout.maxHeight)
      if textContainer.containerSize != containerSize {
        textContainer.containerSize = containerSize
        textView.layoutManager?.ensureLayout(for: textContainer)
      }
    }
  }
}

struct InlineAnnotationTextEditor: NSViewRepresentable {
  let editingId: UUID
  @Binding var text: String
  let font: NSFont
  let logicalSize: CGSize
  let textContainerInset: NSSize
  let textColor: NSColor
  let onCommit: () -> Void
  let onCancel: () -> Void
  let onUndo: () -> Void
  let onRedo: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> FlippedTextEditorContainerView {
    // Explicitly build a TextKit 1 stack so live editing uses the exact same
    // `NSLayoutManager` line-breaking and metrics as `AnnotateTextLayout`.
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    layoutManager.usesFontLeading = true
    let textContainer = NSTextContainer(
      size: CGSize(
        width: max(logicalSize.width - textContainerInset.width * 2, AnnotateTextLayout.minContentWidth),
        height: AnnotateTextLayout.maxHeight
      )
    )
    textContainer.lineFragmentPadding = 0
    textContainer.lineBreakMode = .byWordWrapping
    textContainer.widthTracksTextView = false
    textContainer.heightTracksTextView = false
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)

    let textView = UndoIsolatedTextView(frame: .zero, textContainer: textContainer)
    textView.delegate = context.coordinator
    textView.string = text
    textView.onCommit = onCommit
    textView.onCancel = onCancel
    textView.onUndo = onUndo
    textView.onRedo = onRedo

    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = false
    textView.autoresizingMask = []
    textView.textContainerInset = textContainerInset
    textView.font = font
    textView.textColor = textColor
    textView.insertionPointColor = textColor

    let container = FlippedTextEditorContainerView(textView: textView)
    container.logicalSize = logicalSize

    context.coordinator.focusedEditingId = editingId
    textView.requestInitialFocus()

    return container
  }

  func updateNSView(_ container: FlippedTextEditorContainerView, context: Context) {
    let textView = container.textView
    context.coordinator.text = $text
    textView.onCommit = onCommit
    textView.onCancel = onCancel
    textView.onUndo = onUndo
    textView.onRedo = onRedo

    if textView.string != text {
      context.coordinator.isApplyingExternalText = true
      textView.string = text
      context.coordinator.isApplyingExternalText = false
    }
    if textView.font != font {
      textView.font = font
    }
    if textView.textContainerInset != textContainerInset {
      textView.textContainerInset = textContainerInset
    }
    if textView.textColor != textColor {
      textView.textColor = textColor
      textView.insertionPointColor = textColor
    }
    container.logicalSize = logicalSize
    container.syncLayout()

    if context.coordinator.focusedEditingId != editingId {
      context.coordinator.focusedEditingId = editingId
      textView.requestInitialFocus()
    }

    // The annotation can grow or move while an IME composition is active.
    // Tell AppKit to ask for the caret rectangle again after this layout pass,
    // so its candidate window follows the current character rather than an
    // earlier position in the text.
    textView.refreshInputMethodPlacement()
  }

  static func dismantleNSView(_ container: FlippedTextEditorContainerView, coordinator: Coordinator) {
    let textView = container.textView
    textView.onCommit = nil
    textView.onCancel = nil
    textView.onUndo = nil
    textView.onRedo = nil
    textView.delegate = nil
    textView.undoManager?.removeAllActions()
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    var isApplyingExternalText = false
    var focusedEditingId: UUID?

    init(text: Binding<String>) {
      self.text = text
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingExternalText,
            let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      (notification.object as? UndoIsolatedTextView)?.refreshInputMethodPlacement()
    }

    func textDidEndEditing(_ notification: Notification) {
      guard let textView = notification.object as? UndoIsolatedTextView else { return }
      textView.onCommit?()
    }
  }

  final class UndoIsolatedTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    private var wantsInitialFocus = false
    private var hasPendingInputMethodPlacementRefresh = false

    override var undoManager: UndoManager? { nil }
    override var acceptsFirstResponder: Bool { true }

    override func didChangeText() {
      super.didChangeText()
      refreshInputMethodPlacement()
    }

    /// Inline annotation text changes its frame as the user types. Input
    /// methods cache character coordinates, so refresh them on the next run
    /// loop after AppKit has applied the new frame and layout.
    func refreshInputMethodPlacement() {
      guard !hasPendingInputMethodPlacementRefresh else { return }
      hasPendingInputMethodPlacementRefresh = true

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.hasPendingInputMethodPlacementRefresh = false
        if let textContainer = self.textContainer {
          self.layoutManager?.ensureLayout(for: textContainer)
        }
        self.inputContext?.invalidateCharacterCoordinates()
      }
    }

    func requestInitialFocus() {
      wantsInitialFocus = true
      focusWhenReady(attempt: 0)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if wantsInitialFocus {
        focusWhenReady(attempt: 0)
      }
    }

    private func focusWhenReady(attempt: Int) {
      let delay = attempt == 0 ? 0 : 0.01
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self, self.wantsInitialFocus else { return }

        if let window = self.window {
          if !window.isKeyWindow {
            window.makeKey()
          }
          window.makeFirstResponder(self)
          if window.firstResponder === self {
            let endLocation = (self.string as NSString).length
            self.setSelectedRange(NSRange(location: endLocation, length: 0))
            self.wantsInitialFocus = false
            return
          }
        }

        if attempt < 8 {
          self.focusWhenReady(attempt: attempt + 1)
        }
      }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard event.type == .keyDown else {
        return super.performKeyEquivalent(with: event)
      }

      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if event.keyCode == 6 && flags == .command {
        onUndo?()
        return true
      }
      if event.keyCode == 6 && flags == [.command, .shift] {
        onRedo?()
        return true
      }

      return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if (event.keyCode == 36 || event.keyCode == 76), flags == .command {
        onCommit?()
        return
      }
      if event.keyCode == 53 {
        onCancel?()
        return
      }
      super.keyDown(with: event)
    }
  }
}