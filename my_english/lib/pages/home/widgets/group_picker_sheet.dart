// material.dart 提供底部面板组件。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌。
import '../../../common/theme.dart';

/// 目标分组的一行展示数据。
class GroupPickerTarget {
  /// 创建目标项；groupId 为 null 表示"未分组"。
  const GroupPickerTarget({
    required this.groupId,
    required this.name,
    required this.wordCount,
  });

  /// 目标分组主键；null 表示移回"未分组"。
  final int? groupId;

  /// 分组名称。
  final String name;

  /// 分组当前单词数量。
  final int wordCount;
}

/// 弹出"移动/复制到分组"选择面板；返回用户选中的 groupId。
///
/// 返回值语义：null 需要与"用户直接关闭"区分，所以外层用 record 包装。
Future<(int?,)?> showGroupPickerSheet(
  BuildContext context, {
  required String title,
  required List<GroupPickerTarget> targets,
}) {
  // showModalBottomSheet 泛型使用 record，允许"选中了未分组(null)"。
  return showModalBottomSheet<(int?,)>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      // 读取当前明暗对应的设计令牌。
      final tokens = AppTokens.of(sheetContext);
      // 顶部圆角白卡容器。
      return Container(
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 30),
        child: Column(
          // 高度只包住内容。
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 面板标题，例如"移动 3 个单词到"。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 逐个目标分组生成可点击行。
            for (final target in targets)
              InkWell(
                // key 便于测试选择具体分组。
                key: Key('pick-group-${target.groupId ?? 0}'),
                // 用 record 包装选中值后关闭面板。
                onTap: () => Navigator.of(sheetContext).pop((target.groupId,)),
                child: Container(
                  // 行内边距与底部行分隔线。
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: tokens.rowBorder),
                    ),
                  ),
                  child: Row(
                    children: [
                      // 分组名称。
                      Text(
                        target.name,
                        style: TextStyle(color: tokens.text, fontSize: 13.5),
                      ),
                      // 撑开中间空间。
                      const Spacer(),
                      // 分组现有单词数量。
                      Text(
                        '${target.wordCount} 词',
                        style: TextStyle(color: tokens.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
