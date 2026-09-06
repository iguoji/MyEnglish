///
/// 设计令牌总表的汇总出口。
///
/// 全 App 的「基础样式」集中在这一个目录里，相当于 HTML 里那份基础 CSS：
///
/// | 文件 | 类 | 管什么 | 命名方式 |
/// |---|---|---|---|
/// | `colors.dart` | `AppTokens` | 颜色（唯一跟随明暗模式的一张） | 按角色 |
/// | `fonts.dart` | `AppFont` / `AppWeight` | 字号与字重 | 按角色 |
/// | `spaces.dart` | `AppSpace` | 间距 | 按数值 |
/// | `radii.dart` | `AppRadius` / `AppStroke` | 圆角与线宽 | 按数值 |
/// | `sizes.dart` | `AppSize` | 造型尺寸（多处共用的方寸） | 按角色 |
/// | `icons.dart` | `AppIcon` | 图标**尺寸**（多大） | 按数值 |
/// | `glyphs.dart` | `AppGlyph` | 图标**语义**（画什么） | 按用途 |
/// | `motions.dart` | `AppDuration` | 动画时长 | 按数值 |
/// | `alphas.dart` | `AppAlpha` | 透明度 | 按数值 |
/// | `shadows.dart` | `AppShadow` | 投影的几何（沉多少、晕多远） | 按角色 |
///
/// 表里唯一一对容易看混的是最后两张图标表：`AppIcon` 决定图标**多大**，
/// `AppGlyph` 决定图标**画的是什么**。一个按钮上的图标要同时从两张表取值。
///
/// 各页面的专属尺寸表（`pages/*/widgets/*_layout.dart`）不写字面量，只从这里
/// 取台阶再起一个业务名字，相当于页面专属 CSS 继承基础 CSS。
///
/// 唯一的例外是 `AppSize` 与 `AppShadow`：只有**两个以上地方必须保持一致**的方寸
/// 才收进总表，只被一处用到的造型尺寸留在该页的尺寸表里写字面量。理由见
/// `sizes.dart` 的表头——把「数字恰好撞上」的两个尺寸并成一档，改一处会误伤另一处。
///
/// 页面**不需要**直接 import 本文件：`lib/common/theme.dart` 已经把它整份转发
/// 出去，现有的 `import '../../common/theme.dart'` 一行都不用改。
///
library;

export 'alphas.dart';
export 'colors.dart';
export 'fonts.dart';
export 'glyphs.dart';
export 'icons.dart';
export 'motions.dart';
export 'radii.dart';
export 'shadows.dart';
export 'sizes.dart';
export 'spaces.dart';
