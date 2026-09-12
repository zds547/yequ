import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_book_reader/flutter_book_reader.dart';

import '../models/book_meta.dart';
import '../services/json_progress_store.dart';
import '../services/local_book_source.dart';
import '../services/reader_settings.dart';

/// 全屏阅读页：分页、五种翻页方式（默认仿真）、目录、主题、字号行距、
/// 书签 / 划线、自动翻页等 UI 均由 BookReader 自带。
///
/// 配置使用全局持久化的 [ReaderSettings.config]，主题 / 字号 / 翻页方式等
/// 设置在退出重进、跨书阅读之间保持一致。
class ReaderPage extends StatelessWidget {
  const ReaderPage({super.key, required this.book});

  final BookMeta book;

  @override
  Widget build(BuildContext context) {
    return BookReader(
      source: LocalBookSource(book),
      config: ReaderSettings.instance.config,
      progressStore: const JsonProgressStore(),
      labels: ReaderLabels.forLanguageCode(
        Localizations.localeOf(context).languageCode,
      ),
      onTextAction: (ReaderTextAction action, ReaderSelection selection) {
        if (action == ReaderTextAction.copy) {
          Clipboard.setData(ClipboardData(text: selection.text));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
    );
  }
}
