/// 无头 WebView 抓取 — 用于 JS 渲染页面
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewScraper {
  /// 加载 JS 页面并提取所有文章链接
  static Future<List<Map<String, String>>> extractLinks(
    String url, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      onLoadStop: (controller, url) async {
        // 等 JS 渲染完
        await Future.delayed(const Duration(seconds: 3));
      },
    );

    try {
      await headless.run();
      await Future.delayed(const Duration(seconds: 5));

      // 先滚动加载更多内容
      final ctrl = headless.webViewController;
      if (ctrl == null) return [];

      for (int i = 0; i < 4; i++) {
        await ctrl.evaluateJavascript(
          source: 'window.scrollTo(0, ${(i + 1) * 2000});',
        );
        await Future.delayed(const Duration(milliseconds: 600));
      }
      await ctrl.evaluateJavascript(source: 'window.scrollTo(0, 0);');
      await Future.delayed(const Duration(milliseconds: 500));

      // 提取文章链接（过滤导航）
      final result = await ctrl.evaluateJavascript(source: '''
        (function() {
          var seen = {};
          var links = [];
          var anchors = document.querySelectorAll('a[href*="news.cctv.com"]');
          anchors.forEach(function(a) {
            var title = a.textContent.trim();
            var href = a.href;
            if (title.length >= 8 && title.length < 200 && !seen[href]) {
              seen[href] = true;
              if (!/^(人民领袖|央视快评|天天学习|全景新闻|首页|更多|查看详情)\$/.test(title)) {
                links.push({title: title, url: href});
              }
            }
          });
          return JSON.stringify(links.slice(0, 30));
        })();
      ''');

      final text = result?.toString() ?? '';
      if (text.isEmpty) return [];

      final List<dynamic> parsed = json.decode(text);
      return parsed
          .whereType<Map>()
          .map((e) => Map<String, String>.from(e.cast<String, String>()))
          .toList();
    } catch (e) {
      return [];
    } finally {
      await headless.dispose();
    }
  }

  /// 加载 JS 页面并提取全部可见文本
  static Future<String> extractText(
    String url, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
    );

    try {
      await headless.run();
      await Future.delayed(const Duration(seconds: 5));

      final ctrl = headless.webViewController;
      if (ctrl == null) return '';
      final result = await ctrl.evaluateJavascript(
        source: 'document.body.innerText',
      );

      return result?.toString() ?? '';
    } catch (e) {
      return '';
    } finally {
      await headless.dispose();
    }
  }
}
