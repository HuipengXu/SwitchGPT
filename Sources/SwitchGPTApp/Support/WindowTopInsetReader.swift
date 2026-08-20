import AppKit
import SwiftUI

struct WindowTopInsetReader: NSViewRepresentable {
  let onChange: (CGFloat) -> Void

  func makeNSView(context: Context) -> WindowTopInsetView {
    let view = WindowTopInsetView()
    view.onChange = onChange
    return view
  }

  func updateNSView(_ nsView: WindowTopInsetView, context: Context) {
    nsView.onChange = onChange
    nsView.reportTopInset()
  }
}

final class WindowTopInsetView: NSView {
  var onChange: ((CGFloat) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    reportTopInset()
  }

  func reportTopInset() {
    guard let contentView = window?.contentView else { return }
    let topInset = contentView.safeAreaInsets.top
    DispatchQueue.main.async { [weak self] in
      self?.onChange?(topInset)
    }
  }
}
