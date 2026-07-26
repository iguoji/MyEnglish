// package 相当于 PHP namespace，确保本类能被 MainActivity 直接引用。
package com.example.my_english

// Context 提供 Android 私有 SharedPreferences，作用类似小程序本地 storage。
import android.content.Context

/**
 * 口音和主题的原生持久化 Store。
 *
 * Dart 只接触 american/british 与 light/dark 四个稳定值，具体文件位置由 Android 管理，
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
    fun getSettings(): Map<String, String> {
        // mapOf 会通过 MethodChannel 转成 Dart Map。
        return mapOf(
            // 首次安装没有值时默认美式。
            ACCENT_KEY to preferences.getString(ACCENT_KEY, AMERICAN)!!,
            // 首次安装没有值时默认 Light。
            THEME_KEY to preferences.getString(THEME_KEY, LIGHT)!!,
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

    /** 所有稳定键值集中在 companion object，类似 PHP 类常量。 */
    private companion object {
        // SharedPreferences 口音键。
        const val ACCENT_KEY = "accent"

        // SharedPreferences 主题键。
        const val THEME_KEY = "theme"

        // 美式口音值。
        const val AMERICAN = "american"

        // 英式口音值。
        const val BRITISH = "british"

        // 浅色主题值。
        const val LIGHT = "light"

        // 深色主题值。
        const val DARK = "dark"
    }
}
