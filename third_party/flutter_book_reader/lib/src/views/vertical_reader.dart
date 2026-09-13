import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../chapter_end.dart';
import '../paginator.dart';
import '../reader_labels.dart';
import '../widgets/page_frame.dart';
import 'reader_mode_view.dart';

/// 上下滚动模式：多章连续流式滚动。
///
/// 临近底部自动接上下一章、临近顶部自动接上上一章（并补偿滚动位置），无需按钮；
/// 顶部标题 / 进度依据视口所处章节实时更新。
class VerticalReader extends ReaderModeView {
  const VerticalReader({
    super.key,
    required super.controller,
    required this.onTapToggleMenu,
  });

  final VoidCallback onTapToggleMenu;

  @override
  State<VerticalReader> createState() => _VerticalReaderState();
}

class _VerticalReaderState extends ReaderModeViewState<VerticalReader>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final Map<int, GlobalKey> _sectionKeys = <int, GlobalKey>{};

  /// 每个章节正文（ReaderProse）的 key，用于遍历段落渲染盒做位置追踪 / 恢复。
  final Map<int, GlobalKey> _proseKeys = <int, GlobalKey>{};

  /// 已处理过的定位信号 tick；[verticalAnchorTick] 变化时滚动到目标段落。
  int _lastAnchorTick = 0;
  bool _anchoring = false;
  int _anchorAttempts = 0;

  /// 定位重试上限（约 50×60ms = 3s，覆盖章节正文异步加载耗时）。
  static const int _maxAnchorAttempts = 50;

  /// 是否允许向流首接入上一章：仅在用户真实向上滚动后武装。
  ///
  /// 打开章节（含续读定位）时滚动位置本来就在 0，若立即 prepend，会在正文尚未
  /// 加载、章节高度还是占位值时连锁插入多章，且各章补偿相互覆盖，把视口拉到
  /// 错误章节。程序化 jumpTo（定位 / 自动阅读）不是用户手势，不武装。
  bool _prependArmed = false;

  /// 一次 prepend 的位置补偿完成前不再 prepend，避免短章连续插入时补偿竞态。
  bool _prependPending = false;

  /// 滚动位置同步按帧合并：jumpTo 同步派发的通知里布局仍是旧的，
  /// postFrame 回调中才能读到新位置下的段落盒。
  bool _syncScheduled = false;

  /// 自动阅读：按速度平滑向下滚（约「一屏 / autoTurnInterval」）。
  late final Ticker _autoTicker = createTicker(_onAutoTick);
  Duration _lastTick = Duration.zero;

  /// 「当前章」判定的节流：上次判定时的滚动位置，及触发重算的最小位移。
  double _lastChapterCheckPx = 0;
  static const double _chapterCheckStride = 60;

  @override
  void initState() {
    super.initState();
    controller.addListener(_syncAutoScroll);
    controller.addListener(_onControllerTick);
    controller.addListener(_onContentRevision);
    _lastContentRevision = controller.contentRevision;
    _syncAutoScroll();
    // 控制器在视图创建前发出的定位信号（首次续读、从横向模式切入）也要处理。
    _onControllerTick();
  }

  /// 章节流 / 正文 / 排版的结构版本：滚动中的高频位置通知（setVerticalPosition）
  /// 不 bump 此版本，故滚动过程中本视图不再整树重建；只有章节接入、正文到达、
  /// 改字号 / 主题等真正影响列表结构时才重建（此时父级可能跳过本 widget 更新）。
  int _lastContentRevision = 0;

  void _onContentRevision() {
    if (!mounted) return;
    final int revision = controller.contentRevision;
    if (revision != _lastContentRevision) {
      _lastContentRevision = revision;
      setState(() {});
    }
  }

  /// 依据自动阅读开关启停滚动 ticker。
  void _syncAutoScroll() {
    if (controller.autoTurning) {
      if (!_autoTicker.isActive) {
        _lastTick = Duration.zero;
        _autoTicker.start();
      }
    } else if (_autoTicker.isActive) {
      _autoTicker.stop();
    }
  }

  void _onAutoTick(Duration elapsed) {
    if (!_scrollController.hasClients) return;
    final double dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    final ScrollPosition pos = _scrollController.position;
    final double secs = controller.autoTurnInterval.inMilliseconds / 1000.0;
    // 速度：约「一屏 / 间隔」像素每秒。
    final double speed =
        secs > 0 ? pos.viewportDimension / secs : pos.viewportDimension;
    final double next = pos.pixels + speed * dt;
    if (next >= pos.maxScrollExtent) {
      _scrollController.jumpTo(pos.maxScrollExtent);
      // 到底且已是最后一章：停止自动阅读；否则 _onScroll 会自动接入下一章继续。
      if (controller.flowChapters.last >= controller.chapterCount - 1) {
        controller.setAutoTurning(false);
      }
    } else {
      _scrollController.jumpTo(next);
    }
  }

  @override
  void dispose() {
    _autoTicker.dispose();
    controller.removeListener(_syncAutoScroll);
    controller.removeListener(_onControllerTick);
    controller.removeListener(_onContentRevision);
    _scrollController.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    final ScrollMetrics m = n.metrics;
    // 用户真实拖拽 / 抛滚后才允许向上接章；程序化 jumpTo（定位、自动阅读）不武装。
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      _prependArmed = true;
    } else if (n is UserScrollNotification) {
      _prependArmed = true;
    }
    if (m.pixels >= m.maxScrollExtent - 800) {
      // 向流尾接章不改变既有内容偏移，无需武装 / 补偿。
      controller.appendNextFlowChapter();
    }
    // 串行化：补偿完成前不再 prepend，避免短章连锁插入时多个补偿以陈旧基准互相覆盖。
    if (_prependArmed && !_prependPending && m.pixels <= 400) {
      final int? inserted = controller.prependPrevFlowChapter();
      if (inserted != null) {
        _prependPending = true;
        _compensateForPrepend(inserted, m.pixels);
      }
    }
    // 章节判定要对每个已装入章做 RenderBox 查询，而滚动通知（尤其自动滚动）每帧都来。
    // 按滚动距离节流；计算延迟到 postFrame——jumpTo 同步派发通知时布局尚未更新，
    // 此时读到的段落位置是旧的，会误判当前章。
    if ((m.pixels - _lastChapterCheckPx).abs() >= _chapterCheckStride) {
      _lastChapterCheckPx = m.pixels;
      _schedulePositionSync();
    }
    return false;
  }

  /// 合并一帧内的多次滚动通知，帧末统一做一次章节 / 偏移同步。
  void _schedulePositionSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncVerticalPosition();
    });
  }

  /// 头部插入章节后，把滚动位置整体下移其高度，保持原本阅读处不动。
  ///
  /// 章节正文异步加载：刚插入时区块只有标题 + 加载提示（高度很小），必须等正文
  /// 渲染出最终高度后再补偿，否则正文到达时区块变高会把视口推回上一章。
  void _compensateForPrepend(int idx, double before, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        _prependPending = false;
        return;
      }
      final RenderBox? box =
          _sectionKeys[idx]?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && controller.bodyOf(idx) != null) {
        _scrollController.jumpTo(before + box.size.height);
        _prependPending = false;
        return;
      }
      if (attempt >= _maxAnchorAttempts) {
        _prependPending = false;
        return;
      }
      _compensateForPrepend(idx, before, attempt: attempt + 1);
    });
  }

  /// 控制器发出定位信号（首次续读 / 目录跳转 / 切到竖滚模式）时滚动到目标段落。
  void _onControllerTick() {
    if (controller.verticalAnchorTick == _lastAnchorTick) return;
    _lastAnchorTick = controller.verticalAnchorTick;
    // 切章 / 续读定位后流已重置到新章，位置在章首是正常态；待用户真实滚动后再允许接章。
    _prependArmed = false;
    _prependPending = false;
    _scheduleAnchor(
      controller.verticalAnchorChapter,
      controller.verticalAnchorOffset,
      controller.verticalAnchorInset,
    );
  }

  void _scheduleAnchor(int chapter, int offset, double inset) {
    _anchoring = true;
    _anchorAttempts = 0;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _runAnchor(chapter, offset, inset),
    );
  }

  /// 把视口滚到 [chapter] 章内字符偏移 [offset] 对应的段落，再补偿 [inset]
  /// 像素（段内精细位置还原）。章节正文异步加载时按帧重试，直到渲染就绪或
  /// 超过 [_maxAnchorAttempts]。
  void _runAnchor(int chapter, int offset, double inset) {
    if (!mounted || !_anchoring) return;

    bool done = false;
    if (_scrollController.hasClients &&
        controller.flowChapters.contains(chapter)) {
      final List<RenderParagraph> paras = _paragraphsOf(chapter);
      final List<int> offs = _blockOffsets(chapter);
      final RenderBox? listBox =
          _listKey.currentContext?.findRenderObject() as RenderBox?;
      if (paras.isNotEmpty &&
          paras.length == offs.length - 1 &&
          listBox != null) {
        int target = 0;
        for (int i = 0; i < paras.length; i++) {
          if (offset >= offs[i]) target = i;
          if (offset < offs[i + 1]) break;
        }
        final double relTop =
            paras[target].localToGlobal(Offset.zero, ancestor: listBox).dy;
        // 排版变化（如换字号）后旧 inset 可能超过当前段落高度：clamp 到该段高内，
        // 避免越过下一段。relTop 是段落顶部在内容坐标（px=0）中的位置；该段保存时
        // 已滚出视口上沿 inset 像素，故要在「对齐顶部」的基础上再多滚 inset。
        final double safeInset = inset.clamp(0.0, paras[target].size.height);
        final double targetPx =
            (_scrollController.position.pixels + relTop + safeInset)
                .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(targetPx);
        done = true;
      }
    }

    if (done) {
      _anchoring = false;
      return;
    }
    if (_anchorAttempts >= _maxAnchorAttempts) {
      _anchoring = false;
      return;
    }
    _anchorAttempts++;
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (mounted && _anchoring) _runAnchor(chapter, offset, inset);
    });
  }

  /// 取某章正文（ReaderProse 子树）内的段落渲染盒，按树顺序即段落顺序。
  List<RenderParagraph> _paragraphsOf(int idx) {
    final BuildContext? ctx = _proseKeys[idx]?.currentContext;
    final RenderObject? root = ctx?.findRenderObject();
    if (root == null) return const <RenderParagraph>[];
    final List<RenderParagraph> out = <RenderParagraph>[];
    void walk(RenderObject ro) {
      ro.visitChildren((RenderObject child) {
        if (child is RenderParagraph) out.add(child);
        walk(child);
      });
    }

    walk(root);
    return out;
  }

  /// 某章各段落首字符在章内的偏移前缀和（块长度坐标，与分页 / 书签一致）。
  List<int> _blockOffsets(int idx) {
    final String? body = controller.bodyOf(idx);
    if (body == null) return const <int>[];
    return controller.blockOffsetsOf(controller.chapterBlocks(idx, body));
  }

  /// 依据视口顶部落在哪一章 / 哪一段，更新「当前章 + 章内字符偏移 + 段内像素补偿」，
  /// 供进度持久化（竖滚续读到段落级 / 像素级位置）。
  void _syncVerticalPosition() {
    final RenderBox? listBox =
        _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;
    final double viewportTop = listBox.localToGlobal(Offset.zero).dy;

    int current = controller.flowChapters.first;
    for (final int idx in controller.flowChapters) {
      final RenderBox? box =
          _sectionKeys[idx]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      if (box.localToGlobal(Offset.zero).dy <= viewportTop + 8) {
        current = idx;
      } else {
        break;
      }
    }

    int offset = 0;
    double inset = 0;
    final List<RenderParagraph> paras = _paragraphsOf(current);
    final List<int> offs = _blockOffsets(current);
    if (paras.isNotEmpty && paras.length == offs.length - 1) {
      for (int i = 0; i < paras.length; i++) {
        final double top = paras[i].localToGlobal(Offset.zero).dy;
        if (top <= viewportTop + 8) {
          offset = offs[i];
          // 该段顶部已滚到视口上沿之上的距离（段间空白处可能略大于段高，恢复时再 clamp）。
          inset = (viewportTop - top).clamp(0.0, paras[i].size.height);
        } else {
          break;
        }
      }
    }
    controller.setVerticalPosition(current, offset, inset: inset);
  }

  @override
  Widget build(BuildContext context) {
    final ReaderLabels labels = ReaderLabels.of(context);
    final int count = controller.flowChapters.length;
    // 全书开头（第 0 章在流首）时，顶部插入扉页，随内容一起滚动。
    final bool showTitle =
        controller.hasTitlePage && controller.flowChapters.first == 0;
    final int lead = showTitle ? 1 : 0;
    // 连续滚动模式：顶部当前章节信息、底部章节进度为固定信息栏（中间列表滚动）。
    // 阅读器运行在 edge-toEdge（透明状态栏覆盖），分页模式刻意让正文延伸到状态栏
    // 下以避免系统栏显隐引发布局重排；竖滚模式不分页，顶部页眉须让出状态栏高度，
    // 否则章节名与时间 / 电量等系统图标重叠。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTapToggleMenu,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(
                left: pagePadding.left,
                right: pagePadding.right,
                top: pagePadding.top,
              ),
              child: ReaderHeaderBar(
                title: controller.currentChapterTitle,
                theme: theme,
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                // builder 惰性构建，滚出视口的章节会被回收，避免 RenderObject 无限驻留
                child: ListView.builder(
                  key: _listKey,
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: pagePadding.left,
                    right: pagePadding.right,
                  ),
                  itemCount: count + 1 + lead,
                  itemBuilder: (BuildContext context, int i) {
                    if (showTitle && i == 0) return _titleSection(context);
                    final int j = i - lead;
                    return j < count
                        ? _section(context, controller.flowChapters[j], labels)
                        : _footer(labels);
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: pagePadding.left,
                right: pagePadding.right,
                bottom: pagePadding.bottom,
              ),
              child: ReaderFooterBar(
                theme: theme,
                chapterIndex: controller.chapterIndex,
                chapterCount: controller.chapterCount,
                pageIndex: 0,
                pageCount: 0, // 连续滚动无页码，仅显示章号与进度
                progress: controller.globalProgress,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 竖滚模式下的扉页：约占一屏高，随内容向上滚出。
  Widget _titleSection(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: controller.titlePageBuilder!(context, theme),
    );
  }

  Widget _section(BuildContext context, int idx, ReaderLabels labels) {
    final bool isFirst = idx == controller.flowChapters.first;
    final String? body = controller.bodyOf(idx);
    return Column(
      key: _sectionKeys.putIfAbsent(idx, () => GlobalKey()),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!isFirst) ...<Widget>[
          const SizedBox(height: 8),
          Divider(color: theme.subTextColor.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
        ],
        Text(
          controller.chapterTitleAt(idx),
          style: TextStyle(
            fontSize: config.fontSize + 4,
            fontWeight: FontWeight.w700,
            color: theme.textColor,
          ),
        ),
        const SizedBox(height: 16),
        _sectionBody(context, idx, body, labels),
        // 章末组件：连续滚动模式下紧随该章正文之后（付费章不显示）。
        if (controller.chapterEndBuilder != null &&
            !controller.chapterLocked(idx)) ...<Widget>[
          const SizedBox(height: 12),
          controller.chapterEndBuilder!(
            context,
            theme,
            ReaderChapterEndInfo(
              chapterIndex: idx,
              chapterTitle: controller.chapterTitleAt(idx),
              isLastChapter: idx >= controller.chapterCount - 1,
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  /// 付费章预览取多少字（连续滚动无分页，用定长预览近似「第一页」）。
  static const int _lockPreviewChars = 500;

  /// 取章节开头约 [_lockPreviewChars] 字作为付费章预览内容。
  ReaderPage _lockedPreview(ReaderPage page) {
    final List<ReaderBlock> out = <ReaderBlock>[];
    int chars = 0;
    for (final ReaderBlock b in page) {
      out.add(b);
      chars += b.length;
      if (chars >= _lockPreviewChars) break;
    }
    return out;
  }

  Widget _sectionBody(
    BuildContext context,
    int idx,
    String? body,
    ReaderLabels labels,
  ) {
    // 未解锁付费章：显示开头一段预览 + 解锁块（连续滚动无“页”，取定长预览作“部分内容”）。
    if (controller.chapterLocked(idx) &&
        controller.chapterLockBuilder != null) {
      final Widget lockBlock = controller.chapterLockBuilder!(
        context,
        theme,
        controller.lockInfoFor(idx),
      );
      if (body == null) return lockBlock; // 正文未加载：仅显示解锁块
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ReaderProse(
            page: _lockedPreview(controller.chapterBlocks(idx, body)),
            config: config,
            chapterIndex: idx,
            chapterTitle: controller.chapterTitleAt(idx),
          ),
          lockBlock,
        ],
      );
    }
    if (body != null) {
      return KeyedSubtree(
        key: _proseKeys.putIfAbsent(idx, () => GlobalKey()),
        child: ReaderProse(
          page: controller.chapterBlocks(idx, body),
          config: config,
          chapterIndex: idx,
          chapterTitle: controller.chapterTitleAt(idx),
        ),
      );
    }
    if (controller.hasError(idx)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: <Widget>[
            Text(
              labels.loadFailed,
              style: TextStyle(fontSize: 13, color: theme.subTextColor),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => controller.retry(idx),
              style: TextButton.styleFrom(foregroundColor: theme.accentColor),
              child: Text(labels.retry),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        labels.loading,
        style: TextStyle(fontSize: 13, color: theme.subTextColor),
      ),
    );
  }

  Widget _footer(ReaderLabels labels) {
    final bool isLast =
        controller.flowChapters.last >= controller.chapterCount - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          isLast ? labels.bookEnd : labels.loadingNext,
          style: TextStyle(fontSize: 13, color: theme.subTextColor),
        ),
      ),
    );
  }
}
