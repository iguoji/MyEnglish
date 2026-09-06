// material.dart 提供 Dialog、按钮与布局组件。
import 'package:flutter/material.dart';

// 引入设计令牌总表与主题令牌，颜色、间距、圆角一律从这里取。
import '../common/theme.dart';

///
/// 二次确认对话框的尺寸表。
///
/// 表里的值都是从三份手写对话框里「取齐」出来的，不是重新设计的：
/// 原来首页的「删除单词」「清空数据」和听音辨义的「刷新候选词」各画了一份，
/// 圆角一个 14 一个 8、标题到正文的间距一个 8 一个 10、两颗按钮的缝一个 10
/// 一个 12。用户不会同时看到两个对话框，所以谁也没发现它们不一样。
///
abstract final class AppConfirmDialogLayout {
  ///
  /// 对话框卡片的圆角。
  ///
  /// 取三方里较软的 14（首页两处用的值）：对话框是浮在整屏之上的一块小卡，
  /// 转角软一点更像「弹出来的东西」，8 太接近页面里的正文白卡。
  static const double cardRadius = AppRadius.roundedXl;

  ///
  /// 卡片四周的内边距。三方原本一致，不用取舍。
  static const double inset = AppSpace.pBase;

  ///
  /// 标题与正文之间的距离。取三方里的多数值 8。
  static const double titleGap = AppSpace.p2;

  ///
  /// 标题图标与标题文字之间的距离。
  static const double titleIconGap = AppSpace.p2;

  ///
  /// 正文与底部两颗按钮之间的距离。三方原本一致。
  static const double bodyGap = AppSpace.p3;

  ///
  /// 两颗按钮之间的缝。取三方里的多数值 12。
  static const double buttonGap = AppSpace.p3;

  ///
  /// 两颗按钮的高度。
  ///
  /// 原先首页写的是 38，比总表那条「可以点的东西不该矮于 44」的下限还矮。
  /// 对话框里这两颗按钮一颗是「取消」一颗往往是「删除」，点错代价不小，
  /// 更不该做小。所以统一抬到 [AppSize.touchTarget]。
  static const double buttonHeight = AppSize.touchTarget;

  ///
  /// 按钮里图标的尺寸（只有带图标的那一版用得到）。
  static const double buttonIconSize = AppIcon.i16;

  ///
  /// 标题左侧图标的尺寸。
  static const double titleIconSize = AppIcon.i20;
}

