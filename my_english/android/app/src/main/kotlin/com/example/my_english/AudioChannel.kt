// package 与播放器一致，渠道定义与原生播放器同属一层，不需要扩大为公共 API。
package com.example.my_english

/**
 * 发音渠道类型：决定“怎么拿到这段音频”。
 *
 * 三种类型对应三条完全不同的取音路径，后续新增渠道只要归入其中一类，
 * 播放、缓存、预缓存和轮转都不需要再改。
 */
enum class AudioChannelType {
    // 直接下载型：音频地址能由单词和口音直接拼出来，GET 就是 MP3。
    DIRECT,

    // 接口调用型：要先换 token、查词，由接口下发音频地址，再下载。
    API,

    // 本地 TTS 型：设备实时合成，没有文件可下载，也不参与预缓存。
    LOCAL_TTS,
}

/**
 * 一个发音渠道的静态定义。
 *
 * [id] 同时是缓存目录名和轮转账本里的渠道键，一经发布不能再改，
 * 否则用户已经下载的离线音频会全部失效。
 */
data class AudioChannel(
    // 稳定协议值：缓存目录名 + 账本键。
    val id: String,
    // 展示名，用于日志排查。
    val displayName: String,
    // 取音方式。
    val type: AudioChannelType,
    // 轮转优先级：数字越大越先被点名。
    val priority: Int,
)

/**
 * 接口调用型渠道的统一入口。
 *
 * 每个这类渠道自己一个实现类，内部管理 token、请求签名和多次接口调用；
 * 播放器只关心“给我单词和口音，还我一个能直接下载的音频地址”。
 */
interface ApiAudioResolver {
    /**
     * 解析音频地址。
     *
     * 失败时抛异常（未收录、token 失效、网络错误都算），由播放器统一转成
     * “该渠道本次不可用”，不影响其他渠道。
     */
    fun audioUrl(spelling: String, accent: String): String
}

/**
 * 全 App 唯一的渠道注册表。
 *
 * 顺序即优先级，与 [AudioChannel.priority] 保持一致，新增渠道只改这里。
 */
object AudioChannels {
    // 不背单词：直接下载型。
    const val BEINGFINE = "beingfine"

    // 百度翻译：直接下载型。
    const val BAIDU = "baidu"

    // 有道：直接下载型。
    const val YOUDAO = "youdao"

    // 百词斩：接口调用型，需要游客 token 才能查词。
    const val BAICIZHAN = "baicizhan"

    // 系统本地 TTS：本地合成。
    const val TTS = "tts"

    // 所有渠道；数组顺序就是轮转优先级。
    val ALL: List<AudioChannel> = listOf(
        AudioChannel(BEINGFINE, "不背单词", AudioChannelType.DIRECT, 100),
        AudioChannel(BAICIZHAN, "百词斩", AudioChannelType.API, 60),
        AudioChannel(BAIDU, "百度翻译", AudioChannelType.DIRECT, 50),
        AudioChannel(YOUDAO, "有道", AudioChannelType.DIRECT, 10),
        AudioChannel(TTS, "本地 TTS", AudioChannelType.LOCAL_TTS, 0),
    )

    // 会产生 MP3 文件的网络渠道：直接下载型和接口调用型都算。
    val NETWORK: List<AudioChannel> = ALL.filter { it.type != AudioChannelType.LOCAL_TTS }

    // 网络渠道 id 列表，供预缓存与缓存扫描按顺序遍历。
    val NETWORK_IDS: List<String> = NETWORK.map { it.id }

    /** 按 id 找渠道定义；未知 id 返回 null。 */
    fun byId(id: String): AudioChannel? = ALL.firstOrNull { it.id == id }

    /** 判断某个 id 是否属于网络渠道（有文件可缓存）。 */
    fun isNetwork(id: String): Boolean = NETWORK.any { it.id == id }
}
