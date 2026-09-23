# 夜曲（Yequ）

一款基于 Flutter 的本地 TXT 小说阅读器，面向 Android 平台（包名 `com.yequ.yequ`）。
无需联网、无账号，书籍与阅读数据全部保存在本机。

## 功能特性

- **本地导入**：通过系统文件选择器导入 TXT，自动识别 UTF-8 / GBK / UTF-16LE / UTF-16BE 编码；识别结果随书保存，再次打开解码结果一致。
- **书架管理**：
  - 封面色按书名生成，展示书名、章节数与续读章节；
  - 基于 FNV-1a 64 位内容指纹的重复导入校验；
  - 长按删除，可选「仅移出书架」或「连同本地文件永久删除」。
- **阅读体验**（能力由本地 `flutter_book_reader` 包提供）：
  - 仿真翻页、覆盖、平移、上下连续滚动等多种翻页模式；
  - 六套配色主题（白 / 灰 / 护眼黄 / 绿 / 蓝 / 夜间），可调字号、行距、首行缩进、段间距；
  - 章节目录、书签、划线、段评、自动阅读；
  - 竖滚模式按章节懒加载，滚动流畅。
- **进度持久化**：阅读位置精确到「章节 + 章内字符偏移 + 段内像素偏移」，应用重启或重新进入可像素级还原；设置全局统一，跨书生效。
- **沉浸阅读**：edge-to-edge 透明状态栏，唤起菜单时自动避让系统栏。

## 目录结构

```
lib/
├── main.dart                    # 应用入口，初始化书架与阅读设置
├── pages/
│   ├── splash_page.dart         # 启动页
│   ├── bookshelf_page.dart      # 书架（导入、删除、书籍卡片）
│   └── reader_page.dart         # 阅读器宿主页
├── services/
│   ├── library.dart             # 书架、本地文件、阅读进度管理（单例）
│   ├── txt_parser.dart          # TXT 编码识别与章节解析
│   ├── local_book_source.dart   # 阅读包的本地书源适配
│   ├── reader_settings.dart     # 全局阅读配置持久化（settings.json）
│   └── json_progress_store.dart # 阅读进度存储适配
└── models/
    └── book_meta.dart           # 书籍元数据（含章节偏移）

third_party/
└── flutter_book_reader/         # 本地 path 依赖的阅读内核（含本地补丁）
```

## 数据存储

应用文档目录下的 `yequ_reader/`：

- `library.json`：书架元数据（书名、编码、章节标题与偏移、导入时间等）
- `progress.json`：每本书的阅读位置
- `settings.json`：全局阅读配置
- `books/[id].txt`：导入时复制的原始 TXT 文件

## 开发环境

- Flutter（Dart SDK `^3.11.5`）
- 主要依赖：`file_picker`（选文件）、`path_provider`（存储路径）、`enough_convert`（GBK 解码）、本地路径依赖 `flutter_book_reader`

常用命令：

```bash
flutter pub get        # 安装依赖
flutter run            # 连接设备调试运行
flutter build apk --release   # 构建 release APK
```

Release 签名通过 `android/key.properties` 与 `android/app/*.jks` 配置，二者均已在
`.gitignore` 中忽略，不会入库。

阅读内核改动后，可在 `third_party/flutter_book_reader/` 下运行测试：

```bash
flutter test
```

## 说明

`third_party/flutter_book_reader` 是以 path 方式引入的本地阅读组件，其中包含针对本项目
的定制补丁（竖滚章内位置记忆、滚动性能、安全区避让等），升级时请注意保留这些改动。
