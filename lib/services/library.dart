import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_book_reader/flutter_book_reader.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book_meta.dart';
import 'txt_parser.dart';

/// 书架、本地文件与阅读进度的统一管理（单例）。
///
/// 全部数据保存在应用文档目录的 yequ_reader/ 下：
/// - library.json：书架元数据（含章节偏移）
/// - progress.json：每本书的阅读位置
/// - books/[id].txt：原始 TXT 文件
class Library {
  Library._();
  static final Library instance = Library._();

  late final Directory _dir;
  late final Directory _booksDir;

  final List<BookMeta> books = <BookMeta>[];
  final Map<String, ReadingPosition> _progress = <String, ReadingPosition>{};

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final Directory base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}${Platform.pathSeparator}yequ_reader');
    _booksDir = Directory('${_dir.path}${Platform.pathSeparator}books');
    _booksDir.createSync(recursive: true);
    _loadLibrary();
    _loadProgress();
    _initialized = true;
  }

  // —— 书架 ——

  void _loadLibrary() {
    final File f = File('${_dir.path}${Platform.pathSeparator}library.json');
    if (!f.existsSync()) return;
    try {
      final List<dynamic> list =
          jsonDecode(f.readAsStringSync()) as List<dynamic>;
      books
        ..clear()
        ..addAll(
          list.map((dynamic e) => BookMeta.fromJson(e as Map<String, dynamic>)),
        );
      books.sort(
        (BookMeta a, BookMeta b) => b.importedAt.compareTo(a.importedAt),
      );
    } catch (_) {
      // 元数据损坏不影响启动，按空书架处理。
    }
  }

  Future<void> _saveLibrary() async {
    final File f = File('${_dir.path}${Platform.pathSeparator}library.json');
    final String data = jsonEncode(
      books.map((BookMeta b) => b.toJson()).toList(),
    );
    await f.writeAsString(data, flush: true);
  }

  /// 计算字节内容指纹（FNV-1a 64bit），用于重复导入校验。
  /// 非加密强度，但速度快、碰撞概率可忽略。
  static String contentFingerprint(Uint8List bytes) {
    // 2^64 取模靠 Dart 的 64 位掩码实现。
    const int mask = 0xFFFFFFFFFFFFFFFF;
    int hash = 0xCBF29CE484222325;
    for (final int b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001B3) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// 查找内容完全相同的已导入书籍（字节数 + 内容指纹）。
  /// 老版本导入的书没有持久化指纹，这里读取其正文文件即时计算（不回写）。
  BookMeta? findDuplicate(int fileSize, String contentHash) {
    if (contentHash.isEmpty) return null;
    for (final BookMeta b in books) {
      String other = b.contentHash;
      if (other.isEmpty) {
        final File f = File(
          '${_booksDir.path}${Platform.pathSeparator}${b.fileName}',
        );
        if (!f.existsSync()) continue;
        try {
          other = contentFingerprint(f.readAsBytesSync());
        } catch (_) {
          continue;
        }
      }
      final bool sizeOk =
          fileSize == 0 || b.fileSize == 0 || fileSize == b.fileSize;
      if (other == contentHash && sizeOk) return b;
    }
    return null;
  }

  /// 导入一本 TXT：识别编码、切分章节、拷贝文件并登记到书架。
  Future<BookMeta> importBytes({
    required String originalName,
    required Uint8List bytes,
  }) async {
    final TxtDecodeResult decoded = decodeTxt(bytes);
    final List<ChapterInfo> chapters = parseChapters(decoded.text);

    final String id = DateTime.now().microsecondsSinceEpoch.toString();
    final String fileName = '$id.txt';
    await File(
      '${_booksDir.path}${Platform.pathSeparator}$fileName',
    ).writeAsBytes(bytes, flush: true);

    String title = originalName;
    final int dot = title.lastIndexOf('.');
    if (dot > 0) title = title.substring(0, dot);

    final BookMeta meta = BookMeta(
      id: id,
      title: title,
      fileName: fileName,
      encoding: decoded.encoding,
      chapters: chapters,
      importedAt: DateTime.now(),
      fileSize: bytes.length,
      contentHash: contentFingerprint(bytes),
    );
    books.insert(0, meta);
    await _saveLibrary();
    return meta;
  }

  /// 删除书籍登记信息与阅读进度。
  /// [deleteFile] 为 true 时一并删除已拷贝到应用目录的正文文件；
  /// 为 false 时仅移出书架（正文文件保留，之后可重新导入）。
  Future<void> removeBook(BookMeta book, {bool deleteFile = true}) async {
    if (deleteFile) {
      final File f = File(
        '${_booksDir.path}${Platform.pathSeparator}${book.fileName}',
      );
      if (f.existsSync()) f.deleteSync();
    }
    books.removeWhere((BookMeta b) => b.id == book.id);
    _progress.remove(book.id);
    await _saveLibrary();
    await _saveProgress();
  }

  /// 读取某本书的全文（按导入时识别出的编码解码）。
  Future<String> loadText(BookMeta book) async {
    final Uint8List bytes = await File(
      '${_booksDir.path}${Platform.pathSeparator}${book.fileName}',
    ).readAsBytes();
    return decodeWith(bytes, book.encoding);
  }

  // —— 阅读进度 ——

  void _loadProgress() {
    final File f = File('${_dir.path}${Platform.pathSeparator}progress.json');
    if (!f.existsSync()) return;
    try {
      final Map<String, dynamic> data =
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      _progress
        ..clear()
        ..addAll(
          data.map(
            (String k, dynamic v) => MapEntry<String, ReadingPosition>(
              k,
              ReadingPosition.fromJson(v as Map<String, dynamic>),
            ),
          ),
        );
    } catch (_) {
      // 忽略损坏的进度文件。
    }
  }

  Future<void> _saveProgress() async {
    final File f = File('${_dir.path}${Platform.pathSeparator}progress.json');
    final Map<String, dynamic> data = _progress.map(
      (String k, ReadingPosition v) => MapEntry<String, dynamic>(k, v.toJson()),
    );
    await f.writeAsString(jsonEncode(data), flush: true);
  }

  ReadingPosition? getProgress(String bookId) => _progress[bookId];

  Future<void> saveProgress(String bookId, ReadingPosition position) async {
    _progress[bookId] = position;
    await _saveProgress();
  }
}
