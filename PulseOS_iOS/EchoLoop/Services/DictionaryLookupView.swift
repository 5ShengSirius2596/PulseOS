import SwiftUI
import UIKit

/// 调用 iOS 系统内置离线词典（UIReferenceLibraryViewController），支持点击英语单词即查
struct DictionaryLookupView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {}
}

struct LookupWordItem: Identifiable {
    let id = UUID()
    let word: String
}
