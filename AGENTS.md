# 注意事项

- 每次思考前读取本文件加深并更新记忆
- 全程使用中文进行交流
- 代码要详细且优雅的注释
- 每次的回复内容以你的模型名+可公开版本号开头
- 如无主动提出，禁止修改非你产生的MD文件

# Git仓库

如本轮需求与上次不同时，可以尝试自行提交git，需要整理归纳改动的逻辑点，信息内容可换行，尽量让人看起来优雅易懂。

# 组织风格

参考小程序式的页面目录式组织

# 界面风格

整体设计如同Tabler出品，所有组件及图标仅可使用Tabler的设计，不允许使用文字型图标代替图标

# 关于注释

我是从未接触过Dart语言和Flutter开发，所以务必每一行代码都以小程序或PHP的角度按流程写注释解释给我听

- 方法与函数：
    - 简短描述：首行写一句话说明方法的作用，可在下一行及之后详细描述用处。
    - 参数说明：使用 @param 声明参数类型和名称。
    - 返回值说明：使用 @return 声明返回的数据类型。
        ```php
        /**
         * 获取数据库连接实例。
         *
         * @param  string|null  $name
         * @return \Illuminate\Database\ConnectionInterface
         */
        public static function connection($name = null)
        {
            // ...
        }
        ```
- 类与属性注释
    - 类注释：说明类的整体功能与所属模块。
    - 属性注释：在属性上方标明变量类型、作用域等等修饰符
        ```php
        /**
         * 用户模型类.
         *
         * @property int $id
         * @property string $name
         */
        class User extends Model
        {
            /**
             * 不可被批量赋值的属性.
             *
             * @var array<int, string>
             */
            protected $guarded = [];
        }
        ```
- 行内注释
    - 使用双斜线 // 进行简单的逻辑说明。
    - 通常写在代码上方或右侧，保持简短。
        ```php
        // 使用自定义的查询构造器类
        $connection = parent::connection($name);
        ```

# 关于测试

如果你有启动、热更新、重启、关闭真机或模拟器的能力，为方便审阅或测试，你可以自行操作，比如截图、点击、模拟手势等等都能自主执行