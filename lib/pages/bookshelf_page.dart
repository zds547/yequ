import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_book_reader/flutter_book_reader.dart';

import '../models/book_meta.dart';
import '../services/library.dart';
import 'reader_page.dart';

/// 书架页配色：墨蓝 + 宣纸 + 金，呼应启动页与图标。
class _ShelfStyle {
  static const Color appBar = Color(0xFF16224E);
  static const Color paper = Color(0xFFF5F1E9);
  static const Color card = Color(0xFFFFFDF8);
  static const Color ink = Color(0xFF23284A);
  static const Color muted = Color(0xFF948D7C);
  static const Color gold = Color(0xFFD8B25E);
  static const Color danger = Color(0xFFB24A44);
}

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final Library _library = Library.instance;
  bool _importing = false;

  Future<void> _importBook() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final PlatformFile? picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['txt'],
      );
      if (picked == null) return;

      final Uint8List bytes = await picked.readAsBytes();

      // 重复导入校验：同一文件已在书架时，询问打开而不是再导入一份。
      final String hash = Library.contentFingerprint(bytes);
      final BookMeta? existing = _library.findDuplicate(bytes.length, hash);
      if (existing != null) {
        await _showDuplicateDialog(existing);
        return;
      }

      final BookMeta meta = await _library.importBytes(
        originalName: picked.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {});
      _showToast('已导入《${meta.title}》');
    } catch (e) {
      _showToast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showDuplicateDialog(BookMeta existing) async {
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: _ShelfStyle.card,
        title: const Text('这本书已在书架中'),
        content: Text('《${existing.title}》之前已导入，无需重复添加。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('关闭'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _ShelfStyle.appBar),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('打开本书'),
          ),
        ],
      ),
    );
    if (open == true && mounted) {
      await _openBook(existing);
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openBook(BookMeta book) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReaderPage(book: book)));
    // 阅读页返回后刷新续读信息。
    if (mounted) setState(() {});
  }

  Future<void> _askRemove(BookMeta book) async {
    final int? choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _ShelfStyle.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 14),
            Text(
              '《${book.title}》',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _ShelfStyle.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '选择删除方式',
              style: TextStyle(fontSize: 12, color: _ShelfStyle.muted),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.library_books_outlined,
                color: _ShelfStyle.appBar,
              ),
              title: const Text('仅移出书架'),
              subtitle: const Text('保留已导入的本地文件与正文，可重新导入'),
              onTap: () => Navigator.of(ctx).pop(1),
            ),
            ListTile(
              iconColor: _ShelfStyle.danger,
              textColor: _ShelfStyle.danger,
              leading: const Icon(Icons.delete_outline),
              title: const Text('移出书架并删除本地文件'),
              subtitle: const Text(
                '正文文件与阅读进度不可恢复',
                style: TextStyle(color: _ShelfStyle.muted),
              ),
              onTap: () => Navigator.of(ctx).pop(2),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Center(child: Text('取消')),
              onTap: () => Navigator.of(ctx).pop(0),
            ),
          ],
        ),
      ),
    );
    if (choice == null || choice == 0) return;

    if (choice == 2) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          backgroundColor: _ShelfStyle.card,
          title: const Text('删除本地文件？'),
          content: Text('《${book.title}》的正文文件和阅读进度将被永久删除，无法恢复。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                '永久删除',
                style: TextStyle(color: _ShelfStyle.danger),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _library.removeBook(book, deleteFile: choice == 2);
    if (mounted) {
      setState(() {});
      _showToast(choice == 2 ? '已删除《${book.title}》' : '已将《${book.title}》移出书架');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<BookMeta> books = _library.books;
    return Scaffold(
      backgroundColor: _ShelfStyle.paper,
      appBar: AppBar(
        title: const Text('书架'),
        backgroundColor: _ShelfStyle.appBar,
        foregroundColor: const Color(0xFFF4ECD8),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _importBook,
        backgroundColor: _ShelfStyle.appBar,
        foregroundColor: _ShelfStyle.gold,
        elevation: 2,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _ShelfStyle.gold,
                ),
              )
            : const Icon(Icons.add),
        label: Text(_importing ? '导入中…' : '导入 TXT'),
      ),
      body: books.isEmpty ? _buildEmpty() : _buildGrid(books),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.menu_book_outlined, size: 72, color: _ShelfStyle.gold),
        const SizedBox(height: 16),
        Text(
          '书架空空如也',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: _ShelfStyle.ink),
        ),
        const SizedBox(height: 8),
        const Text(
          '点击下方按钮导入本地 TXT 小说',
          style: TextStyle(color: _ShelfStyle.muted),
        ),
      ],
    ),
  );

  Widget _buildGrid(List<BookMeta> books) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 2.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (BuildContext context, int i) =>
          _BookCard(book: books[i], onTap: _openBook, onLongPress: _askRemove),
    );
  }
}

/// 书架卡片：左侧色块"封面" + 书名 + 续读章节。
class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });

  final BookMeta book;
  final ValueChanged<BookMeta> onTap;
  final ValueChanged<BookMeta> onLongPress;

  @override
  Widget build(BuildContext context) {
    final ReadingPosition? pos = Library.instance.getProgress(book.id);
    final String subtitle = pos == null
        ? '共 ${book.chapterCount} 章 · 未读'
        : '续读 · ${_short(_chapterTitle(pos.chapterIndex), 12)}';
    final Color cover = coverColor(book.title);

    return Card(
      color: _ShelfStyle.card,
      elevation: 1.2,
      shadowColor: const Color(0x3316224E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(book),
        onLongPress: () => onLongPress(book),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              AspectRatio(
                aspectRatio: 0.72,
                child: Container(
                  decoration: BoxDecoration(
                    color: cover,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    book.title.isNotEmpty ? book.title.characters.first : '书',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _ShelfStyle.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        if (pos != null)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.bookmark,
                              size: 13,
                              color: _ShelfStyle.gold,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _ShelfStyle.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _chapterTitle(int index) {
    if (index < 0 || index >= book.chapters.length) return '';
    return book.chapters[index].title;
  }

  static String _short(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// 沉稳的低饱和封面色，与墨蓝/金主色协调。
  static Color coverColor(String title) {
    const List<Color> palette = <Color>[
      Color(0xFF3F5393), // 靛蓝
      Color(0xFF2F6E6B), // 松绿
      Color(0xFF8C4A52), // 绛红
      Color(0xFFB08948), // 赭金
      Color(0xFF4A6579), // 黛蓝
      Color(0xFF6E4B7A), // 紫檀
      Color(0xFF4E6E50), // 苔绿
    ];
    if (title.isEmpty) return palette.first;
    return palette[title.hashCode.abs() % palette.length];
  }
}
