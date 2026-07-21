import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/cpp_native/bindings/danmaku_parser.dart';

String encodeDanmakuXmlText(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String decodeDanmakuXmlText(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

Map<String, dynamic> convertBilibiliXmlDanmakuToJson(String xmlContent) {
  // 优先使用 C++ 解析器（非 Web 平台）
  if (!kIsWeb) {
    try {
      final jsonStr = DanmakuParser.parseXml(xmlContent);
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final count = decoded['count'];
        // 防御性检查: 如果 C++ 返回 0 条弹幕但 XML 明显包含 <d 标签，
        // 可能是 FFI content_len 传错、XML 被截断等异常情况，
        // 应 fallback 到 Dart 而非返回空列表导致弹幕消失。
        if (count == 0 && xmlContent.contains('<d')) {
          final comments = parseBilibiliXmlDanmakuComments(xmlContent);
          return {'count': comments.length, 'comments': comments};
        }
        debugPrint('[DanmakuParser] [C++] [OK] convertBilibiliXml: '
            '${decoded['count']} comments via C++ path');
        return decoded;
      }
    } catch (_) {
      debugPrint('[DanmakuParser] [C++] [ERR] convertBilibiliXml: '
          'C++ exception, falling back to Dart');
    }
  }
  // Fallback: 原 Dart 实现
  final comments = parseBilibiliXmlDanmakuComments(xmlContent);
  return {
    'count': comments.length,
    'comments': comments,
  };
}

List<Map<String, dynamic>> parseBilibiliXmlDanmakuComments(String xmlContent) {
  try {
    final document = XmlDocument.parse(xmlContent);
    final comments = <Map<String, dynamic>>[];

    for (final element in document.findAllElements('d')) {
      final parsedComment = _buildBilibiliDanmakuComment(
        pAttr: element.getAttribute('p') ?? '',
        rawTextContent: element.innerText,
      );
      if (parsedComment != null) {
        comments.add(parsedComment);
      }
    }

    if (comments.isNotEmpty || !xmlContent.contains('<d')) {
      return comments;
    }
  } on XmlParserException {
    // Fall back to a more tolerant parser for slightly malformed exports.
  }

  final comments = <Map<String, dynamic>>[];
  final danmakuRegex = RegExp(
    r'<d\b[^>]*\bp="([^"]+)"[^>]*>([\s\S]*?)</d>',
    caseSensitive: false,
  );

  for (final match in danmakuRegex.allMatches(xmlContent)) {
    final parsedComment = _buildBilibiliDanmakuComment(
      pAttr: match.group(1) ?? '',
      rawTextContent: match.group(2) ?? '',
    );
    if (parsedComment != null) {
      comments.add(parsedComment);
    }
  }

  return comments;
}

Map<String, dynamic>? _buildBilibiliDanmakuComment({
  required String pAttr,
  required String rawTextContent,
}) {
  try {
    final textContent = decodeDanmakuXmlText(rawTextContent);
    if (textContent.isEmpty) return null;

    final pParams = pAttr.split(',');
    if (pParams.length < 4) return null;

    final time = double.tryParse(pParams[0]) ?? 0.0;
    final typeCode = int.tryParse(pParams[1]) ?? 1;
    final fontSize = int.tryParse(pParams[2]) ?? 25;
    final colorCode = int.tryParse(pParams[3]) ?? 16777215;

    final danmakuType = DanmakuMode.fromCode(typeCode).typeName;

    final r = (colorCode >> 16) & 0xFF;
    final g = (colorCode >> 8) & 0xFF;
    final b = colorCode & 0xFF;
    final color = 'rgb($r,$g,$b)';

    // 可选字段: timestamp, senderId, cid
    final timestamp = pParams.length > 4 ? int.tryParse(pParams[4]) : null;
    final senderId = pParams.length > 6 ? pParams[6].trim() : '';
    final danmakuId = pParams.length > 7 ? pParams[7].trim() : '';

    return {
      't': time,
      'c': textContent,
      'y': danmakuType,
      'r': color,
      'fontSize': fontSize,
      'originalType': typeCode,

      if (timestamp != null && timestamp > 0) 'timestamp': timestamp,
      if (senderId.isNotEmpty && senderId != '0') 'senderId': senderId,
      if (danmakuId.isNotEmpty && danmakuId != '0') 'cid': danmakuId,
      'source': 'bilibili', // 标记来源, 便于后续处理
    };
  } catch (_) {
    return null;
  }
}

int parseDanmakuColorToInt(dynamic colorValue) {
  if (colorValue == null) return 0xFFFFFF;

  if (colorValue is int) return colorValue & 0xFFFFFF;
  if (colorValue is num) return colorValue.toInt() & 0xFFFFFF;

  final text = colorValue.toString().trim();
  if (text.isEmpty) return 0xFFFFFF;

  final rgbMatch = RegExp(
    r'rgb\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)',
    caseSensitive: false,
  ).firstMatch(text);
  if (rgbMatch != null) {
    final r = int.tryParse(rgbMatch.group(1) ?? '') ?? 255;
    final g = int.tryParse(rgbMatch.group(2) ?? '') ?? 255;
    final b = int.tryParse(rgbMatch.group(3) ?? '') ?? 255;
    return (_clampColorComponent(r) << 16) |
        (_clampColorComponent(g) << 8) |
        _clampColorComponent(b);
  }

  if (text.startsWith('#')) {
    var hex = text.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    } else if (hex.length == 8) {
      hex = hex.substring(2);
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return parsed & 0xFFFFFF;
  }

  if (text.startsWith('0x') || text.startsWith('0X')) {
    final parsed = int.tryParse(text.substring(2), radix: 16);
    if (parsed != null) return parsed & 0xFFFFFF;
  }

  final parsed = int.tryParse(text);
  if (parsed != null) return parsed & 0xFFFFFF;

  return 0xFFFFFF;
}

int _clampColorComponent(int value) {
  return value.clamp(0, 255).toInt();
}

/// 将弹幕评论列表转换为 Bilibili XML 格式字符串。
///
/// 每条评论支持以下字段（兼容多种命名）：
/// - `t` / `time`: 出现时间（秒）
/// - `c` / `content`: 弹幕文本
/// - `y` / `type` / `originalType`: 弹幕类型
/// - `r` / `color`: 颜色（rgb 字符串或 hex）
/// - `fontSize` / `size` / `fontsize`: 字号
/// - `timestamp` / `d`: 时间戳
String convertDanmakuCommentsToBilibiliXml(List<dynamic> comments) {
  final buffer = StringBuffer();
  buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buffer.writeln('<i>');

  for (final raw in comments) {
    if (raw is! Map) continue;
    final item = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw);

    final content = (item['content'] ?? item['c'] ?? '').toString();
    if (content.isEmpty) continue;

    // 时间（秒）
    final timeValue = _resolveDouble(item['time'] ?? item['t']);
    final timeText = _formatDanmakuTime(timeValue);

    // 类型码
    final typeCode = _resolveTypeCode(item);

    // 字号
    final fontSize = _resolveFontSize(item);

    // 颜色码
    final colorCode = parseDanmakuColorToInt(item['color'] ?? item['r']);

    // 时间戳
    final timestamp = _resolveTimestamp(item);

    final escaped = encodeDanmakuXmlText(content);
    buffer.writeln(
      '<d p="$timeText,$typeCode,$fontSize,$colorCode,$timestamp,0,0,0">$escaped</d>',
    );
  }

  buffer.writeln('</i>');
  return buffer.toString();
}

