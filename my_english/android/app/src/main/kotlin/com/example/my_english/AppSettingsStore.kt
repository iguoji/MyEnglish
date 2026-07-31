// package 相当于 PHP namespace，确保本类能被 MainActivity 直接引用。
package com.example.my_english

// Context 提供 Android 私有 SharedPreferences，作用类似小程序本地 storage。
import android.content.Context

/**
 * 口音、主题、中文释义分隔符和每日复习目标的原生持久化 Store。
 *
 * Dart 只接触经过校验的稳定字符串，具体文件位置由 Android 管理，
 * 不申请外部存储权限，卸载 App 时系统会自动清理。
 */
class AppSettingsStore(context: Context) {
    // applicationContext 不持有 Activity，避免设置 Store 造成页面内存泄漏。
    private val preferences = context.applicationContext.getSharedPreferences(
        // 文件名类似 PHP 项目中单独的一份 settings 配置。
        "app_settings",
        // MODE_PRIVATE 表示只有当前 App 可以读取。
        Context.MODE_PRIVATE,
    )

    /** 返回 Dart 启动阶段需要的一次性设置快照。 */
    fun getSettings(): Map<String, Any> {
        // mapOf 会通过 MethodChannel 转成 Dart Map。
        return mapOf(
            // 首次安装没有值时默认美式。
            ACCENT_KEY to preferences.getString(ACCENT_KEY, AMERICAN)!!,
            // 首次安装没有值时默认 Light。
            THEME_KEY to preferences.getString(THEME_KEY, LIGHT)!!,
            // 旧版本没有保存该字段时默认使用中文顿号。
            DEFINITION_SEPARATOR_KEY to preferences.getString(
                DEFINITION_SEPARATOR_KEY,
                IDEOGRAPHIC_COMMA,
            )!!,
            // 旧版本没有保存目标时默认每天复习 100 个单词。
            DAILY_GOAL_KEY to preferences.getInt(DAILY_GOAL_KEY, DEFAULT_DAILY_GOAL),
        )
    }

    /** 校验并持久化口音，commit 返回时已经真正写入本地文件。 */
    fun setAccent(value: String) {
        // 只允许 Dart 枚举约定的两个值，防止损坏设置文件。
        require(value == AMERICAN || value == BRITISH) { "不支持的发音口音：$value" }
        // commit 是同步确认写入；这里只有一个短字符串，不会形成可感知卡顿。
        check(preferences.edit().putString(ACCENT_KEY, value).commit()) {
            // false 表示 Android 没能完成磁盘保存，错误会返回设置面板。
            "口音设置写入失败"
        }
    }

    /** 校验并持久化主题。 */
    fun setTheme(value: String) {
        // 当前产品只开放 Light 和 Dark。
        require(value == LIGHT || value == DARK) { "不支持的主题：$value" }
        // 保存完成以后 Dart 才切换界面，确保内存和磁盘一致。
        check(preferences.edit().putString(THEME_KEY, value).commit()) {
            // 向 Dart 返回明确失败原因。
            "主题设置写入失败"
        }
    }

    /** 校验并持久化中文释义分隔符。 */
    fun setDefinitionSeparator(value: String) {
        // 只接受设置面板提供的三种全角中文标点映射值。
        require(
            value == IDEOGRAPHIC_COMMA ||
                value == FULL_WIDTH_COMMA ||
                value == FULL_WIDTH_SEMICOLON,
        ) { "不支持的中文释义分隔符：$value" }
        // 同步确认写入，Dart 收到成功以后才会刷新全部释义文本。
        check(preferences.edit().putString(DEFINITION_SEPARATOR_KEY, value).commit()) {
            // false 表示 Android 没能把新符号保存到设置文件。
            "中文释义分隔符写入失败"
        }
    }

    /** 校验并持久化每日复习目标。 */
    fun setDailyGoal(value: Int) {
        // 与 Dart Store 保持一致，目标可以为 0，但不能为负数。
        require(value >= 0) { "每日复习目标不能小于 0：$value" }
        // 确认整数真正写入以后再让 Dart 更新页面状态。
        check(preferences.edit().putInt(DAILY_GOAL_KEY, value).commit()) {
            // false 表示磁盘写入失败。
            "每日复习目标写入失败"
        }
    }

    /** 清空全部设置，恢复到首次安装的默认值（对应 App 内「清空数据」）。 */
    fun clearAll() {
        // edit().clear() 删除本 SharedPreferences 文件中的全部键值对。
        // commit() 同步落盘，确保清空结果立刻对磁盘可见。
        check(preferences.edit().clear().commit()) {
            // false 表示 Android 没能完成清空。
            "设置清空失败"
        }
    }

    /** 所有稳定键值集中在 companion object，类似 PHP 类常量。 */
    private companion object {
        // SharedPreferences 口音键。
        const val ACCENT_KEY = "accent"

        // SharedPreferences 主题键。
        const val THEME_KEY = "theme"

        // SharedPreferences 中文释义分隔符键。
        const val DEFINITION_SEPARATOR_KEY = "definitionSeparator"

        // SharedPreferences 每日复习目标键。
        const val DAILY_GOAL_KEY = "dailyGoal"

        // 首次安装和旧版本升级后的默认每日目标。
        const val DEFAULT_DAILY_GOAL = 100

        // 美式口音值。
        const val AMERICAN = "american"

        // 英式口音值。
        const val BRITISH = "british"

        // 浅色主题值。
        const val LIGHT = "light"

        // 深色主题值。
        const val DARK = "dark"

        // 中文顿号对应的稳定存储值。
        const val IDEOGRAPHIC_COMMA = "ideographic_comma"

        // 中文全角逗号对应的稳定存储值。
        const val FULL_WIDTH_COMMA = "full_width_comma"

        // 中文全角分号对应的稳定存储值。
        const val FULL_WIDTH_SEMICOLON = "full_width_semicolon"
    }
}
