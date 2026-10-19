//
//  macOSSidebar.swift
//  Mixtape
//

@_spi(Advanced) import SwiftUIIntrospect
import SwiftUI

extension View {

    #if os(macOS)
    func preventSidebarCollapse() -> some View {
        self
            .introspect(.navigationSplitView, on: .macOS(.v14...)) { splitView in
            if let delegate = splitView.delegate as? NSSplitViewController {
                  delegate.splitViewItems.first?.canCollapse = false
                  delegate.splitViewItems.first?.canCollapseFromWindowResize = false
            }
        }
      }
    #endif
}
