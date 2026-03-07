//
//  WebNavigationHandler.swift
//  desktop video
//
//  网页壁纸的导航代理，处理加载完成/失败事件
//

import WebKit

@MainActor
class WebNavigationHandler: NSObject, WKNavigationDelegate {
    static let shared = WebNavigationHandler()

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        dlog("WebView finished loading: \(webView.url?.host ?? "unknown")")
        SharedWallpaperWindowManager.shared.applyWebSettings(for: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        errorLog("WebView navigation failed: \(error.localizedDescription)")
        showErrorPage(in: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        errorLog("WebView provisional navigation failed: \(error.localizedDescription)")
        showErrorPage(in: webView, error: error)
    }

    private func showErrorPage(in webView: WKWebView, error: Error) {
        let html = """
        <html><body style="background:#1a1a1a;color:#aaa;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:-apple-system,system-ui;">
        <div style="text-align:center">
        <h2 style="color:#fff">Failed to load</h2>
        <p>\(error.localizedDescription)</p>
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
