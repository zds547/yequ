import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

/// 一个章节在全文中的位置（字符偏移）。
class ChapterInfo {
  const ChapterInfo({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final int start;
  final int end;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'start': start,
    'end': end,
  };

  factory ChapterInfo.fromJson(Map<String, dynamic> json) => ChapterInfo(
    title: json['title'] as String? ?? '',
    start: json['start'] as int? ?? 0,
    end: json['end'] as int? ?? 0,
  );
}

/// TXT 解码结果：[text] 为解码后的全文，[encoding] 为识别出的编码名称。
class TxtDecodeResult {
  const TxtDecodeResult(this.text, this.encoding);

  final String text;
  final String encoding;
}

const String kEncodingUtf8 = 'utf-8';
const String kEncodingGbk = 'gbk';
const String kEncodingUtf16le = 'utf-16le';
const String kEncodingUtf16be = 'utf-16be';

/// 识别 TXT 文件编码并解码为字符串。
///
/// 支持带 BOM 的 UTF-8 / UTF-16；无 BOM 时先尝试严格 UTF-8，
/// 失败则回退到中文 TXT 最常见的 GBK（纯 Dart 解码，无需原生支持）。
TxtDecodeResult decodeTxt(Uint8List bytes) {
  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return TxtDecodeResult(
      utf8.decode(bytes.sublist(3), allowMalformed: true),
      kEncodingUtf8,
    );
  }
  // UTF-16 LE/BE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return TxtDecodeResult(
      _decodeUtf16(bytes.sublist(2), littleEndian: true),
      kEncodingUtf16le,
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return TxtDecodeResult(
      _decodeUtf16(bytes.sublist(2), littleEndian: false),
      kEncodingUtf16be,
    );
  }
  try {
    return TxtDecodeResult(
      utf8.decode(bytes, allowMalformed: false),
      kEncodingUtf8,
    );
  } catch (_) {
    return TxtDecodeResult(
      const GbkCodec(allowInvalid: true).decode(bytes),
      kEncodingGbk,
    );
  }
}

/// 用已知编码名称解码（导入时识别出的编码会被保存下来，保证再次打开与首次一致）。
String decodeWith(Uint8List bytes, String encoding) {
  switch (encoding) {
    case kEncodingGbk:
      return const GbkCodec(allowInvalid: true).decode(bytes);
    case kEncodingUtf16le:
      return _decodeUtf16(bytes, littleEndian: true);
    case kEncodingUtf16be:
      return _decodeUtf16(bytes, littleEndian: false);
    case kEncodingUtf8:
    default:
      return utf8.decode(bytes, allowMalformed: true);
  }
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final ByteData data = ByteData.sublistView(bytes);
  final int charCount = bytes.lengthInBytes ~/ 2;
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < charCount; i++) {
    buffer.writeCharCode(
      data.getUint16(i * 2, littleEndian ? Endian.little : Endian.big),
    );
  }
  return buffer.toString();
}

/// 常见网文章节标题：独占一行，形如「第一章 标题」「第123章」「卷三」「楔子」「番外」。
final RegExp _chapterLine = RegExp(
  r'^\s{0,8}(?:'
  r'第\s*[0-9０-９零〇一二三四五六七八九十百千万两]{1,9}\s*[章节回卷集部篇][^\r\n]{0,40}'
  r'|卷\s*[0-９０-９零〇一二三四五六七八九十百千万两]{1,9}[^\r\n]{0,40}'
  r'|序章|序言|前言|引子|楔子|尾声|后记|番外[^\r\n]{0,20}'
  r')\s{0,8}$',
  multiLine: true,
);

/// 把全文切成章节。识别不到任何章节标题时，全书作为一章「正文」。
List<ChapterInfo> parseChapters(String text) {
  final List<RegExpMatch> matches = _chapterLine.allMatches(text).toList();
  if (matches.isEmpty) {
    return <ChapterInfo>[ChapterInfo(title: '正文', start: 0, end: text.length)];
  }

  final List<ChapterInfo> chapters = <ChapterInfo>[];

  // 第一章之前的内容（书名页 / 简介）单独成「前言」。
  final int firstStart = matches.first.start;
  if (firstStart > 0 && text.substring(0, firstStart).trim().isNotEmpty) {
    chapters.add(ChapterInfo(title: '前言', start: 0, end: firstStart));
  }

  for (int i = 0; i < matches.length; i++) {
    final RegExpMatch m = matches[i];
    final int end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    final String title = text
        .substring(m.start, m.end)
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    chapters.add(ChapterInfo(title: title, start: m.start, end: end));
  }
  return chapters;
}

/// 取出某章正文：去掉章节标题行，按段落整理，段落之间用 '\n' 分隔
/// （flutter_book_reader 约定）。
String chapterBody(String fullText, ChapterInfo chapter) {
  final String raw = fullText.substring(chapter.start, chapter.end);
  final List<String> lines = raw.split(RegExp(r'\r\n?|\n'));
  final List<String> paragraphs = <String>[];
  for (final String line in lines) {
    final String t = line.trim();
    if (t.isEmpty) continue;
    // 首段若是章节标题行（阅读器会用章题目录渲染页眉大标题），跳过避免重复。
    // 两边都压缩空白再比较，兼容源文件标题中多空格 / Tab 的情况。
    if (paragraphs.isEmpty &&
        t.replaceAll(RegExp(r'\s+'), '') ==
            chapter.title.replaceAll(RegExp(r'\s+'), '')) {
      continue;
    }
    paragraphs.add(t);
  }
  return paragraphs.join('\n');
}

/// 供 [compute] 在后台 isolate 执行「编码识别 + 章节切分」。
/// 这两步对大文件是 CPU 密集型，放在 isolate 可避免阻塞 UI 线程，
/// 让下载完成后书架能尽快响应。返回值为纯数据，可安全跨 isolate 传递。
class ParsedBook {
  const ParsedBook(this.decoded, this.chapters);

  final TxtDecodeResult decoded;
  final List<ChapterInfo> chapters;
}

/// 后台 isolate 入口：必须是顶级（或静态）函数、单参数。
ParsedBook parseBookInIsolate(Uint8List bytes) {
  final TxtDecodeResult decoded = decodeTxt(bytes);
  return ParsedBook(decoded, parseChapters(decoded.text));
}
