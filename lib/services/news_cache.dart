/// 跨平台缓存 — 条件导出
export 'news_cache_stub.dart'
    if (dart.library.io) 'news_cache_io.dart';

// readAndCleanNewsCache 通过条件导出自动包含
