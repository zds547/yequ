import '../services/txt_parser.dart';

/// 书架中的一本书（元数据持久化在 library.json，正文文件单独存放）。
class BookMeta {
  BookMeta({
    required this.id,
    required this.title,
    required this.fileName,
    required this.encoding,
    required this.chapters,
    required this.importedAt,
    this.fileSize = 0,
    this.contentHash = '',
  });

  /// 唯一 ID，同时作为本地正文文件名（[id].txt）。
  final String id;
  final String title;

  /// books 目录下的文件名。
  final String fileName;
  final String encoding;
  final List<ChapterInfo> chapters;
  final DateTime importedAt;

  /// 原始文件字节数（用于重复导入校验）。
  final int fileSize;

  /// 原始文件内容指纹（FNV-1a 64bit 的十六进制）。
  final String contentHash;

  int get chapterCount => chapters.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'fileName': fileName,
    'encoding': encoding,
    'chapters': chapters.map((ChapterInfo c) => c.toJson()).toList(),
    'importedAt': importedAt.millisecondsSinceEpoch,
    'fileSize': fileSize,
    'contentHash': contentHash,
  };

  factory BookMeta.fromJson(Map<String, dynamic> json) => BookMeta(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    fileName: json['fileName'] as String? ?? '',
    encoding: json['encoding'] as String? ?? kEncodingUtf8,
    chapters: (json['chapters'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => ChapterInfo.fromJson(e as Map<String, dynamic>))
        .toList(),
    importedAt: DateTime.fromMillisecondsSinceEpoch(
      json['importedAt'] as int? ?? 0,
    ),
    fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
    contentHash: json['contentHash'] as String? ?? '',
  );
}
