# 本地依赖说明

本目录固定保存 `tabler_icons_plus 3.44.0`，目的是让 MyEnglish 在无法访问 `pub.dev` 时仍能完成依赖解析、编译和启动。

- 上游包名：`tabler_icons_plus`
- 固定版本：`3.44.0`
- 许可证：见同目录 `LICENSE`
- 项目引用位置：`my_english/pubspec.yaml`
- 图标字体：`lib/fonts/`
- Dart 图标常量：`lib/tabler_icons_plus.dart`

`lib/tabler_icons_plus.dart` 和字体文件均来自上游发布包，请不要直接手工修改。未来升级时，应整体替换本目录并同步更新版本说明，然后执行 `flutter pub get --offline`、`flutter analyze --no-pub` 与 `flutter test --no-pub`。
