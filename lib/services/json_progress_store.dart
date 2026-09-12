import 'package:flutter_book_reader/flutter_book_reader.dart';

import 'library.dart';

/// 把阅读器的阅读进度对接到本地 JSON 持久化。
class JsonProgressStore extends ReaderProgressStore {
  const JsonProgressStore();

  @override
  Future<ReadingPosition?> load(Object bookId) async =>
      Library.instance.getProgress(bookId.toString());

  @override
  Future<void> save(Object bookId, ReadingPosition position) =>
      Library.instance.saveProgress(bookId.toString(), position);
}
