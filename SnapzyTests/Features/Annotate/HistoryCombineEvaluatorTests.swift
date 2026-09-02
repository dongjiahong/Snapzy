//
//  HistoryCombineEvaluatorTests.swift
//  SnapzyTests
//
//  Unit tests for history multi-select combine validation.
//

import Foundation
import XCTest
@testable import Snapzy

final class HistoryCombineEvaluatorTests: XCTestCase {
  func testEvaluate_rejectsVideoOrGIFSelection() {
    let records = [
      makeRecord(type: .screenshot, filePath: "/tmp/a.png"),
      makeRecord(type: .video, filePath: "/tmp/b.mov"),
    ]

    XCTAssertEqual(HistoryCombineEvaluator.evaluate(records), .containsUnsupportedMedia)
  }

  func testEvaluate_requiresAtLeastTwoExistingScreenshots() {
    XCTAssertEqual(HistoryCombineEvaluator.evaluate([]), .needMoreImages)
    XCTAssertEqual(
      HistoryCombineEvaluator.evaluate([makeRecord(type: .screenshot, filePath: "/tmp/missing-a.png")]),
      .needMoreImages
    )
  }

  func testEvaluate_opensExistingScreenshotsAndNotesMissingFiles() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_HistoryCombine_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = directory.appendingPathComponent("first.png")
    let secondURL = directory.appendingPathComponent("second.png")
    try Data("first".utf8).write(to: firstURL)
    try Data("second".utf8).write(to: secondURL)
    let missingURL = directory.appendingPathComponent("missing.png")

    let result = HistoryCombineEvaluator.evaluate([
      makeRecord(type: .screenshot, filePath: firstURL.path),
      makeRecord(type: .screenshot, filePath: secondURL.path),
      makeRecord(type: .screenshot, filePath: missingURL.path),
    ])

    XCTAssertEqual(
      result,
      .ready(urls: [firstURL, secondURL], skippedMissing: true)
    )
  }

  private func makeRecord(type: CaptureHistoryType, filePath: String) -> CaptureHistoryRecord {
    CaptureHistoryRecord(
      id: UUID(),
      filePath: filePath,
      fileName: URL(fileURLWithPath: filePath).lastPathComponent,
      captureType: type,
      fileSize: 1024,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      width: 640,
      height: 360,
      duration: type == .screenshot ? nil : 12,
      thumbnailPath: nil,
      isDeleted: false
    )
  }
}
