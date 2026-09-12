import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_book_reader/flutter_book_reader.dart';
import 'package:path_provider/path_provider.dart';

/// 阅读器设置：全局唯一的 [ReaderConfig]，变更后落盘到 settings.json。
///
/// flutter_book_reader 自身不持久化 [ReaderConfig]，这里通过监听其 ChangeNotifier
/// 把全部排版 / 主题 / 翻页方式设置保存下来，启动时用公开 setter 回放。
class ReaderSettings {
  ReaderSettings._();
  static final ReaderSettings instance = ReaderSettings._();

  /// 所有书共用的阅读器配置；BookReader 必须传入同一实例，设置才能跨书保持。
  final ReaderConfig config = ReaderConfig();

  Timer? _saveTimer;
  late final File _file;
  bool _loaded = false;

  static const Map<String, ReaderTheme> _themes = <String, ReaderTheme>{
    'white': ReaderTheme.white,
    'grey': ReaderTheme.grey,
    'yellow': ReaderTheme.yellow,
    'green': ReaderTheme.green,
    'blue': ReaderTheme.blue,
    'night': ReaderTheme.night,
  };

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final Directory base = await getApplicationDocumentsDirectory();
    _file = File(
      '${base.path}${Platform.pathSeparator}yequ_reader'
      '${Platform.pathSeparator}settings.json',
    );

    if (!_file.existsSync()) {
      // 首次使用：默认护眼黄底 + 仿真翻页（其余沿用包默认排版）。
      config
        ..setTheme(ReaderTheme.yellow)
        ..setFlipType(FlipType.simulation);
      config.addListener(_scheduleSave);
      return;
    }

    try {
      final Map<String, dynamic> json =
          jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      _apply(json);
    } catch (_) {
      // 设置损坏时回退默认，不影响阅读。
    }
    config.addListener(_scheduleSave);
  }

  void _apply(Map<String, dynamic> json) {
    final String? themeAlias = json['theme'] as String?;
    final ReaderTheme? theme = _themes[themeAlias];
    if (theme != null) config.setTheme(theme);

    final int? flipIndex = json['flipType'] as int?;
    if (flipIndex != null && flipIndex >= 0 && flipIndex < FlipType.values.length) {
      config.setFlipType(FlipType.values[flipIndex]);
    }

    final num? fontSize = json['fontSize'] as num?;
    if (fontSize != null) {
      // 包只提供增 / 减字号 API，从默认 19 逐步调到目标值。
      double target = fontSize.toDouble();
      while (config.fontSize < target && config.fontSize < ReaderConfig.maxFontSize) {
        config.increaseFont();
      }
      while (config.fontSize > target && config.fontSize > ReaderConfig.minFontSize) {
        config.decreaseFont();
      }
    }

    final num? lineHeight = json['lineHeight'] as num?;
    if (lineHeight != null) config.setLineHeight(lineHeight.toDouble());

    final int? indent = json['firstLineIndent'] as int?;
    if (indent != null) config.setFirstLineIndent(indent);

    final num? spacing = json['paragraphSpacing'] as num?;
    if (spacing != null) config.setParagraphSpacing(spacing.toDouble());

    final bool? justify = json['justify'] as bool?;
    if (justify != null) config.setJustify(justify);

    final num? dim = json['dimLevel'] as num?;
    if (dim != null) config.setDimLevel(dim.toDouble());

    final bool? comments = json['showSegmentComments'] as bool?;
    if (comments != null && comments != config.showSegmentComments) {
      config.toggleSegmentComments();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    // 行距 / 亮度滑块会高频通知，防抖后落盘。
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  Future<void> _saveNow() async {
    final Map<String, dynamic> data = <String, dynamic>{
      'theme': config.theme.alias,
      'flipType': config.flipType.index,
      'fontSize': config.fontSize,
      'lineHeight': config.lineHeight,
      'firstLineIndent': config.firstLineIndent,
      'paragraphSpacing': config.paragraphSpacing,
      'justify': config.justify,
      'dimLevel': config.dimLevel,
      'showSegmentComments': config.showSegmentComments,
    };
    try {
      _file.parent.createSync(recursive: true);
      await _file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 写盘失败不打断阅读。
    }
  }
}