double _resolveDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

int _resolveTypeCode(Map<String, dynamic> item) {
  final originalType = item['originalType'];
  if (originalType is num) {
    final code = originalType.toInt();
    if (code > 0) return code;
  }
  final typeValue = item['type'] ?? item['y'];
  if (typeValue is num) {
    final code = typeValue.toInt();
    if (code > 0) return code;
  }
  final typeText = typeValue?.toString().toLowerCase();
  switch (typeText) {
    case 'top':
      return DanmakuMode.top.code;
    case 'bottom':
      return DanmakuMode.bottom.code;
    case 'scroll':
    case 'right':
      return DanmakuMode.scroll.code;
    default:
      return DanmakuMode.scroll.code;
  }
}

int _resolveFontSize(Map<String, dynamic> item) {
  final sizeValue = item['fontSize'] ?? item['size'] ?? item['fontsize'];
  if (sizeValue is num) return sizeValue.round();
  if (sizeValue is String) {
    final parsed = double.tryParse(sizeValue);
    if (parsed != null) return parsed.round();
  }
  return 25;
}

int _resolveTimestamp(Map<String, dynamic> item) {
  final value = item['timestamp'] ?? item['d'];
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _formatDanmakuTime(double value) {
  if (value.isNaN || value.isInfinite) return '0';
  final safeValue = value < 0 ? 0.0 : value;
  final text = safeValue.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
