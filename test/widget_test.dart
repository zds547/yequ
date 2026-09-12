import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yequ/services/txt_parser.dart';

void main() {
  test('按章节标题切分全文', () {
    const String text =
        '书名简介\r\n\r\n第一章 初入江湖\r\n正文第一段。\r\n正文第二段。\r\n'
        '第二章 风波再起\r\n这一章讲了许多事。\r\n'
        '第三回 大结局\r\n完结。';

    final List<ChapterInfo> chapters = parseChapters(text);

    expect(chapters.length, 4);
    expect(chapters[0].title, '前言');
    expect(chapters[1].title, '第一章 初入江湖');
    expect(chapters[2].title, '第二章 风波再起');
    expect(chapters[3].title, '第三回 大结局');

    final String body = chapterBody(text, chapters[1]);
    expect(body.contains('第一章'), isFalse);
    expect(body.split('\n'), <String>['正文第一段。', '正文第二段。']);
  });

  test('识别不到标题时全书为一章', () {
    const String text = '这是一本没有章节标题的小说。\n第二段。';
    final List<ChapterInfo> chapters = parseChapters(text);
    expect(chapters.length, 1);
    expect(chapters.single.title, '正文');
    expect(chapterBody(text, chapters.single), contains('这是一本'));
    expect(chapterBody(text, chapters.single), contains('第二段'));
  });

  test('无 BOM 的 UTF-8 正常解码', () {
    final Uint8List bytes = Uint8List.fromList(utf8.encode('第一章 测试\n中文内容'));
    final TxtDecodeResult r = decodeTxt(bytes);
    expect(r.encoding, kEncodingUtf8);
    expect(r.text, contains('中文内容'));
  });

  test('GBK 文件回退解码', () {
    // "第一章 测试" 的 GBK 字节（enough_convert 纯 Dart 编码）。
    final Uint8List bytes = Uint8List.fromList(gbk.encode('第一章 测试'));
    final TxtDecodeResult r = decodeTxt(bytes);
    expect(r.encoding, kEncodingGbk);
    expect(r.text, '第一章 测试');
  });
}
