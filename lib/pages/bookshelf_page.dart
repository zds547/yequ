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

  /// 当前分类筛选：null = 全部，'' = 未分类，其余为具体分类名。
  String? _filter;

  @override
  void initState() {
    super.initState();
    // 恢复上次的分类筛选；分类可能已被删除，无效时回退「全部」。
    final String? saved = _library.preferredFilter;
    if (saved == null || saved.isEmpty || _library.categories.contains(saved)) {
      _filter = saved;
    }
  }

  /// 切换分类筛选并持久化，下次启动自动恢复。
  void _applyFilter(String? f) {
    setState(() => _filter = f);
    _library.setPreferredFilter(f);
  }

  /// 导入本地 TXT，支持一次选择多本：逐本读取、指纹查重，最后汇总提示。
  Future<void> _importBooks() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      // pickFiles 在 Android SAF 上原生支持多选；取消选择时返回空列表。
      final List<PlatformFile> picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['txt'],
      );
      if (picked.isEmpty || !mounted) return;

      final List<String> imported = <String>[];
      final Map<String, BookMeta> duplicates = <String, BookMeta>{};
      int failed = 0;
      for (final PlatformFile file in picked) {
        try {
          final Uint8List bytes = await file.readAsBytes();
          final String hash = Library.contentFingerprint(bytes);
          final BookMeta? existing = _library.findDuplicate(bytes.length, hash);
          if (existing != null) {
            // 同一批里重复选到同一本书时只计一次。
            duplicates[existing.id] = existing;
            continue;
          }
          final BookMeta meta = await _library.importBytes(
            originalName: file.name,
            bytes: bytes,
            // 在某个分类页下导入时自动归入该分类；「全部 / 未分类」下归入未分类。
            category: _filter ?? '',
          );
          imported.add(meta.title);
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      setState(() {});

      // 仅选了一本且命中重复：沿用「询问打开」的交互；其余情况汇总提示。
      if (picked.length == 1 &&
          imported.isEmpty &&
          failed == 0 &&
          duplicates.length == 1) {
        await _showDuplicateDialog(duplicates.values.single);
        return;
      }

      final List<String> summary = <String>[];
      if (imported.length == 1) {
        summary.add('已导入《${imported.single}》');
      } else if (imported.length > 1) {
        summary.add('成功导入 ${imported.length} 本');
      }
      if (duplicates.isNotEmpty) {
        summary.add('跳过已在书架的 ${duplicates.length} 本');
      }
      if (failed > 0) summary.add('$failed 本导入失败');
      if (summary.isNotEmpty) _showToast(summary.join('，'));
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
              '整理这本书',
              style: TextStyle(fontSize: 12, color: _ShelfStyle.muted),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.drive_file_move_outline,
                color: _ShelfStyle.appBar,
              ),
              title: const Text('移动到分类'),
              subtitle: Text(
                book.category.isEmpty ? '当前：未分类' : '当前：${book.category}',
                style: const TextStyle(color: _ShelfStyle.muted),
              ),
              onTap: () => Navigator.of(ctx).pop(3),
            ),
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

    if (choice == 3) {
      await _pickCategory(book);
      return;
    }

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

  /// 右上角菜单直接新建空分类：创建后筛选条立即出现，长按书籍即可往里移动。
  Future<void> _createCategory() async {
    final String? name = await _askCategoryName(title: '新建分类');
    if (name == null || !mounted) return;
    final bool ok = await _library.createCategory(name);
    if (!mounted) return;
    if (ok) {
      setState(() {});
      _showToast('已新建分类「$name」，可在书籍上长按移入');
    } else {
      _showToast('分类「$name」已存在');
    }
  }

  /// 选择目标分类（含「未分类」与「新建分类」）。
  Future<void> _pickCategory(BookMeta book) async {
    final String? target = await showModalBottomSheet<String>(
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
            const Text(
              '移动到分类',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _ShelfStyle.ink,
              ),
            ),
            const SizedBox(height: 8),
            _categoryTile(ctx, '', book.category.isEmpty, Icons.inbox_outlined),
            for (final String c in _library.categories)
              _categoryTile(ctx, c, book.category == c, Icons.folder_outlined),
            ListTile(
              leading: const Icon(
                Icons.create_new_folder_outlined,
                color: _ShelfStyle.gold,
              ),
              title: const Text('新建分类'),
              onTap: () => Navigator.of(ctx).pop('__new__'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;

    String name = target;
    if (target == '__new__') {
      final String? created = await _askCategoryName(title: '新建分类');
      if (created == null || !mounted) return;
      name = created;
    }
    await _library.setCategory(book, name);
    if (!mounted) return;
    setState(() {});
    _showToast(
      name.isEmpty ? '已将《${book.title}》移到未分类' : '已将《${book.title}》移到「$name」',
    );
  }

  Widget _categoryTile(
    BuildContext ctx,
    String name,
    bool selected,
    IconData icon,
  ) {
    return ListTile(
      leading: Icon(icon, color: _ShelfStyle.appBar),
      title: Text(name.isEmpty ? '未分类' : name),
      trailing: selected
          ? const Icon(Icons.check, color: _ShelfStyle.gold)
          : null,
      onTap: () => Navigator.of(ctx).pop(name),
    );
  }

  /// 文本输入对话框：新建分类或重命名。返回去重后的名字，取消返回 null。
  Future<String?> _askCategoryName({
    required String title,
    String initial = '',
  }) async {
    final TextEditingController ctrl = TextEditingController(text: initial);
    final Set<String> existing = _library.categories.toSet();
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        String? error;
        return StatefulBuilder(
          builder: (BuildContext ctx, void Function(void Function()) setSt) {
            void submit() {
              final String v = ctrl.text.trim();
              if (v.isEmpty) {
                setSt(() => error = '分类名不能为空');
                return;
              }
              if (v != initial && existing.contains(v)) {
                setSt(() => error = '已存在同名分类');
                return;
              }
              Navigator.of(ctx).pop(v);
            }

            return AlertDialog(
              backgroundColor: _ShelfStyle.card,
              title: Text(title),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 12,
                decoration: InputDecoration(
                  hintText: '输入分类名（最多 12 字）',
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _ShelfStyle.appBar,
                  ),
                  onPressed: submit,
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 分类管理：新建 / 重命名 / 删除（删除后书籍回到未分类）。
  Future<void> _manageCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ShelfStyle.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setSt) {
          final List<String> cats = _library.categories;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 14),
                const Text(
                  '分类管理',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _ShelfStyle.ink,
                  ),
                ),
                const SizedBox(height: 8),
                if (cats.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      '还没有自定义分类\n点下方「新建分类」即可创建',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _ShelfStyle.muted, fontSize: 13),
                    ),
                  ),
                for (final String c in cats)
                  ListTile(
                    leading: const Icon(
                      Icons.folder_outlined,
                      color: _ShelfStyle.appBar,
                    ),
                    title: Text(c),
                    subtitle: Text('${_library.countOfCategory(c)} 本'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: '重命名',
                          icon: const Icon(
                            Icons.drive_file_rename_outline,
                            size: 20,
                          ),
                          onPressed: () async {
                            final String? v = await _askCategoryName(
                              title: '重命名分类',
                              initial: c,
                            );
                            if (v == null) return;
                            await _library.renameCategory(c, v);
                            if (_filter == c) {
                              _filter = v;
                              _library.setPreferredFilter(v);
                            }
                            if (mounted) setState(() {});
                            setSt(() {});
                          },
                        ),
                        IconButton(
                          tooltip: '删除分类',
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: _ShelfStyle.danger,
                          ),
                          onPressed: () async {
                            final bool? ok = await showDialog<bool>(
                              context: ctx,
                              builder: (BuildContext dctx) => AlertDialog(
                                backgroundColor: _ShelfStyle.card,
                                title: const Text('删除分类？'),
                                content: Text(
                                  '「$c」将被删除，其中的 ${_library.countOfCategory(c)} 本书会移到未分类，不会删除正文。',
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dctx).pop(false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dctx).pop(true),
                                    child: const Text(
                                      '删除',
                                      style: TextStyle(
                                        color: _ShelfStyle.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            final String removed = c;
                            await _library.deleteCategory(removed);
                            if (_filter == removed) {
                              _filter = null;
                              _library.setPreferredFilter(null);
                            }
                            if (mounted) setState(() {});
                            setSt(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.create_new_folder_outlined,
                    color: _ShelfStyle.gold,
                  ),
                  title: const Text('新建分类'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _createCategory();
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<BookMeta> all = _library.books;
    final List<BookMeta> books = _filter == null
        ? all
        : all.where((BookMeta b) => b.category == _filter).toList();

    return Scaffold(
      backgroundColor: _ShelfStyle.paper,
      appBar: AppBar(
        title: const Text('书架'),
        backgroundColor: _ShelfStyle.appBar,
        foregroundColor: const Color(0xFFF4ECD8),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: <Widget>[
          if (_importing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _ShelfStyle.gold,
                  ),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: '功能菜单',
              icon: const Icon(Icons.more_vert),
              color: _ShelfStyle.card,
              onSelected: (String value) {
                if (value == 'import') {
                  _importBooks();
                } else if (value == 'new_category') {
                  _createCategory();
                } else if (value == 'manage') {
                  _manageCategories();
                }
              },
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'import',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.file_upload_outlined,
                        color: _ShelfStyle.appBar,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text('导入 TXT'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'new_category',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.create_new_folder_outlined,
                        color: _ShelfStyle.gold,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text('新建分类'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'manage',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.folder_outlined,
                        color: _ShelfStyle.appBar,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text('分类管理'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildCategoryBar(all),
          Expanded(
            child: all.isEmpty
                ? _buildEmpty()
                : books.isEmpty
                ? _buildFilterEmpty()
                : _buildGrid(books),
          ),
        ],
      ),
    );
  }

  /// 顶部分类筛选条：全部 / 未分类 / 自定义分类。
  Widget _buildCategoryBar(List<BookMeta> all) {
    final int uncategorized = all
        .where((BookMeta b) => b.category.isEmpty)
        .length;
    return Container(
      width: double.infinity,
      color: _ShelfStyle.card,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _filterChip(
              label: '全部',
              count: all.length,
              selected: _filter == null,
              onTap: () => _applyFilter(null),
            ),
            _filterChip(
              label: '未分类',
              count: uncategorized,
              selected: _filter == '',
              onTap: () => _applyFilter(''),
            ),
            for (final String c in _library.categories)
              _filterChip(
                label: c,
                count: _library.countOfCategory(c),
                selected: _filter == c,
                onTap: () => _applyFilter(c),
                onLongPress: () => _manageCategories(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Material(
          color: selected ? _ShelfStyle.appBar : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? _ShelfStyle.appBar
                      : const Color(0xFFD8D0C0),
                ),
              ),
              child: Text(
                '$label $count',
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? const Color(0xFFF4ECD8) : _ShelfStyle.ink,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
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
          '点击右上角菜单导入本地 TXT 小说',
          style: TextStyle(color: _ShelfStyle.muted),
        ),
      ],
    ),
  );

  Widget _buildFilterEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.folder_open, size: 64, color: _ShelfStyle.gold),
        const SizedBox(height: 14),
        Text(
          _filter == '' ? '未分类里还没有书' : '「$_filter」里还没有书',
          style: const TextStyle(color: _ShelfStyle.muted),
        ),
        const SizedBox(height: 6),
        const Text(
          '在其他书处长按 → 移动到分类',
          style: TextStyle(color: _ShelfStyle.muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _buildGrid(List<BookMeta> books) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
      // 固定三列：窄屏手机上每格约 130dp。卡片为「书名在上、续读信息在下」
      // 的书脊卡（见 _BookCard），0.95 的宽高比接近两行标题 + 一行状态的自然高度。
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.95,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (BuildContext context, int i) =>
          _BookCard(book: books[i], onTap: _openBook, onLongPress: _askRemove),
    );
  }
}

/// 书架卡片：竖向布局——色块"封面"在上，书名 + 续读信息在下，适配三列网格。
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
        : '续读 · ${_short(_chapterTitle(pos.chapterIndex), 10)}';
    final Color accent = accentColor(book.title, book.id);
    final String initial = book.title.isNotEmpty
        ? book.title.characters.first
        : '书';
    // 粗略进度：当前章 / 总章数，仅用于书架展示。
    final double progress = pos == null || book.chapterCount == 0
        ? 0
        : ((pos.chapterIndex + 1) / book.chapterCount).clamp(0.0, 1.0);

    // 「架上的书」：宣纸白卡 + 左侧书脊色条，右下淡色首字水印填补留白，
    // 底部一行续读信息与细进度条。
    return Material(
      color: _ShelfStyle.card,
      elevation: 1.2,
      shadowColor: const Color(0x3316224E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(book),
        onLongPress: () => onLongPress(book),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 书脊
            Container(width: 5, color: accent),
            Expanded(
              child: Stack(
                children: <Widget>[
                  // 首字水印：居中浮于卡面，填补标题与续读信息之间的留白。
                  Positioned.fill(
                    child: Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontSize: 58,
                          height: 1,
                          fontWeight: FontWeight.bold,
                          color: accent.withValues(alpha: 0.09),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 11, 10, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: _ShelfStyle.ink,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: <Widget>[
                            if (pos != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Icon(
                                  Icons.bookmark,
                                  size: 11,
                                  color: accent,
                                ),
                              ),
                            Flexible(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF8A8272),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: const Color(0x1416224E),
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  /// 书脊/水印用的低饱和深色，与墨蓝、金主色协调。
  static Color accentColor(String title, String id) {
    const List<Color> palette = <Color>[
      Color(0xFF3F5393), // 靛蓝
      Color(0xFF2F6E6B), // 松绿
      Color(0xFF9A5560), // 绛红
      Color(0xFFB08948), // 赭金
      Color(0xFF4A6579), // 黛蓝
      Color(0xFF6E4B7A), // 紫檀
      Color(0xFF4E6E50), // 苔绿
    ];
    if (title.isEmpty) return palette.first;
    // 混入 id 再散列：不同书即使标题哈希撞色，书脊色也会被拉开。
    return palette[(title.hashCode ^ id.hashCode).abs() % palette.length];
  }
}
