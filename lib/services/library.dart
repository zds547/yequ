import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// 手动创建、当前可能没有任何书籍的分类，单独持久化在 categories.json。
  /// 有书的分类本就可从书籍派生，这里只补「空分类」这部分，取并集展示。
  final List<String> _manualCategories = <String>[];

  /// 书架上次的分类筛选：null = 全部，'' = 未分类，其余为分类名。
  /// 持久化在 shelf_prefs.json，启动时恢复。
  String? _preferredFilter;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final Directory base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}${Platform.pathSeparator}yequ_reader');
    _booksDir = Directory('${_dir.path}${Platform.pathSeparator}books');
    _booksDir.createSync(recursive: true);
    _loadLibrary();
    _loadProgress();
    _loadCategories();
    _loadPrefs();
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
  /// [category] 为分组名，空串放入「未分类」。
  Future<BookMeta> importBytes({
    required String originalName,
    required Uint8List bytes,
    String category = '',
  }) async {
    // 编码识别 + 章节切分放到后台 isolate，避免大文件阻塞 UI。
    final ParsedBook parsed = await compute(parseBookInIsolate, bytes);

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
      encoding: parsed.decoded.encoding,
      chapters: parsed.chapters,
      importedAt: DateTime.now(),
      fileSize: bytes.length,
      contentHash: contentFingerprint(bytes),
      category: category.trim(),
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

  // —— 分类（单分组模型：空分类持久化，有书的分类由书籍派生，取并集） ——

  void _loadCategories() {
    final File f = File('${_dir.path}${Platform.pathSeparator}categories.json');
    if (!f.existsSync()) return;
    try {
      final List<dynamic> list =
          jsonDecode(f.readAsStringSync()) as List<dynamic>;
      _manualCategories
        ..clear()
        ..addAll(
          list
              .map((dynamic e) => (e as String).trim())
              .where((String s) => s.isNotEmpty),
        );
    } catch (_) {
      // 分类文件损坏不影响启动。
    }
  }

  Future<void> _saveCategories() async {
    final File f = File('${_dir.path}${Platform.pathSeparator}categories.json');
    await f.writeAsString(jsonEncode(_manualCategories), flush: true);
  }

  /// 全部自定义分类：先列手动创建的（可能暂无书籍），再补由书籍派生的新名字。
  List<String> get categories {
    final Set<String> seen = <String>{};
    final List<String> ordered = <String>[];
    for (final String c in _manualCategories) {
      if (seen.add(c)) ordered.add(c);
    }
    for (final BookMeta b in books) {
      if (b.category.isNotEmpty && seen.add(b.category)) {
        ordered.add(b.category);
      }
    }
    return ordered;
  }

  /// 手动新建分类（允许暂时没有书）。重名或空名返回 false。
  Future<bool> createCategory(String name) async {
    final String target = name.trim();
    if (target.isEmpty || categories.contains(target)) return false;
    _manualCategories.add(target);
    await _saveCategories();
    return true;
  }

  int countOfCategory(String category) =>
      books.where((BookMeta b) => b.category == category).length;

  /// 把一本书移动到指定分类（空串为未分类）。
  Future<void> setCategory(BookMeta book, String category) async {
    final String target = category.trim();
    final int i = books.indexWhere((BookMeta b) => b.id == book.id);
    if (i < 0 || books[i].category == target) return;
    books[i] = books[i].copyWith(category: target);
    await _saveLibrary();
  }

  /// 重命名分类：该分类下所有书与空分类登记一并更新。返回受影响的书籍数
  /// （空分类时书籍数为 0 但仍可能完成重命名）。
  /// 注意 [newName] 允许为空串——那是 [deleteCategory] 在把书移到未分类；
  /// 但 UI 层的重命名对话框会拒绝空名。
  Future<int> renameCategory(String oldName, String newName) async {
    final String target = newName.trim();
    if (oldName.isEmpty || oldName == target) return 0;
    int changed = 0;
    for (int i = 0; i < books.length; i++) {
      if (books[i].category == oldName) {
        books[i] = books[i].copyWith(category: target);
        changed++;
      }
    }
    final int mi = _manualCategories.indexOf(oldName);
    if (mi >= 0) {
      if (target.isEmpty) {
        _manualCategories.removeAt(mi);
      } else {
        _manualCategories[mi] = target;
      }
    }
    if (changed > 0) await _saveLibrary();
    if (mi >= 0) await _saveCategories();
    return changed;
  }

  /// 删除分类：从空分类登记中移除，其下书籍回到「未分类」。
  Future<int> deleteCategory(String name) => renameCategory(name, '');

  // —— 书架偏好（记住上次的分类筛选） ——

  void _loadPrefs() {
    final File f = File(
      '${_dir.path}${Platform.pathSeparator}shelf_prefs.json',
    );
    if (!f.existsSync()) return;
    try {
      final Map<String, dynamic> data =
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final dynamic v = data['categoryFilter'];
      if (v == null || v is String) _preferredFilter = v as String?;
    } catch (_) {
      // 偏好文件损坏不影响启动，按「全部」处理。
    }
  }

  String? get preferredFilter => _preferredFilter;

  /// 记住书架当前选中的分类筛选，重启后恢复。
  Future<void> setPreferredFilter(String? filter) async {
    if (_preferredFilter == filter) return;
    _preferredFilter = filter;
    final File f = File(
      '${_dir.path}${Platform.pathSeparator}shelf_prefs.json',
    );
    await f.writeAsString(
      jsonEncode(<String, dynamic>{'categoryFilter': filter}),
      flush: true,
    );
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
