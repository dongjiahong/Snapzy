//
//  QuickAccessPinWindowSizing.swift
//  Snapzy
//
//  Sizing policy for pinned screenshot windows.
//

import AppKit
import Foundation

enum QuickAccessPinWindowSizing {
  /// Smallest edge a pin may be shrunk to, so it stays grabbable.
  static let minimumInteractiveEdge: CGFloat = 48

  private static let screenMargin: CGFloat = 24

  /// A pin opens at the captured image's point size (1:1 with the original selection).
  static func baseSize(for imageSize: CGSize) -> CGSize {
    CGSize(width: max(imageSize.width, 1), height: max(imageSize.height, 1))
  }

  static func centeredFrame(size: CGSize, on screen: NSScreen) -> NSRect {
    let visibleFrame = screen.visibleFrame
    return NSRect(
      x: visibleFrame.midX - size.width / 2,
      y: visibleFrame.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  static func constrainedFrame(_ frame: NSRect, on screen: NSScreen) -> NSRect {
    constrainedFrame(frame, visibleFrame: screen.visibleFrame)
  }

  static func constrainedFrame(_ frame: NSRect, visibleFrame: NSRect) -> NSRect {
    let bounds = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
    // Never shrink the frame: a pin may be larger than the screen. Only keep it on-screen
    // along axes where it fits.
    let x = frame.width <= bounds.width
      ? min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
      : frame.minX
    let y = frame.height <= bounds.height
      ? min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
      : frame.minY
    return NSRect(x: x, y: y, width: frame.width, height: frame.height)
  }
}
