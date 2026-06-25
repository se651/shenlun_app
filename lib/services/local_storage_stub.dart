/// Web 端 localStorage 读写
import 'dart:html' as html;

String storageGet(String key) {
  return html.window.localStorage[key] ?? '';
}

void storageSet(String key, String value) {
  html.window.localStorage[key] = value;
}
