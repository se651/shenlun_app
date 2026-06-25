/// OCR 识图服务
/// 通过 DeepSeek Vision API 提取图片中的文字
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class OcrService {
  static const _endpoint = 'https://api.deepseek.com/v1/chat/completions';
  static const _model = 'deepseek-chat';

  /// 从图片路径提取文字，返回提取结果；失败返回 null
  static Future<String?> extractText({
    required String imagePath,
    required String apiKey,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);

      // 根据扩展名确定 MIME
      final ext = imagePath.split('.').last.toLowerCase();
      final mime = switch (ext) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };

      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': '请提取图片中的所有文字内容，保持原有的段落结构和格式。只输出提取的文字，不要添加任何额外说明。如果图片中没有文字，请回复"未检测到文字"。',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:$mime;base64,$base64',
                  },
                },
              ],
            },
          ],
          'temperature': 0.1,
          'max_tokens': 2000,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content == '未检测到文字') return null;

      return content.trim();
    } catch (_) {
      return null;
    }
  }
}
