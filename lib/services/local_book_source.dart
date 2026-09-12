import 'dart:ui';

import 'package:flutter_book_reader/flutter_book_reader.dart';

import '../models/book_meta.dart';
import 'library.dart';
import 'txt_parser.dart';

/// 本地 TXT 书籍的 [BookSource] 实现：目录来自导入时解析的章节，
/// 正文首次需要时从文件读取并缓存（阅读器内部还有 LRU 章级缓存）。
class LocalBookSource extends BookSource {
  LocalBookSource(this.book);

  final BookMeta book;

  String? _text;
  Future<String>? _loading;

  @override
  Future<BookManifest> loadManifest() async => BookManifest(
        id: book.id,
        title: book.title,
        author: '',
        intro: '本地 TXT · ${book.chapterCount} 章',
        coverColor: _coverColor(book.title),
        chapterTitles:
            book.chapters.map((ChapterInfo c) => c.title).toList(),
      );

  @override
  Future<String> loadChapterBody(int chapterIndex) async {
    if (_text == null) {
      // 防止相邻章预取时重复读文件。
      _loading ??= Library.instance.loadText(book);
      _text = await _loading;
    }
    return chapterBody(_text!, book.chapters[chapterIndex]);
  }

  /// 按书名取一个稳定的封面色。
  static Color _coverColor(String title) {
    const List<Color> palette = <Color>[
      Color(0xFF8D6E63),
      Color(0xFF5C6BC0),
      Color(0xFF26A69A),
      Color(0xFFEC8067),
      Color(0xFF7E57C2),
      Color(0xFF5C8DBC),
      Color(0xFF9E7B4F),
    ];
    if (title.isEmpty) return palette.first;
    return palette[title.hashCode.abs() % palette.length];
  }
}
