import 'chapter_content_mixin.dart';
import 'reader_controller_base.dart';

/// 纵向连续滚动的章节流能力（上下滚动模式使用）。
mixin VerticalFlowMixin on ReaderControllerBase, ChapterContentMixin {
  /// 临近底部时接上下一章，返回是否发生追加。
  bool appendNextFlowChapter() {
    final int last = flowChapters.last;
    // 末章为未解锁付费章时不再向下接章，避免付费正文被连续滚动漏出。
    if (chapterLocked(last)) return false;
    if (last < chapterCount - 1 && !flowChapters.contains(last + 1)) {
      flowChapters.add(last + 1);
      ensureLoaded(last + 1);
      contentRevision++;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// 临近顶部时接上上一章（返回被插入的章序号，无则 null）；位置补偿由视图完成。
  int? prependPrevFlowChapter() {
    final int first = flowChapters.first;
    if (first > 0 && !flowChapters.contains(first - 1)) {
      final int inserted = first - 1;
      flowChapters.insert(0, inserted);
      ensureLoaded(inserted);
      contentRevision++;
      notifyListeners();
      return inserted;
    }
    return null;
  }

  /// 竖滚模式下视口顶部段落已向上滚出视口上沿的像素数（段内精细位置），
  /// 与章号 / 字符偏移一起持久化，续读时做像素级还原。
  double verticalInset = 0;

  /// 纵向滚动时根据视口所处位置更新「当前章」及章内字符偏移。
  ///
  /// [charOffset] 为视口顶部段落的章内偏移（块长度坐标，与横向分页 / 书签同一套
  /// 坐标系），随进度一起持久化，使上下滚动模式续读时能恢复到段落级位置。
  /// [inset] 为该段落顶部距视口上沿的像素补偿，见 [verticalInset]。
  void setVerticalPosition(int index, int charOffset, {double inset = 0}) {
    bool changed = false;
    if (index != chapterIndex) {
      chapterIndex = index;
      signature = ''; // 切回横向模式时按当前章重新分页
      prefetchAround(index);
      changed = true;
    }
    if (charOffset != this.charOffset) {
      this.charOffset = charOffset;
      changed = true;
    }
    if ((inset - verticalInset).abs() > 0.5) {
      verticalInset = inset;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
