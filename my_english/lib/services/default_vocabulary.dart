// services.dart 提供 rootBundle 与 MethodChannel，分别读取资源和调用 Android 标记。
import 'package:flutter/services.dart';

// Word Store 提供 JSON 转 Word 模型以及写入 SQLite 的接口。
import '../store/word.dart';

///
/// 首次安装时把内置词库导入本地 SQLite。
///
/// 该服务只在原生独立标记为 false 时执行；用户主动清空数据不会再次触发。
///
class DefaultVocabularyService {
  /// 默认词库资源路径；必须与 pubspec.yaml 的 assets 配置一致。
  static const String assetPath = 'assets/data/words.json';

  ///
  /// 初始化内置词库，已初始化或资源不可用时安全返回。
  ///
  /// @param  WordStore  store
  /// @param  MethodChannel  channel
  /// @return `Future<bool>` true 表示本次完成了导入。
  ///
  static Future<bool> initialize({
    required WordStore store,
    MethodChannel channel = const MethodChannel('my_english/settings'),
  }) async {
    // 读取独立标记，不能使用单词数量判断，因为用户清空后数量同样为 0。
    final initialized = await channel.invokeMethod<bool>(
      'isDefaultVocabularyInitialized',
    );
    if (initialized == true) return false;

    // 旧版本升级可能没有初始化标记，但用户已经有自己的词库；此时只能补标记，
    // 不能把默认词库整库导入，否则 importWords 会覆盖用户已有内容。
    if ((await store.getAll()).isNotEmpty) {
      await channel.invokeMethod<void>('markDefaultVocabularyInitialized');
      return false;
    }

    // 从安装包读取 JSON；这个过程不需要网络。
    final jsonText = await rootBundle.loadString(assetPath);
    // 使用既有解析器转换成 Word 列表，保持导入和用户导入格式一致。
    final words = parseWordsFromJsonText(jsonText);
    if (words.isEmpty) return false;
    // 原生 SQLite 在事务内整库导入，成功后再写初始化标记。
    await store.importWords(words);
    await channel.invokeMethod<void>('markDefaultVocabularyInitialized');
    return true;
  }
}
