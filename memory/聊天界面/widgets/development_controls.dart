// 本文件是 development_page.dart 的一部分（part of），与主文件共享同一个
// library，因此可以直接使用页面内部的私有类型（下划线开头的类），不需要
// 单独 import 任何依赖。这里集中放置用户交互控件（顶栏按钮、候选项与键盘），让主文件只保留页面骨架与状态逻辑。
part of '../development_page.dart';

///
/// 顶栏无文字图标按钮。
///
/// 这个按钮的宽高和听音辨义模块相同，图标仍然是 Tabler 的 chevron-left。
///
class _DevelopmentIconButton extends StatelessWidget {
  /// 创建一个顶栏图标按钮。
  const _DevelopmentIconButton({
    required this.icon,
    required this.onTap,
    this.alignment = Alignment.center,
    super.key,
  });

  /// 要显示的 Tabler 图标。
  final IconData icon;

  /// 点击回调。
  final VoidCallback onTap;

  /// 图标在固定画布中的对齐方式。
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: DevelopmentLayout.headerButtonSize,
      height: DevelopmentLayout.headerButtonSize,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          DevelopmentLayout.headerButtonSize / 2,
        ),
        child: Align(
          alignment: alignment,
          child: Icon(icon, size: 21, color: tokens.textMedium),
        ),
      ),
    );
  }
}

/// 四选一候选区，使用原型中两列卡片布局。
class _DevelopmentChoices extends StatelessWidget {
  /// 创建四选一候选区。
  const _DevelopmentChoices({
    required this.options,
    required this.wrongOptions,
    required this.onTap,
    required this.tokens,
  });

  /// 候选文字。
  final List<String> options;

  /// 已答错并禁用的候选文字。
  final Set<String> wrongOptions;

  /// 点击候选时的回调。
  final ValueChanged<String> onTap;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - DevelopmentLayout.choiceGap) / 2;
        return Wrap(
          spacing: DevelopmentLayout.choiceGap,
          runSpacing: DevelopmentLayout.choiceGap,
          children: [
            for (var index = 0; index < options.length; index += 1)
              SizedBox(
                width: width,
                child: _DevelopmentChoiceButton(
                  key: ValueKey('development-choice-${options[index]}'),
                  text: options[index],
                  label: 'ABCD'[index],
                  wrong: wrongOptions.contains(options[index]),
                  onTap: () => onTap(options[index]),
                  tokens: tokens,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 单张四选一卡片。
class _DevelopmentChoiceButton extends StatelessWidget {
  /// 创建候选卡片。
  const _DevelopmentChoiceButton({
    required this.text,
    required this.label,
    required this.wrong,
    required this.onTap,
    required this.tokens,
    super.key,
  });

  /// 候选文字。
  final String text;

  /// A/B/C/D 标记。
  final String label;

  /// 是否已经答错。
  final bool wrong;

  /// 点击回调。
  final VoidCallback onTap;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final borderColor = wrong
        ? DevelopmentLayout.red.withValues(alpha: .55)
        : tokens.border;
    return Semantics(
      button: true,
      enabled: !wrong,
      label: '$label $text',
      child: Opacity(
        opacity: wrong ? .52 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: wrong ? null : onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: DevelopmentLayout.choiceHeight,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: wrong ? DevelopmentLayout.redLight : tokens.card,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: DevelopmentLayout.choiceBadgeSize,
                    height: DevelopmentLayout.choiceBadgeSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: wrong
                          ? DevelopmentLayout.red.withValues(alpha: .18)
                          : AppTokens.accent.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: wrong ? DevelopmentLayout.red : AppTokens.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: DevelopmentLayout.choiceTextSize,
                        fontWeight: FontWeight.w700,
                        decoration: wrong ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 原型中的三行 QWERTY 键盘。
class _DevelopmentKeyboard extends StatelessWidget {
  /// 创建键盘。
  const _DevelopmentKeyboard({
    required this.onKeyTap,
    required this.onBackspace,
    required this.disabled,
    required this.tokens,
  });

  /// 字母按键回调。
  final ValueChanged<String> onKeyTap;

  /// 删除键回调。
  final VoidCallback onBackspace;

  /// 当前是否禁用键盘。
  final bool disabled;

  /// 当前主题色令牌。
  final AppTokens tokens;

  /// 原型保持的三排字母顺序。
  static const List<String> _rows = <String>[
    'QWERTYUIOP',
    'ASDFGHJKL',
    'ZXCVBNM',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 原型先用第一排十个字母和九个间隔算出唯一的 --key，三排都
        // 复用它。之前用 Expanded 按每排子项数量重新分配空间，导致第二、
        // 三排的字母键比第一排宽，删除键也跟着挤压其它按键。
        final keyWidth =
            (constraints.maxWidth - 9 * DevelopmentLayout.keyGap) / 10;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var rowIndex = 0; rowIndex < _rows.length; rowIndex += 1) ...[
              if (rowIndex > 0)
                const SizedBox(height: DevelopmentLayout.keyRowGap),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _rows[rowIndex].length; i += 1) ...[
                    if (i > 0) const SizedBox(width: DevelopmentLayout.keyGap),
                    SizedBox(
                      width: keyWidth,
                      child: _DevelopmentKeyButton(
                        text: _rows[rowIndex][i],
                        onTap: () => onKeyTap(_rows[rowIndex][i]),
                        disabled: disabled,
                        tokens: tokens,
                      ),
                    ),
                  ],
                  if (rowIndex == _rows.length - 1) ...[
                    // 删除键前的间隔属于键盘统一 gap，不再通过 Padding
                    // 把字母键的可见宽度偷偷减掉。
                    const SizedBox(width: DevelopmentLayout.keyGap),
                    SizedBox(
                      width: keyWidth * 1.22,
                      child: _DevelopmentKeyButton(
                        icon: TablerIcons.backspace,
                        onTap: onBackspace,
                        disabled: disabled,
                        tokens: tokens,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 键盘上的一个字母或删除按钮。
class _DevelopmentKeyButton extends StatelessWidget {
  /// 创建键盘按钮。
  const _DevelopmentKeyButton({
    this.text,
    this.icon,
    required this.onTap,
    required this.disabled,
    required this.tokens,
  });

  /// 字母文字，与图标二选一。
  final String? text;

  /// 删除按钮图标。
  final IconData? icon;

  /// 点击回调。
  final VoidCallback onTap;

  /// 是否禁用。
  final bool disabled;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DevelopmentLayout.keyHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(DevelopmentLayout.keyRadius),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.sub,
              borderRadius: BorderRadius.circular(DevelopmentLayout.keyRadius),
              boxShadow: [
                BoxShadow(
                  color: tokens.border,
                  blurRadius: 0,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: icon != null
                ? Icon(icon, size: 18, color: tokens.textMedium)
                : Text(
                    text!,
                    style: TextStyle(
                      color: tokens.text,
                      fontSize: DevelopmentLayout.keyTextSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
