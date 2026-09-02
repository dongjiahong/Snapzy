import AppKit
import UniformTypeIdentifiers

enum HistoryCombineEvaluation: Equatable {
  case containsUnsupportedMedia
  case needMoreImages
  case ready(urls: [URL], skippedMissing: Bool)
}

enum HistoryCombineEvaluator {
  static func evaluate(_ records: [CaptureHistoryRecord]) -> HistoryCombineEvaluation {
    if records.contains(where: { $0.captureType != .screenshot }) {
      return .containsUnsupportedMedia
    }

    let existing = records.filter(\.fileExists)
    guard existing.count >= 2 else { return .needMoreImages }
    return .ready(urls: existing.map(\.fileURL), skippedMissing: existing.count < records.count)
  }
}

@MainActor
final class CombineImagesCoordinator {
  static let shared = CombineImagesCoordinator()

  private init() {}

  func presentPicker() {
    let panel = NSOpenPanel()
    panel.title = L10n.Combine.pickerTitle
    panel.message = L10n.Combine.pickerMessage
    panel.prompt = L10n.Combine.pickerConfirm
    panel.allowedContentTypes = [.png, .jpeg, .webP, .gif, .tiff, .heic]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false

    guard panel.runModal() == .OK, panel.urls.count >= 2 else { return }
    AnnotateManager.shared.openCombineImages(urls: panel.urls)
  }

  func combineHistoryRecords(_ records: [CaptureHistoryRecord]) {
    switch HistoryCombineEvaluator.evaluate(records) {
    case .containsUnsupportedMedia:
      AppToastManager.shared.show(message: L10n.Combine.videosNotSupported, style: .warning)
    case .needMoreImages:
      AppToastManager.shared.show(message: L10n.Combine.needTwoImages, style: .warning)
    case .ready(let urls, let skippedMissing):
      if skippedMissing {
        AppToastManager.shared.show(message: L10n.Combine.missingFiles, style: .warning)
      }
      AnnotateManager.shared.openCombineImages(urls: urls)
    }
  }
}

