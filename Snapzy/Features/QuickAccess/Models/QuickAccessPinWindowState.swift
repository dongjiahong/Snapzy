//
//  QuickAccessPinWindowState.swift
//  Snapzy
//
//  Observable state for independent pinned screenshot windows.
//

import AppKit
import Combine
import Foundation

@MainActor
final class QuickAccessPinWindowState: ObservableObject {
  let id: UUID

  @Published private(set) var url: URL
  @Published private(set) var image: NSImage
  @Published private(set) var thumbnail: NSImage
  @Published private(set) var zoomFactor: CGFloat = 1

  private(set) var baseSize: CGSize
  private(set) var maxSize: CGSize

  private let absoluteMinimumZoomFactor: CGFloat = 0.4

  init(id: UUID, url: URL, image: NSImage, thumbnail: NSImage, baseSize: CGSize, maxSize: CGSize) {
    self.id = id
    self.url = url
    self.image = image
    self.thumbnail = thumbnail
    self.baseSize = baseSize
    self.maxSize = maxSize
  }

  var displaySize: CGSize {
    CGSize(width: baseSize.width * zoomFactor, height: baseSize.height * zoomFactor)
  }

  var zoomPercent: Int {
    Int((zoomFactor * 100).rounded())
  }

  var minimumZoomFactor: CGFloat {
    guard baseSize.width > 0, baseSize.height > 0 else { return 1 }
    let interactiveSize = QuickAccessPinWindowSizing.minimumInteractiveSize
    let interactiveFloor = max(
      interactiveSize.width / baseSize.width,
      interactiveSize.height / baseSize.height
    )
    let floor = max(absoluteMinimumZoomFactor, interactiveFloor)
    return min(floor, maximumZoomFactor)
  }

  var maximumZoomFactor: CGFloat {
    guard baseSize.width > 0, baseSize.height > 0 else { return 1 }
    let screenLimit = min(maxSize.width / baseSize.width, maxSize.height / baseSize.height)
    return max(1, min(2, screenLimit))
  }

  func setZoomPercent(_ percent: Int) -> CGSize {
    setZoomFactor(CGFloat(percent) / 100)
  }

  func applyZoomStep(_ step: CGFloat) -> CGSize {
    guard step.isFinite, step != 0 else { return displaySize }
    return setZoomFactor(zoomFactor + step)
  }

  func update(url: URL, image: NSImage, thumbnail: NSImage, baseSize: CGSize, maxSize: CGSize) -> CGSize {
    self.url = url
    self.image = image
    self.thumbnail = thumbnail
    return updateSizing(baseSize: baseSize, maxSize: maxSize)
  }

  func updateSizing(baseSize: CGSize, maxSize: CGSize) -> CGSize {
    self.baseSize = baseSize
    self.maxSize = maxSize
    zoomFactor = clampedZoomFactor(zoomFactor)
    return displaySize
  }

  func updateZoomFactor(_ factor: CGFloat) {
    zoomFactor = clampedZoomFactor(factor)
  }

  @discardableResult
  private func setZoomFactor(_ factor: CGFloat) -> CGSize {
    zoomFactor = clampedZoomFactor(factor)
    return displaySize
  }

  func clampedZoomFactor(_ factor: CGFloat) -> CGFloat {
    min(max(factor, minimumZoomFactor), maximumZoomFactor)
  }
}