///
/// 全 App 统一的二次确认对话框：一句标题、一段说明、一对「取消 / 确认」。
///
/// 生活化解释：凡是「点下去就收不回来」的操作——删掉一个单词、清空全部数据、
/// 把一个候选词换成新的——都先弹这一块出来问一句。三处问法长得一样，用户就知道
/// 「哦，又是那个要我再确认一次的框」。
///
/// 抽成公共组件之前，这三处各写了 40 到 55 行，共同点是骨架，差异全在细节上
/// 无意跑偏（圆角、间距、按钮画法都不一致）。现在骨架只有这一份，页面只填内容。
///
/// 两颗按钮直接用 Material 的 [OutlinedButton] 和 [FilledButton]，样式由主题里
/// 的按钮槽位统一提供。首页原来是拿 `InkWell` + `Container` 手搓的——手搓的版本
/// 没有键盘焦点框、也没有「按下时变暗」之外的状态，读屏软件也认不出它是按钮。
///
class AppConfirmDialog extends StatelessWidget {
  ///
  /// 创建一个二次确认对话框。
  const AppConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = defaultCancelLabel,
    this.titleIcon,
    this.confirmIcon,
    this.cancelIcon,
    this.confirmColor,
    this.cancelKey,
    this.confirmKey,
    super.key,
  });

  ///
  /// 「取消」两个字，三处本来写的都是它。
  static const String defaultCancelLabel = '取消';

  ///
  /// 标题，例如「删除单词」。
  final String title;

  ///
  /// 说明这一步会发生什么，允许折行。
  final String message;

  ///
  /// 确认按钮的文案，例如「删除」「确认清空」「刷新」。
  final String confirmLabel;

  ///
  /// 取消按钮的文案，一般不用改。
  final String cancelLabel;

  ///
  /// 标题左侧的 Tabler 图标，不传就只显示文字。
  final IconData? titleIcon;

  ///
  /// 确认按钮里的 Tabler 图标，不传就只显示文字。
  final IconData? confirmIcon;

  ///
  /// 取消按钮里的 Tabler 图标，不传就只显示文字。
  final IconData? cancelIcon;

  ///
  /// 确认按钮的底色。
  ///
  /// 不传就是主题里的品牌蓝。删除这类不可挽回的操作应当传
  /// [AppTokens.danger]，让按钮自己说出后果。
  final Color? confirmColor;

  ///
  /// 取消按钮的测试标识。
  final Key? cancelKey;

  ///
  /// 确认按钮的测试标识。
  final Key? confirmKey;

  ///
  /// 弹出对话框并等用户表态；返回 true 只在用户明确点了确认时发生。
  ///
  /// 点遮罩、按系统返回键都会让 `showDialog` 返回 null，这里统一算作取消——
  /// 三处调用方原本各写了一遍这个判断。
  static Future<bool> show(
    BuildContext context,
    AppConfirmDialog dialog,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => dialog,
    );
    return result == true;
  }

  ///
  /// 构建对话框卡片。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfirmDialogLayout.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConfirmDialogLayout.inset),
        child: Column(
          // 高度只包住内容，对话框不该拉成一整屏高。
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitle(textTheme),
            const SizedBox(height: AppConfirmDialogLayout.titleGap),
            Text(
              message,
              // 这段话常常折成两三行；行距用正文那一档自带的 1.43，
              // 本来就是为多行中文定的，不必在这里再写一遍。
              style: textTheme.fs5.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: AppConfirmDialogLayout.bodyGap),
            _buildActions(context, textTheme),
          ],
        ),
      ),
    );
  }

  ///
  /// 构建标题行：有图标就图标加文字，没有就只有文字。
  Widget _buildTitle(TextTheme textTheme) {
    final label = Text(title, style: textTheme.fs4Semibold);
    if (titleIcon == null) return label;
    return Row(
      children: [
        Icon(
          titleIcon,
          size: AppConfirmDialogLayout.titleIconSize,
          color: AppTokens.primary,
        ),
        const SizedBox(width: AppConfirmDialogLayout.titleIconGap),
        label,
      ],
    );
  }

  ///
  /// 构建底部两颗按钮：左取消、右确认，各占一半宽度。
  Widget _buildActions(BuildContext context, TextTheme textTheme) {
    // 两颗按钮共用的高度下限；写成 minimumSize 而不是写死高度，
    // 这样字号调到「大 / 特大」时按钮会跟着长高，而不是把文字压回去。
    final size = Size(0, AppConfirmDialogLayout.buttonHeight);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: cancelKey,
            onPressed: () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(minimumSize: size),
            child: _buildButtonChild(cancelIcon, cancelLabel),
          ),
        ),
        const SizedBox(width: AppConfirmDialogLayout.buttonGap),
        Expanded(
          child: FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: size,
              // 不传就沿用主题里的品牌蓝，传了通常是危险红。
              backgroundColor: confirmColor,
            ),
            child: _buildButtonChild(confirmIcon, confirmLabel),
          ),
        ),
      ],
    );
  }

  ///
  /// 构建一颗按钮的内容：有图标就图标加文字，没有就只有文字。
  ///
  /// 不用 `OutlinedButton.icon` 那一族构造函数，是因为它在不传图标时不可用，
  /// 会逼着调用方分两条分支写同一颗按钮。
  Widget _buildButtonChild(IconData? icon, String label) {
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppConfirmDialogLayout.buttonIconSize),
        const SizedBox(width: AppConfirmDialogLayout.titleIconGap),
        Text(label),
      ],
    );
  }
}
