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

  private let absoluteMinimumZoomFactor: CGFloat = 0.1
  // Safety bound only; the pin is not limited to the screen size.
  private let absoluteMaximumZoomFactor: CGFloat = 20

  init(id: UUID, url: URL, image: NSImage, thumbnail: NSImage, baseSize: CGSize) {
    self.id = id
    self.url = url
    self.image = image
    self.thumbnail = thumbnail
    self.baseSize = baseSize
  }

  var displaySize: CGSize {
    CGSize(width: baseSize.width * zoomFactor, height: baseSize.height * zoomFactor)
  }

  var zoomPercent: Int {
    Int((zoomFactor * 100).rounded())
  }

  var minimumZoomFactor: CGFloat {
    guard baseSize.width > 0, baseSize.height > 0 else { return 1 }
    let interactiveFloor = QuickAccessPinWindowSizing.minimumInteractiveEdge / min(baseSize.width, baseSize.height)
    let floor = max(absoluteMinimumZoomFactor, interactiveFloor)
    return min(floor, 1)
  }

  var maximumZoomFactor: CGFloat {
    absoluteMaximumZoomFactor
  }

  func setZoomPercent(_ percent: Int) -> CGSize {
    setZoomFactor(CGFloat(percent) / 100)
  }

  func applyZoomStep(_ step: CGFloat) -> CGSize {
    guard step.isFinite, step != 0 else { return displaySize }
    return setZoomFactor(zoomFactor + step)
  }

  func update(url: URL, image: NSImage, thumbnail: NSImage, baseSize: CGSize) -> CGSize {
    self.url = url
    self.image = image
    self.thumbnail = thumbnail
    return updateSizing(baseSize: baseSize)
  }

  func updateSizing(baseSize: CGSize) -> CGSize {
    self.baseSize = baseSize
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

