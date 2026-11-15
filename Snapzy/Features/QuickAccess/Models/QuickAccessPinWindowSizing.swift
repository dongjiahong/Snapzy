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

  /// A pin opens over the region it was captured from, so several screenshots
  /// taken in different places don't pile up in the middle of the screen.
  /// When the pin is a different size (canvas padding, annotations), it stays
  /// centered on the captured region.
  static func frame(placingCapturedRegion captureRect: CGRect, size: CGSize, on screen: NSScreen) -> NSRect {
    frame(placingCapturedRegion: captureRect, size: size, visibleFrame: screen.visibleFrame)
  }

  static func frame(placingCapturedRegion captureRect: CGRect, size: CGSize, visibleFrame: NSRect) -> NSRect {
    let frame = NSRect(
      x: captureRect.midX - size.width / 2,
      y: captureRect.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
    return constrainedFrame(frame, visibleFrame: visibleFrame)
  }

  /// Screen containing the captured region, falling back to any intersecting
  /// screen for regions that cross display boundaries.
  static func screen(containing captureRect: CGRect) -> NSScreen? {
    let center = CGPoint(x: captureRect.midX, y: captureRect.midY)
    return NSScreen.screens.first { $0.frame.contains(center) }
      ?? NSScreen.screens.first { $0.frame.intersects(captureRect) }
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
