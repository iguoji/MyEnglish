///
/// 随身听页面的布局尺寸表，作用类似小程序页面共用的 WXSS 变量。
///
/// 所有边距和控件尺寸集中在这里，后续调整设计时不需要到多层 Widget 中寻找散落数字。
///
abstract final class ListeningLayout {
  ///
  /// 页面左右统一留白。
  ///
  /// @var double
  ///
  static const double pageInset = 20;

  ///
  /// 顶栏距离安全区顶部的距离。
  ///
  /// @var double
  ///
  static const double headerTop = 18;

  ///
  /// 顶栏图标按钮的完整点击画布大小。
  ///
  /// @var double
  ///
  static const double headerButtonSize = 34;

  ///
  /// 顶栏与进度条之间的距离。
  ///
  /// @var double
  ///
  static const double progressTop = 10;

  ///
  /// 播放进度条高度。
  ///
  /// @var double
  ///
  static const double progressHeight = 4;

  ///
  /// 相邻卡片之间的纵向距离。
  ///
  /// @var double
  ///
  static const double sectionGap = 12;

  ///
  /// 上方播放列表卡片的固定高度。
  ///
  /// @var double
  ///
  static const double playlistHeight = 180;

  ///
  /// 播放列表工具栏四周留白。
  ///
  /// @var double
  ///
  static const double playlistToolbarInset = 8;

  ///
  /// 搜索框与上下跳转按钮共享的高度和按钮宽度。
  ///
  /// @var double
  ///
  static const double compactControlSize = 32;

  ///
  /// 播放列表中每个单词行的固定高度。
  ///
  /// @var double
  ///
  static const double playlistRowHeight = 32;

  ///
  /// 页面卡片统一圆角。
  ///
  /// @var double
  ///
  static const double cardRadius = 10;

  ///
  /// 答案卡正文距离卡片边缘的基础留白。
  ///
  /// @var double
  ///
  static const double answerContentInset = 16;

  ///
  /// 眼睛按钮距离答案卡顶部和右侧的合法正数边距。
  ///
  /// @var double
  ///
  static const double answerActionInset = 8;

  ///
  /// 正文右侧额外预留空间，避免文字进入眼睛按钮的点击区域。
  ///
  /// @var double
  ///
  static const double answerContentRightInset =
      answerActionInset + headerButtonSize + answerContentInset;

  ///
  /// 设置面板每一项的固定行高。
  ///
  /// @var double
  ///
  static const double settingsRowHeight = 52;

  ///
  /// 单词骨架在字符宽度之外增加的基础宽度。
  ///
  /// @var double
  ///
  static const double spellingSkeletonBaseWidth = 40;

  ///
  /// 单词骨架为每个字母估算的宽度。
  ///
  /// @var double
  ///
  static const double spellingSkeletonCharacterWidth = 12;

  ///
  /// 单词骨架最大宽度，避免极长拼写挤占整行。
  ///
  /// @var double
  ///
  static const double spellingSkeletonMaxWidth = 260;

  ///
  /// 释义骨架在字符宽度之外增加的基础宽度。
  ///
  /// @var double
  ///
  static const double definitionSkeletonBaseWidth = 20;

  ///
  /// 释义骨架为每个中文字符估算的宽度。
  ///
  /// @var double
  ///
  static const double definitionSkeletonCharacterWidth = 14;

  ///
  /// 释义骨架最大宽度。
  ///
  /// @var double
  ///
  static const double definitionSkeletonMaxWidth = 300;
}
