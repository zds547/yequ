# Flutter UI 组件包开发规范

> 适用范围:**不含任何原生代码**(无 `android/`、`ios/`、无 MethodChannel)、以 Flutter Widget 为对外产物的 package —— 本仓库 `flutter_book_reader` 即属此类。
>
> 与「纯 Dart 包」的关键差异:本类包**必须** `import 'package:flutter/*'`,因此不可能拿到服务端 / CLI 平台标签,也**必须**以 widget 测试为主力测试手段。凡纯 Dart 包规范中因"不得依赖 Flutter"而来的条款,在本文档中均已按 UI 包重述,不要照搬纯 Dart 版本。
>
> 但纯 Dart 包的两条核心纪律在这里同样成立,且是本文档的主线:**公开面越小越好**、**逻辑核心与 IO / UI 解耦**。
>
> **Flutter UI 包专属的强约束(多语言完整性、渲染性能、主题与无障碍、资源释放、Flutter 特有陷阱、宿主错误出口)集中在 [§11](#11-flutter-ui-包专属约束必读)**,那一节是本包 Review 时最常命中的部分,请优先阅读。
>
> 文档定位:这是一份**带解释的强约束**。每条规则先给出"要求",再给出"为什么"和"权衡",最后给出正反例。规则等级用 RFC 2119 语义:
>
> - **MUST / 必须** —— 违反即视为缺陷,CI 或 Code Review 应当拦截。
> - **SHOULD / 应当** —— 默认遵守;确有理由偏离时,必须在 PR 描述里写清楚理由。
> - **MAY / 可以** —— 团队自行取舍,列出来是为了避免每次重新讨论。

---

## 目录

1. [第一性原则:为什么纯 Dart 包的约束不一样](#1-第一性原则为什么纯-dart-包的约束不一样)
2. [项目结构约束](#2-项目结构约束)
3. [代码规范与简洁度](#3-代码规范与简洁度)
4. [架构与分层约束](#4-架构与分层约束)
5. [API 设计](#5-api-设计)
6. [版本管理与演进](#6-版本管理与演进)
7. [测试约束](#7-测试约束)
8. [CI 与发布](#8-ci-与发布)
9. [Code Review 检查清单](#9-code-review-检查清单)
10. [附录:可直接复制的模板](#10-附录可直接复制的模板)
11. [Flutter UI 包专属约束(必读)](#11-flutter-ui-包专属约束必读)

---

## 1. 第一性原则:为什么组件包的约束不一样

写一个 App 和写一个包,失败的代价完全不同。App 里写错了,你自己改;包里写错了,**所有依赖你的人都要改**。这个不对称决定了下面全部规则的走向:

**原则一:公开的东西越少越好。** 你写进 `lib/xxx.dart` 顶层的每一个类、每一个字段,都是一份你签给下游的、无法单方面撕毁的合同。私有代码可以随便重构,公开 API 改一个参数名就是破坏性变更。所以默认私有,确有必要才公开。

**原则二:UI 包不能假设宿主 App 长什么样。** 它会被接进各式各样的 App:不同的主题、不同的语言、不同的数据来源、不同的持久化方案、不同的原生插件组合。因此**禁止**把宿主的选择写死在包里——**不依赖任何原生插件**(电量、常亮、TTS、分享一律由宿主注入),**不内置多语言框架**(文案通过 `ReaderLabels` 传入),**不指定存储实现**(`BookSource` / `Reader*Store` 全是抽象)。一旦包里 `import 'package:battery_plus/...'`,所有用户都被迫接受这个依赖及其版本约束。

**原则三:失败要同时给"界面"和"程序"一个出口。** UI 包和纯 Dart 库在这里分岔:章节加载失败时,包**应当**把它渲染成可重试的界面状态(用户能看懂),而**不是**把异常抛给调用方去弹 toast。但仅有界面不够——涉及宿主资源(进度 / 书签 / 划线的持久化)的失败必须**同时**通过回调告知宿主,否则宿主永远不知道自己的存储挂了(见 [§11.6](#116-给宿主留错误出口must))。

**原则四:没有原生代码意味着 100% 可测。** 没有平台通道、没有真机依赖,任何"这个逻辑没法测"的说法在本类包里都是设计问题,不是客观限制。区别只在于**手段**:纯逻辑(分页、偏移换算、导航状态机)用单元测试,渲染与交互(翻页、选中、菜单)用 widget 测试 —— 后者在本类包里是**主力**,不是补充。

---

## 2. 项目结构约束

### 2.1 标准目录布局(MUST)

```
my_widget_package/
├── lib/
│   ├── my_widget_package.dart   # 唯一的公开入口(barrel file)
│   └── src/                     # 全部实现代码,对外不可见
│       ├── controller/          # 逻辑核心:状态、算法、导航(不含任何 Widget)
│       ├── views/               # 大块呈现形态(各翻页模式等)
│       ├── widgets/             # 可复用的小组件与绘制
│       ├── <feature>/           # 可插拔能力的抽象 + 默认实现(store / source)
│       └── *.dart               # 对外的配置、主题、文案、回调类型
├── test/                        # 逻辑测试镜像 lib/src/;交互测试按功能分文件
├── example/                     # 可运行的最小示例(pub.dev 评分项)
├── analysis_options.yaml
├── CHANGELOG.md
├── LICENSE
├── README.md
└── pubspec.yaml
```

**为什么不套 `api/domain/infra` 三层。** 那套划分是为"有 IO、无 UI"的库设计的。UI 包的真实边界不是"是否碰 IO",而是**"是否依赖渲染"**:`controller/` 必须能在没有 Widget 的前提下被单测(见 [4.1](#41-四类划分must)),`views/` 与 `widgets/` 必然依赖渲染。硬套三层会逼你把分页算法叫 domain、把翻页视图叫 api,名字与内容脱节,反而降低可读性。

**为什么 `lib/src/` 是硬性要求。** Dart 的可见性规则很特别:`lib/` 下**除 `src/` 外**的所有文件都被 pub 工具链视为公开 API,下游可以 `import 'package:my_package/任意文件.dart'`。只要你把文件放在 `lib/` 根目录,你就永远失去了自由移动它的权利。放进 `src/` 后,静态分析会对下游的直接 import 发出 `implementation_imports` 警告,你的重构自由度就回来了。

**权衡。** 有人会觉得多套一层 `src/` 很啰嗦,尤其小包。但从"小包"长成"大包"的过程中,没有人会主动做这次目录迁移——那意味着所有 import 路径的破坏性变更。所以一开始就分好,成本是零。

### 2.2 入口文件只做转发(MUST)

`lib/my_package.dart` 里**只允许**出现 `library` 声明、文档注释和 `export`,不允许有任何实现代码。

```dart
/// 一个用于解析和校验 XX 协议报文的纯 Dart 库。
///
/// 典型用法:
/// ```dart
/// final parser = MessageParser();
/// final result = parser.parse(bytes);
/// ```
library;

export 'src/book_reader_widget.dart' show BookReader;
export 'src/book_reader_controller.dart' show BookReaderController;
export 'src/reader_config.dart' show ReaderConfig, FlipType;
```

**必须用 `show` 显式列出导出符号,禁止裸 `export`。** 裸 `export 'src/xxx.dart';` 会把该文件里所有公开符号一并抛出去,包括你只想给内部用的辅助类。更糟的是,以后你在那个文件里新增一个类,它会**自动**变成公开 API,而你毫无察觉。`show` 让每一次 API 扩张都是一次显式的、要在 Code Review 里被看见的动作。

### 2.3 一个文件一个主类型(SHOULD)

文件名 = 主类型的 snake_case 形式。`MessageParser` → `message_parser.dart`。紧密耦合的小类型(比如某个类专用的枚举、`sealed` 子类)可以同文件,但不要把三个互不相关的类塞进 `utils.dart`。

**为什么要拒绝 `utils.dart`。** 它是架构熵的入口。一旦存在,任何"暂时不知道放哪"的代码都会流进去,半年后它变成几千行、被所有层引用、无法拆分的耦合中心。宁可多建几个命名精确的文件,也不要一个 `utils.dart`。

---

## 3. 代码规范与简洁度

### 3.1 Lint 基线(MUST)

Flutter 包必须以 `package:flutter_lints/flutter.yaml` 为底再收紧 —— 它已包含 `lints/recommended` 的全部规则,并额外加了 Flutter 专属项(如 `use_build_context_synchronously`、`use_key_in_widget_constructors`)。**不要**改用纯 Dart 的 `package:lints/recommended.yaml`,那会丢掉这些 Flutter 检查。

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    # 这几条对"包"而言是致命问题,降级为 warning 等于没有
    implementation_imports: error
    invalid_use_of_visible_for_testing_member: error
    body_might_complete_normally: error
  exclude:
    - '**/*.g.dart'
    - '**/*.freezed.dart'

linter:
  rules:
    # —— 公开 API 的稳定性 ——
    always_declare_return_types: true
    avoid_positional_boolean_parameters: true

    # —— 不可变性 ——
    prefer_final_locals: true
    prefer_final_fields: true
    prefer_const_constructors: true
    prefer_const_declarations: true
    avoid_setters_without_getters: true

    # —— 空安全与类型 ——
    avoid_dynamic_calls: true
    unnecessary_null_checks: true
    null_check_on_nullable_type_parameter: true

    # —— 简洁度 ——
    prefer_if_null_operators: true
    prefer_null_aware_method_calls: true
    unnecessary_parenthesis: true

    # —— 包场景专属 ——
    avoid_print: true
    unawaited_futures: true
    use_rethrow_when_possible: true
    depend_on_referenced_packages: true
    sort_pub_dependencies: true
```

**关于 `public_member_api_docs`(与纯 Dart 版本的差异)。** 纯 Dart 规范把它设成 `error`,理由是"设成 warning 就没人管"。但在 UI 包里它会为**每一个 widget 构造参数**索要一句文档,噪音显著高于收益,一次性开启会产生上百条报错,结果往往是整个分析输出被忽略 —— 那比不开更糟。本类包的折中:

- **不进 `errors:`,也不全局开启**;
- 但**新增**公开符号必须带 dartdoc,由 [§9](#9-code-review-检查清单) 的 Review 第一优先级把关;
- 存量补齐作为长期任务,补到一定比例后再考虑打开这条规则。

**为什么 `strict-casts` 值得开。** 默认模式下 `dynamic` 到具体类型的隐式向下转型是允许的,这让类型系统在最需要它的边界(JSON / 存储反序列化)悄悄失效。开启后,`json['id']` 不能直接赋给 `int`,你被迫写显式转换和校验 —— 而这正是解析层本该做的事。开启的一次性成本是几十个报错,收益是永久消除一整类运行时 `TypeError`。

**为什么去掉了 `discarded_futures` 和 `cascade_invocations`。** 前者在 widget 回调里几乎必然误报(`onTap: () => doAsync()` 是完全正常的写法);后者会把可读的连续赋值改写成级联式,在 UI 代码里反而更难读。`unawaited_futures` 保留 —— 它能抓出真正危险的"发起了持久化却没人处理失败"(见 [§11.6](#116-给宿主留错误出口must))。

**为什么 `strict-casts` 值得开。** 默认模式下 `dynamic` 到具体类型的隐式向下转型是允许的,这让类型系统在最需要它的边界(JSON 解析)悄悄失效。开启后,`json['id']` 不能直接赋给 `int`,你被迫写显式转换和校验——而这正是解析层本该做的事。开启的一次性成本是几十个报错,收益是永久消除一整类运行时 `TypeError`。

**为什么 `public_member_api_docs` 设成 `error`。** 因为它同时是 pub.dev 的评分项和最容易被"下次再补"拖死的事。设成 warning 时没人管;设成 error,写文档就成了写代码的一部分。这是本规范里最不受欢迎、但长期收益最高的一条。

### 3.2 格式化(MUST)

- 一律 `dart format .`,不手工排版,不与格式化器对抗。
- 行宽用默认 80,不改。团队里关于行宽的争论价值为零,而 80 的分屏 diff 可读性确实更好。
- CI 必须跑 `dart format --output=none --set-exit-if-changed .`,格式不对直接挂。

### 3.3 命名

| 对象 | 规则 | 例 |
|---|---|---|
| 包名、目录、文件 | `lower_snake_case` | `message_parser.dart` |
| 类、枚举、扩展、typedef | `UpperCamelCase` | `MessageParser` |
| 变量、方法、参数 | `lowerCamelCase` | `parseHeader` |
| 常量 | `lowerCamelCase`(不是 `SCREAMING_CAPS`) | `defaultTimeout` |
| 私有成员 | 前缀 `_` | `_buffer` |
| 泛型参数 | 单字母或有意义的词 | `T`、`R`、`TResult` |

补充约束:

- **禁止在公开 API 里用缩写**,除非是行业通用词(`http`、`url`、`id`、`json`)。`cfg`、`mgr`、`resp` 一律写全。内部私有变量可以放宽。
- **布尔量用断言式命名**:`isValid`、`hasHeader`、`canRetry`。禁止 `flag`、`status`(布尔的 `status` 尤其糟糕,因为它暗示了多态)。
- **方法名用动词短语**,并且**动词要诚实**:`getUser()` 若发起了网络请求,应叫 `fetchUser()`;`parse()` 若会修改入参,应叫 `parseInPlace()`。命名撒谎比没有命名更贵。
- **不要在类名里重复包名**。包 `my_json` 里的类叫 `Decoder`,不叫 `MyJsonDecoder`——调用方需要区分时可以 `import ... as`。

### 3.4 函数与类的粒度(SHOULD)

- 函数体 **≤ 40 行**;超过就找抽取点。
- 圈复杂度 **≤ 10**;嵌套层级 **≤ 3**。
- 参数 **≤ 4 个**;超过就该收成一个配置对象(见 [5.2](#52-参数设计))。
- 类的公开方法 **≤ 10 个**;超过通常意味着职责不止一个。

**这些数字不是玄学,是阈值报警器。** 它们的作用不是"41 行就一定错了",而是"到 41 行时你必须停下来想一下"。绝大多数情况下,超长函数里藏着一个没被命名的概念——把它抽出来命名,函数就短了,而且代码可读性的提升来自那个**名字**,不是来自行数变少。

**UI 包的豁免与加严(与纯 Dart 版本的差异):**

- **豁免行数**:`build()` 及 `_buildXxx()` 系列不计入 40 行阈值。Widget 树是声明式嵌套,强行按行数拆成一串 `_buildA/_buildB` 往往**更**难读 —— 读者要在多个方法间跳转才能拼出结构。
- **但嵌套层级照旧受约束**:widget 嵌套超过约 5~6 层就该抽成**独立的 Widget 类**(不是私有方法)。独立 Widget 有自己的 `const` 构造与重建边界,对性能也更友好(见 [§11.2](#112-渲染性能must))。
- **加严 State 类**:`State` 的字段数与方法数比普通类更容易失控 —— 一个类里同时管选区、坐标换算、浮层、缓存时,`setState` 的影响面就没人能推理清楚。**`State` 子类超过约 300 行或 15 个方法,MUST 拆**:优先把不依赖渲染的部分抽成纯类(便于单测),其次把浮层 / 子区域抽成独立 Widget。

降低复杂度最有效的两招:

```dart
// ❌ 反例:嵌套 + 长函数,读者要在脑子里维护 3 层上下文
Message? handle(List<int>? raw) {
  if (raw != null) {
    if (raw.length >= 4) {
      final header = _readHeader(raw);
      if (header.isValid) {
        return Message(header, raw.sublist(4));
      } else {
        return null;
      }
    } else {
      return null;
    }
  } else {
    return null;
  }
}

// ✅ 正例:卫语句拉平嵌套,主流程贴着左边界
Message? handle(List<int>? raw) {
  if (raw == null || raw.length < 4) return null;

  final header = _readHeader(raw);
  if (!header.isValid) return null;

  return Message(header, raw.sublist(4));
}
```

第二招是**用命名把注释干掉**:

```dart
// ❌ 需要注释解释的条件
if (t.difference(last).inSeconds > 30 && retries < 3) { ... }

// ✅ 条件本身就是解释
final shouldRetry = _isStale(t) && retries < maxRetries;
if (shouldRetry) { ... }
```

### 3.5 注释与文档注释

**区分两种注释,规则完全不同。**

**文档注释 `///`——面向调用方,MUST 覆盖所有公开成员。**

写法要求:

- 第一句是**完整的单句摘要**,以句号结尾。这一句会被 pub.dev 提取为列表摘要,写成半截话很难看。
- 摘要用**第三人称陈述**("Returns the parsed message."),不要用祈使句("Parse the message.")。这是 Dart 官方文档风格,与 SDK 保持一致。
- 空一行后写细节:边界条件、**会抛出哪些异常**、复杂度、线程/异步语义。
- 用 `[标识符]` 交叉引用,IDE 和 dartdoc 会渲染成可跳转链接。
- 至少给核心 API 一段可运行的 ` ```dart ` 示例。

```dart
/// 将 [raw] 解析为一条 [Message]。
///
/// [raw] 必须是完整报文;分片数据请先用 [FrameAssembler] 拼接。
///
/// 当报文头部校验和不匹配时抛出 [ParseException],其
/// [ParseException.kind] 为 [ParseErrorKind.checksum];当长度不足时
/// 为 [ParseErrorKind.truncated]。本方法不会抛出其他异常。
///
/// 时间复杂度 O(n),n 为 [raw] 的长度;不会复制底层字节。
///
/// ```dart
/// final message = parser.parse(Uint8List.fromList([0x01, 0x02, 0x03, 0x04]));
/// print(message.header.version);
/// ```
Message parse(Uint8List raw) { ... }
```

**行内注释 `//`——面向维护者,只写"为什么"。**

```dart
// ❌ 复述代码,零信息量,而且会随代码腐烂成谎言
// 把索引加一
index += 1;

// ✅ 解释代码看不出来的决策依据
// 协议 v2 的长度字段含头部自身 4 字节,v1 不含;此处统一按 v2 语义对齐,
// v1 报文在 _normalize 里已被补齐。见 spec §3.2。
index += 1;
```

**被注释掉的代码 MUST 删除。** 版本控制就是干这个的,留着只会让读者猜"这是不是还要用"。

### 3.6 明确禁止项(MUST NOT)

| 禁止 | 原因 | 替代 |
|---|---|---|
| 依赖任何**原生插件**(`battery_plus`、`wakelock_plus`、`flutter_tts`、`share_plus`…) | 把宿主锁死在你选的插件及其版本上;也会缩水平台标签 | 定义数据 / 回调入口由宿主注入(如 `battery: ValueListenable<ReaderBatteryInfo?>`),示例 App 里才真正接插件 |
| 内置多语言框架(`intl` / `gen-l10n` 生成物进 `lib/`) | 强加构建负担,且宿主的文案体系无法复用 | 一个不可变文案类(如 `ReaderLabels`)+ 内置预设,宿主传入 |
| 顶层 `import 'dart:io'` | 包在 Web 上直接不可用 | 抽象成接口注入;或用条件导入分离实现 |
| `print()` / `debugPrint()` | 库无权决定宿主的日志策略,且污染生产输出 | 暴露可选的 `void Function(String)? onLog` 回调,默认 `null` |
| 可变全局状态 / 单例 | 测试无法隔离,多实例互相干扰 | 依赖注入,由调用方持有实例(全局默认值可以有,但必须能被实例覆盖) |
| `late` 用于可空语义 | 把编译期错误推迟成运行时 `LateInitializationError` | 用 `?` 或构造函数保证初始化 |
| `dynamic` 出现在公开签名 | 类型系统失效,IDE 补全失效 | 泛型或明确类型;实在需要用 `Object?` |
| `as` 强转外部数据 | 运行时崩溃 | `is` 判断 + 显式错误分支 |
| 捕获后吞掉异常 `catch (_) {}` | 故障静默,排查成本极高 | 至少 `rethrow`,或转成 UI 错误态 **且**回调告知宿主(见 [§11.6](#116-给宿主留错误出口must)) |
| 公开 API 返回可变集合 | 调用方能改你的内部状态 | 返回 `List.unmodifiable(...)` 或 `UnmodifiableListView` |
| 在 `State` 自身 `context` 上查询**自己创建**的 `InheritedWidget` | 查找只向上遍历,取不到自己子树里建的作用域 → 静默回退默认值 | 直接用 `widget.xxx`,或把读取下沉到子 Widget 的 `build`(见 [§11.5](#115-flutter-特有陷阱must)) |
| `build()` 里做度量 / 路径布尔运算 / 大字符串拼接 | 每帧重复执行,直接掉帧 | 提到 `initState` / `didUpdateWidget` 缓存,或交给 `CustomPainter`(见 [§11.2](#112-渲染性能must)) |

---

## 4. 架构与分层约束

### 4.1 四类划分(MUST)

UI 包的分界线不是"是否碰 IO",而是**"是否依赖渲染"**。必须有四条清晰的界:

```
        ┌────────────────────────────────────────────┐
        │  对外类型 —— 入口 Widget、配置、主题、文案、  │  ← 稳定,改动 = 破坏性变更
        │              回调、对外控制器                │
        ├────────────────────────────────────────────┤
        │  controller/ 逻辑核心 —— 状态机、算法、导航   │  ← 不含 Widget,可纯单测
        ├────────────────────────────────────────────┤
        │  views/ widgets/ 呈现层 —— 渲染与手势        │  ← 依赖渲染,用 widget 测试
        ├────────────────────────────────────────────┤
        │  可插拔能力 —— source / store 的抽象         │  ← 宿主实现,测试里换 fake
        └────────────────────────────────────────────┘

依赖方向:对外类型 → controller ← 呈现层;可插拔能力的抽象由 controller 定义
```

各层职责:

**对外类型**是门面:入口 Widget 负责编排(装配控制器、注入作用域、生命周期),配置 / 主题 / 文案 / 回调是纯数据。这一层**不应该有业务逻辑** —— 逻辑漏进入口 Widget 的典型征兆是 `State` 越写越长(见 [3.4](#34-函数与类的粒度should) 的 300 行阈值)。

**`controller/`** 是包的心脏,放状态、算法、导航规则。**硬性约束:不得 import `material.dart` / `cupertino.dart`,不得构建任何 Widget,不得直接读写文件或网络。** 允许 import `widgets.dart` 里的**纯数据类型**(`Size`、`TextStyle`、`Locale`、`TextScaler`) —— 排版计算离不开它们,这与"不依赖渲染"不冲突:它仍然可以在 `flutter_test` 里不建任何 Widget 就完成断言。

**`views/` `widgets/`** 放所有依赖渲染的东西:各翻页模式、页面框架、绘制器、手势。

**可插拔能力**(`BookSource`、`Reader*Store`)只在包内定义**抽象**,默认实现只提供"空操作"与"内存版";真实实现属于宿主。

**为什么"时钟和随机数"也要注入。** 这是最常被忽略的一条。一个直接调用 `DateTime.now()` 的判断函数是无法稳定测试的 —— 你没法测"刚好在边界那一毫秒"。把时钟抽成 `DateTime Function() now` 注入进来,这些用例立刻变成三行普通单测。**UI 包的等价物是 `vsync` 与帧时间**:动画一律走 `AnimationController` / `Ticker`(测试里由 `pump(duration)` 精确驱动),**不得**用 `Timer.periodic` 自己数帧。

```dart
// ❌ domain 层直接摸系统时间,不可测
class TokenValidator {
  bool isExpired(Token token) => DateTime.now().isAfter(token.expiresAt);
}

// ✅ 时间从外面来,domain 保持纯粹
final class TokenValidator {
  TokenValidator({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  bool isExpired(Token token) => _now().isAfter(token.expiresAt);
}

// 测试里:
final validator = TokenValidator(now: () => DateTime.utc(2026, 1, 1));
```

### 4.2 依赖方向不可逆(MUST)

`controller/` **不得**引用 `views/` / `widgets/` 的任何具体类型,也不得引用宿主的具体实现。如果逻辑核心需要"取正文"这个能力,它自己定义抽象,由宿主去实现——**接口属于使用方,不属于实现方**。

> 唯一的例外要写清楚:逻辑核心可以持有**由宿主传入的构建器**(如 `Widget Function(...) titlePageBuilder`),因为那是数据流入,不是对呈现层的依赖 —— 控制器只转发它,不知道它会画出什么。

```dart
// lib/src/source/book_source.dart —— 抽象由包定义
abstract class BookSource {
  Future<BookManifest> loadManifest();
  Future<String> loadChapterBody(int index);
}

// 宿主侧实现(HTTP / 数据库 / 本地文件),包里只提供最小的假实现供测试用
final class DbBookSource implements BookSource { /* ... */ }
```

这条规则的价值在于**编译期就能验证架构没有腐化**。层间违规不是靠人眼看出来的,是靠 import 检查出来的。可以用一段简单的 CI 脚本强制:

```bash
# 逻辑核心不得依赖渲染层,也不得碰 IO
! grep -rE "import .*(material\.dart|cupertino\.dart|src/views|src/widgets|dart:io|dart:html)" lib/src/controller/
```

### 4.3 把 IO 推到边界上(依赖倒置)

**MUST:任何跨进程边界的能力(网络、文件、时间、随机、环境变量)都通过构造函数注入,不在类内部 `new` 出来。**

**MUST NOT:直接依赖 `package:http` 等第三方的具体类型出现在公开 API 上。** 你一旦在公开签名里写 `http.Client`,就等于把下游锁死在那个包的那个大版本上——它发布 breaking change 时,你的用户会陷入依赖地狱。定义自己的最小接口,内部再做适配。

```dart
// ✅ 自定义最小接口:只声明你真正需要的能力
abstract interface class HttpClientLike {
  Future<HttpResponseLike> send(HttpRequestLike request);
}
```

**权衡要说清楚。** 这样做的代价是多一层适配代码,以及用户接入时要包一层。对于只有内部使用的小工具包,直接依赖 `package:http` 是可接受的取舍;但对于要发到 pub.dev 给外部用的包,这层隔离几乎总是值得的。判断标准:**你能不能承受被下游依赖冲突骂?**

### 4.4 不可变优先(MUST)

所有跨越层边界的数据模型必须不可变:字段全 `final`,构造函数尽量 `const`,变更通过 `copyWith` 产生新实例。

```dart
final class MessageHeader {
  const MessageHeader({
    required this.version,
    required this.length,
    this.flags = const <String>[],
  });

  final int version;
  final int length;
  final List<String> flags;

  MessageHeader copyWith({int? version, int? length, List<String>? flags}) {
    return MessageHeader(
      version: version ?? this.version,
      length: length ?? this.length,
      flags: flags ?? this.flags,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MessageHeader &&
      other.version == version &&
      other.length == length;

  @override
  int get hashCode => Object.hash(version, length);
}
```

**为什么值得这么麻烦。** 可变模型在异步代码里是定时炸弹:你把对象交出去,`await` 一下,回来时它已经被别人改了,而这类 bug 在测试里几乎不可复现。不可变模型把这整类问题从"运行时偶发"降级为"编译期报错"。

**注意 `copyWith` 的经典陷阱:它无法把字段设成 `null`。** 上面的写法里 `copyWith(flags: null)` 表达的是"不修改",不是"清空"。如果某字段确实需要"清空"语义,单独提供 `clearFlags()`,或用 sentinel 值——但**必须在文档注释里写明**,这是 `copyWith` 最常见的踩坑点。

**MAY:** 模型多且样板代码烦人时可以引入 `freezed` + `json_serializable`。代价是给下游增加了 build_runner 的构建负担认知(实际上生成代码已提交则无负担),收益是消除手写 `==`/`hashCode` 的出错空间。**如果引入,生成文件必须提交到仓库**,否则下游从 git 依赖你的包时会编译失败。

### 4.5 状态与并发

- **MUST NOT** 使用可变的静态字段、全局单例。包的每个实例应当自包含,两个实例互不干扰。
- **MUST** 让每个公开的异步方法在文档里说明:是否可重入、是否可并发调用、是否有内部队列。
- **SHOULD** 对持有资源(Socket、StreamSubscription、Timer)的类实现 `Future<void> dispose()`,并在文档中明确"dispose 后再调用任何方法的行为"(推荐抛 `StateError`)。
- **MUST** 使 `dispose()` 幂等,重复调用不报错。

### 4.6 日志与可观测性

库**不得**决定宿主的日志方式。正确做法是把观测点暴露成可选回调或 Stream:

```dart
final class MessageParser {
  const MessageParser({this.onDiagnostic});

  /// 解析过程中的诊断信息回调,默认不产生任何输出。
  ///
  /// 回调在解析线程同步触发,实现方**不应**在其中执行耗时操作。
  final void Function(Diagnostic)? onDiagnostic;
}
```

**为什么不直接依赖 `package:logging`。** 那是在替用户做技术选型。用户可能用 `logger`、`logging`,或者接到自家的埋点系统。一个 `Function` 回调零依赖、零学习成本,用户三行代码就能桥接到任何日志框架。

---

## 5. API 设计

### 5.1 公开面最小化(MUST)

新增一个公开符号前,先问三个问题:调用方**现在**就需要它吗?没有它能不能完成任务?它未来会不会变?任何一个答案不确定,就先别公开。

**这条规则的不对称性是关键:今天少公开一个类,明天补上是 minor 版本;今天多公开一个类,明天想删是 major 版本。** 少公开的代价是用户提个 issue,多公开的代价是你被永久绑架。

具体做法:

- 实现类默认 `final class`(Dart 3),显式禁止外部继承。要允许继承时用 `base`/`interface`/`mixin` 明确表达意图,并在文档里写明继承契约。
- 只给调用方需要的 getter,不要无脑给所有字段配 setter。
- 内部辅助类型即使跨文件使用,也留在 `src/` 内不导出。

### 5.2 参数设计

- **MUST**:超过 2 个参数时,除首个主参数外一律用**命名参数**。
- **MUST**:布尔参数一律命名,永不使用位置布尔——`parse(bytes, true)` 在调用点完全不可读。
- **MUST**:必填的命名参数用 `required`,不用"可选 + 运行时断言"。
- **SHOULD**:参数超过 4 个时收成一个 `const` 配置对象。

```dart
// ❌ 调用点像天书:parser.parse(bytes, true, false, 3);
Message parse(Uint8List raw, bool strict, bool copy, int retries);

// ✅ 自解释,且未来加参数不是破坏性变更
Message parse(
  Uint8List raw, {
  bool strict = true,
  bool copyBytes = false,
  int maxRetries = 3,
});

// ✅✅ 参数再多就收成配置对象
Message parse(Uint8List raw, {ParseOptions options = const ParseOptions()});
```

**注意最后一种写法带来的演进优势:**给 `ParseOptions` 加一个带默认值的新字段是非破坏性的,而给方法加一个命名参数虽然对调用方非破坏,但对**实现了你接口的下游**是破坏性的。如果这个方法在抽象接口上,配置对象几乎是唯一安全的演进路径。

### 5.3 错误模型(MUST)

> **UI 包先读这条(与纯 Dart 版本的差异)。** 组件包的主要失败来自「宿主提供的数据源 / 存储」,而它有 UI 可用,所以处理方式不同:
>
> 1. **能画出来的失败,画出来。** 章节加载失败 → 渲染可重试的错误态,**不要**把异常抛给调用方。抛异常会让宿主被迫在 widget 树外面 try-catch,而那里根本没法恢复。
> 2. **画不出来的失败,回调出去。** 写入类失败(进度 / 书签 / 划线 / 评论的持久化)没有对应界面,**必须**通过错误回调告知宿主(见 [§11.6](#116-给宿主留错误出口must))。静默丢弃是本类包最容易犯、也最难排查的错误。
> 3. **构造期的非法用法照旧抛 `Error`。** 参数矛盾、dispose 后调用 —— 这是宿主的 bug,应该在开发期就崩掉,见下面的规则三。
>
> 下面规则一 / 二关于"自定义异常 + 机器可读分类"的部分,在本类包里只适用于**确实需要抛给调用方**的少数场景;不要为了满足条文而给 UI 错误态硬造一套异常类型。

**规则一:只抛出本包定义的异常类型,或明确文档化的 SDK 异常。** 让 `package:http` 的 `ClientException` 从你的 API 里漏出去,等于把你的实现细节写进了合同。

**规则二:异常必须携带机器可读的分类。** 调用方要能 `switch` 而不是靠字符串匹配。

```dart
/// 解析失败的原因分类。
enum ParseErrorKind { truncated, checksum, unsupportedVersion, malformed }

/// 解析报文时发生的错误。
final class ParseException implements Exception {
  const ParseException(this.kind, this.message, {this.offset});

  /// 错误分类,用于调用方分支处理。
  final ParseErrorKind kind;

  /// 面向人的说明,不保证格式稳定,**不应**被解析。
  final String message;

  /// 出错位置在原始字节流中的偏移,未知时为 null。
  final int? offset;

  @override
  String toString() => 'ParseException($kind): $message'
      '${offset == null ? '' : ' at $offset'}';
}
```

**规则三:区分"程序 bug"和"预期内失败"。**

- 调用方传了非法参数、在 dispose 后调用方法 → 这是 **bug**,抛 `ArgumentError` / `StateError`(属于 `Error`),不应被 catch,应该在开发期就被修掉。
- 网络断了、数据损坏、文件不存在 → 这是**预期内失败**,抛 `Exception` 子类,调用方**必须**处理。

这个区分直接决定了调用方该不该写 try-catch。混为一谈的库会逼着用户对所有调用无脑套 `catch (e)`,这正是错误处理退化的开始。

**规则四:异步失败通过 Future 的错误通道返回,不要返回 `null` 表示失败。** `null` 丢失了失败原因。

**MAY:考虑 `Result<T, E>` 风格。** 当失败是高频的、常规的控制流(比如逐行解析一个可能有脏数据的大文件),用 `sealed class` 建模返回值比异常更合适,因为 Dart 3 的穷尽性检查会强制调用方处理每个分支:

```dart
sealed class ParseResult {
  const ParseResult();
}

final class ParseSuccess extends ParseResult {
  const ParseSuccess(this.message);
  final Message message;
}

final class ParseFailure extends ParseResult {
  const ParseFailure(this.kind);
  final ParseErrorKind kind;
}

// 调用方:漏掉任何一个分支都编译不过
final text = switch (parser.tryParse(bytes)) {
  ParseSuccess(:final message) => message.body,
  ParseFailure(:final kind) => 'failed: $kind',
};
```

**取舍:不要两种风格混用。** 全包统一,要么异常为主,要么 Result 为主(可以对同一能力提供 `parse()` 抛异常 + `tryParse()` 返回 Result 的成对 API,这是 Dart SDK 自身的惯例,如 `int.parse` / `int.tryParse`)。

### 5.4 异步契约

- **MUST**:任何可能耗时超过毫秒级的操作返回 `Future`,不提供同步阻塞版本。
- **MUST**:所有网络类操作提供 `Duration? timeout` 参数,或在文档中说明默认超时值。
- **SHOULD**:长时间运行的操作支持取消。Dart 没有内置 `CancellationToken`,推荐通过 `StreamSubscription.cancel()` 或自定义 token 表达。
- **MUST**:返回 `Stream` 的 API 必须在文档中说明是**单订阅**还是**广播**流,以及关闭时机。这是最容易出错、也最容易被忽略的文档项。

---

## 6. 版本管理与演进

### 6.1 语义化版本(MUST)

严格遵循 [SemVer 2.0](https://semver.org/lang/zh-CN/) + Dart 生态惯例:

| 变更类型 | 版本位 | 例 |
|---|---|---|
| 修 bug,不改 API | patch `1.2.x` | 修正边界判断 |
| 新增 API,向后兼容 | minor `1.x.0` | 加一个新方法、加带默认值的命名参数 |
| 破坏兼容 | major `x.0.0` | 删/改任何公开符号 |
| `0.x` 阶段 | `0.x.y` 中 **x 位即 major** | `0.3.0 → 0.4.0` 视为破坏性 |

**Dart 特有的坑:`0.x` 版本的破坏性变更要升 `x` 而不是 `y`**,因为 pub 的 caret 约束 `^0.3.1` 只允许 `>=0.3.1 <0.4.0`。这一点和某些语言生态的直觉不同,写错会直接把破坏性变更推给所有下游。

### 6.2 什么算破坏性变更(必须背下来)

**是**破坏性变更:

- 删除或重命名任何公开的类、方法、字段、枚举值、typedef
- 修改公开方法的参数类型、返回类型、参数顺序
- 新增**必填**参数;把可选参数改成必填
- 给公开的 `abstract class` / `interface class` **新增成员**(所有实现者都会编译失败)
- 给 `enum` 新增值(下游的穷尽 `switch` 会失败)
- 收窄返回值类型或放宽入参可空性以外的类型变动
- 提高 Dart SDK 下限、提高依赖包的版本下限
- 改变已文档化的行为,即使签名不变(比如"返回空列表"改成"抛异常")

**不是**破坏性变更:

- 新增带默认值的命名参数(前提是该方法不在需要下游实现的接口上)
- 新增类、新增顶层函数
- 内部实现优化、性能改进
- 补充文档、修 typo
- 放宽依赖版本上限

**最容易被误判的两条是「给接口加方法」和「给枚举加值」。** 它们看起来只是"新增",但因为 Dart 3 有穷尽性检查和显式实现契约,对下游是硬伤。规避手段:接口用 `base`/`final` 限制实现者,或为新方法提供默认实现(用 `mixin` 或 `abstract class` + 具体方法);枚举则考虑改用 `sealed class` 或在文档里明确"本枚举可能新增值,请始终写 default 分支"。

### 6.3 弃用流程(MUST)

**禁止直接删除公开 API。** 必须走完整流程:

```dart
/// 解析 [raw] 并返回消息。
///
/// 已弃用:请改用 [parse],新方法有明确的异常分类。
@Deprecated('改用 parse();将在 3.0.0 移除。见迁移指南 doc/migration-2to3.md')
Message parseMessage(Uint8List raw) => parse(raw);
```

流程要求:

1. 在 minor 版本标记 `@Deprecated`,消息里**必须**包含:替代方案、计划移除的版本号、迁移文档链接。
2. 至少保留**一个完整的 major 周期**,或不少于 6 个月。
3. 在 CHANGELOG 中单列 "Deprecated" 段落。
4. 真正删除时,在 major 版本的 CHANGELOG 顶部写清楚,并提供 `doc/migration-xtoy.md`。

### 6.4 CHANGELOG(MUST)

pub.dev 会直接展示 CHANGELOG,格式不规范会掉分。约束:

- 每个已发布版本一个 `## x.y.z` 标题,倒序排列,版本号必须与 `pubspec.yaml` 完全一致。
- 分类使用固定小标题:`Breaking`、`Added`、`Changed`、`Deprecated`、`Fixed`、`Removed`。
- **面向用户写,不是面向自己写。** 写"修复了空报文导致的崩溃",不写"修复 parser.dart 第 42 行"。
- 破坏性变更必须给出**迁移前后的代码对比**。

````markdown
## 2.0.0

### Breaking

- `parse()` 现在在长度不足时抛出 `ParseException` 而非返回 `null`。

  ```dart
  // 旧
  final m = parser.parse(bytes);
  if (m == null) handleError();

  // 新
  try {
    final m = parser.parse(bytes);
  } on ParseException catch (e) {
    handleError(e.kind);
  }
  ```

### Added

- 新增 `parser.tryParse()`,返回 `ParseResult` 而不抛异常。

### Fixed

- 修复了 v1 报文长度字段被按 v2 语义解释导致的越界读取。
````

### 6.5 依赖约束(MUST)

- `dependencies` 用 caret 约束(`^1.2.0`),**不要**锁死具体版本,也**不要**用无上限的 `any`。前者制造依赖冲突,后者让下游在上游发布 breaking change 时随机爆炸。
- 依赖数量**尽可能少**。每个依赖都是你强加给下游的版本约束。只用到一两个工具函数时,自己实现比引依赖便宜。
- 开发期工具(`test`、`lints`、`build_runner`)一律放 `dev_dependencies`。
- SDK 下限设成你**实际测试过**的最低版本,不要无脑写当前版本——那会把用旧 SDK 的用户拒之门外。

---

## 7. 测试约束

### 7.1 测试分层

UI 包没有平台通道测试,但 widget 测试是**主力**而非补充,共三类:

| 层次 | 占比 | 对象 | 特征 |
|---|---|---|---|
| 单元测试 | ~50% | `controller/` 与算法(分页、偏移换算、导航状态机) | 零渲染、毫秒级,失败定位精确 |
| Widget 测试 | ~40% | `views/` `widgets/` 的渲染与交互 | `pumpWidget` + 手势 / `pump(duration)` 驱动动画 |
| 端到端测试 | ~10% | 入口 Widget + 假数据源 | 走完整链路,验证公开 API 真的能接起来 |

**优先把断言下沉。** 能用单元测试表达的,不要写成 widget 测试:后者慢、脆,且失败时要在 widget 树里找原因。典型的下沉对象:页偏移前缀和、付费章的可见页数、自动翻页的开关状态机 —— 它们都不需要渲染就能断言。

**目录约定:**

- 逻辑测试**必须**镜像 `lib/src/`:`lib/src/controller/pagination_mixin.dart` → `test/controller/pagination_mixin_test.dart`。它让"这个文件有没有测试"一眼可见。
- 交互测试**按功能**分文件(`reader_flip_test.dart`、`reader_notes_test.dart`、`reader_lock_test.dart`…),**MUST NOT** 把所有 widget 测试堆进一个巨型文件。单文件超过约 300 行就拆 —— 否则没人愿意在里面加用例,也没人找得到已有用例。

### 7.2 覆盖率(MUST)

- `lib/src/controller/` 行覆盖率 **≥ 90%**。这一层不依赖渲染,达不到 90% 只可能是懒,不可能是难。
- 全包整体行覆盖率 **≥ 80%**。
- CI 必须计算覆盖率并在低于门槛时失败,不能只是"生成个报告没人看"。

**存量项目的落地方式:用棘轮,不要一刀切。** 对已有代码直接卡 80% 只有两种结果——要么大量补低质量测试凑数,要么门槛被注释掉。正确做法是把**当前实测值**写进 CI 作为基线,规则是"只许涨不许跌",每次提交若下降即失败;随功能开发逐步抬高基线,直到达到上面的目标值。绘制类代码(`CustomPainter.paint`)的行覆盖意义有限,可从分母中排除,但**几何计算函数不能排除**。

**同时要警惕覆盖率的欺骗性。** 100% 覆盖不等于没 bug,它只保证每行被执行过,不保证断言有意义。所以配套要求:**每个测试至少有一个 `expect`,禁止只调用不断言的"覆盖率刷分测试"**;分支密集的逻辑必须用 `test/` 的参数化写法覆盖边界值(0、1、最大值、空、超长)。

### 7.3 Fake 优先于 Mock(SHOULD)

依赖有抽象接口后,测试替身有两种写法。**优先手写 fake:**

```dart
// ✅ Fake:有真实行为的轻量实现,可复用,重构时编译器帮你发现问题
final class InMemoryMessageSource implements MessageSource {
  InMemoryMessageSource(this._data);
  final Map<String, Uint8List> _data;

  @override
  Future<Uint8List> fetch(String id) async {
    final bytes = _data[id];
    if (bytes == null) throw StateError('no such id: $id');
    return bytes;
  }
}
```

**为什么不首选 mockito。** mock 断言的是"调用了什么方法、几次、什么参数",这把测试和**实现细节**绑死了——你重构内部调用顺序,业务行为没变,测试却红了。这类测试的维护成本会随时间失控。fake 断言的是"最终状态和返回值",只和行为有关。

**mock 仍有合理场景:**验证"异常路径确实触发了重试"这类难以用状态观察的交互,或者被替身的接口极大而你只关心一个方法。此时用 mock 是对的,但要意识到你在为此支付脆弱性成本。

### 7.4 测试书写规范

- 测试名用**行为描述**,不用方法名:`test('returns null when the buffer is shorter than the header', ...)`,不是 `test('parse test', ...)`。测试失败时,名字就是错误报告。
- 每个测试**一个断言主题**;多个 `expect` 可以,但都应服务于同一个结论。
- 用 `group()` 按被测方法或场景组织。
- **MUST NOT** 让测试依赖真实时间 / 真实网络 / 执行顺序。需要时间推进用注入的时钟或 `fakeAsync`。
- **MUST** 为每个修复的 bug 补一条回归测试,并在测试名里带上 issue 号:`test('regression #42: handles zero-length payload', ...)`。

### 7.5 示例即测试(SHOULD)

`example/` 里的代码**必须能编译通过**,并纳入 CI 的 `dart analyze` 范围。同时,文档注释里的 ` ```dart ` 代码块应当能通过 `dart doc` 校验。

**理由很实际:文档里的代码是用户最先复制的东西,也是最容易腐烂的东西。** 一段编译不过的示例带来的信任损失,比缺少示例大得多。

---

## 8. CI 与发布

### 8.1 CI 必备关卡(MUST)

任何 PR 合并前必须全绿:

**Flutter 包必须用 `flutter` 命令,不能用 `dart`** —— `dart test` 跑不了 widget 测试(缺 `flutter_test` 的绑定),`dart analyze` 也拿不到 Flutter 的分析配置。

```yaml
# .github/workflows/ci.yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - run: flutter pub get
      - run: flutter pub get --directory=example

      # 1. 格式:不一致直接失败
      - run: dart format --output=none --set-exit-if-changed lib test example/lib

      # 2. 静态分析:**不要传路径参数**(原因见下),包与示例各analyze一次
      - run: flutter analyze
      - run: flutter analyze --no-pub
        working-directory: example

      # 3. 测试 + 覆盖率
      - run: flutter test --coverage
      - name: Enforce coverage ratchet
        run: |
          sudo apt-get update && sudo apt-get install -y lcov
          lcov --summary coverage/lcov.info 2>&1 | tee summary.txt
          pct=$(grep -oP 'lines\.*: \K[0-9.]+' summary.txt)
          base=$(cat .coverage-baseline 2>/dev/null || echo 0)
          echo "line coverage: $pct% (baseline $base%)"
          awk -v p="$pct" -v b="$base" 'BEGIN { exit (p + 0.5 >= b) ? 0 : 1 }'

      # 4. 发布体检:pana 评分低于阈值失败
      - run: flutter pub global activate pana
      - run: flutter pub global run pana --exit-code-threshold 0 .

      # 5. 干跑发布,提前发现打包问题
      - run: flutter pub publish --dry-run
```

**关于 SDK 矩阵。** 纯 Dart 版本建议对 `[SDK 下限, stable]` 各跑一遍。Flutter 包同样值得,但 `subosito/flutter-action` 需要指定具体 Flutter 版本(而非 Dart 版本),维护成本略高;**至少**要保证 `environment:` 里声明的下限是你**真的验证过**的版本,不要顺手写成当前开发机的版本。

**关于 `--fatal-infos`。** 它把所有 lint 提示都变成 CI 失败。这条会被抱怨"太严",但请对比另一条路:允许 warning 存在,则 warning 数量只会单调增长,三个月后没人再看分析输出,lint 配置形同虚设。**分析结果必须始终为零,才有信号价值。**

**`flutter analyze` MUST NOT 带路径参数。** 一旦写成 `flutter analyze lib test`,分析器就只看这些目录,**根目录的 `pubspec.yaml` 被整个跳过** —— 而 `sort_pub_dependencies`、`depend_on_referenced_packages` 这类规则恰恰作用在 pubspec 上。后果是本地和 CI 全绿,发布时 pana 却扣分,且没人知道为什么。

```bash
# ❌ 看着更"精确",实则漏掉 pubspec.yaml,pana 会替你发现
flutter analyze lib test example/lib

# ✅ 整包分析;example 是独立的包,单独再 analyze 一次
flutter analyze
(cd example && flutter analyze --no-pub)
```

> 真实事故:`dev_dependencies` 里 `flutter_test` 排在 `flutter_lints` 前面(字母序应反过来),本地 `flutter analyze lib test example/lib` 一直是 "No issues found",直到 pana 报 `Dependencies not sorted alphabetically` 扣掉 10 分。
>
> **推论(适用于所有工具):凡是能整包跑的检查,就不要用路径参数缩小范围。** 缩小范围省下的那点时间,远不如漏检一次的代价。

### 8.2 pub.dev 评分项(MUST)

发布前用 `flutter pub global run pana .` 自查,以下几项必须满分:

- **约定俗成的文件**:`README.md`、`CHANGELOG.md`、`LICENSE`(用标准 OSI 协议文本,不要自己改)、`example/`。
- **文档覆盖**:公开 API 的 dartdoc 覆盖率 ≥ 20%。
- **平台支持**:Flutter UI 包的目标是拿到**全部 Flutter 平台**标签(Android / iOS / Web / macOS / Windows / Linux),**不包含**服务端与 CLI —— 后者对 UI 包不适用,缺失是正常的,不是架构违规。但若某个 **Flutter 平台**标签缺失,说明你误引了平台专属 API(如 `dart:io`、`dart:html`)或某个原生插件,**必须修**。
- **依赖健康**:所有依赖都在最新兼容版本,无已废弃包。理想状态是 `dependencies` 只有 `flutter` 本身(见 [3.6](#36-明确禁止项must-not) 对原生插件的禁令)。
- **null safety + 最新 SDK 兼容**。

`pubspec.yaml` 必须填写 `description`(60–180 字符,pana 有硬性长度检查)、`homepage`/`repository`、`issue_tracker`、`topics`。

### 8.3 发布检查清单(MUST 逐项确认)

发布是不可逆的——**pub.dev 上的版本永远无法删除,只能 retract**。所以这份清单每次都要走完:

- [ ] `pubspec.yaml` 的 `version` 与 CHANGELOG 顶部标题一致
- [ ] CHANGELOG 已按 6.4 的格式写完,破坏性变更有迁移示例
- [ ] 版本号升位符合 6.2 的判定(尤其确认没有把 breaking 藏进 minor)
- [ ] `dart pub publish --dry-run` 无警告
- [ ] `pana` 评分无扣分项
- [ ] `example/` 能跑通,README 里的代码片段与当前 API 一致
- [ ] 所有 `@Deprecated` 消息里的"将在 x.y.z 移除"仍然准确
- [ ] 新增的公开符号都有 dartdoc,且确实**需要**公开
- [ ] 在 SDK 下限版本上测试通过
- [ ] 打了 git tag `vX.Y.Z`,且 CI 在该 commit 上全绿

**推荐用 CI 自动发布**(GitHub Actions + pub.dev 的 OIDC 自动化发布),避免本地环境差异和手滑发错版本。

---

## 9. Code Review 检查清单

Reviewer 按这个顺序看,**从代价最高的问题看起**:

**第一优先:公开 API 变更**

- [ ] 有新增的公开符号吗?每一个都必要吗?能不能先私有?
- [ ] 是破坏性变更吗?版本号升对了吗?
- [ ] 新公开的东西有 dartdoc 吗?写了会抛什么异常吗?

**第二优先:架构与依赖**

- [ ] `controller/` 有没有 import `material.dart` / 构建 Widget / 摸 IO、时间、随机数?
- [ ] 有没有新增第三方依赖?**是不是原生插件?** 能不能改成由宿主注入?
- [ ] 改了 `pubspec.yaml` 吗?依赖是否按字母序?(见 [8.1](#81-ci-必备关卡must):带路径的 `flutter analyze` 查不到 pubspec)
- [ ] 有没有新的全局/静态可变状态?

**第二优先补充(UI 包专属,详见 [§11](#11-flutter-ui-包专属约束必读)):**

- [ ] 新增文案:12 种语言预设都补了吗?(覆盖度测试会挡)
- [ ] 每帧变化的绘制:走 `CustomPainter` 还是在重建 widget 树?
- [ ] 新建的 `AnimationController` / `Ticker` / `ScrollController` / `OverlayEntry` 在 `dispose` 里释放了吗?
- [ ] 有没有在 `State` 自己的 `context` 上查自己创建的 `InheritedWidget`?
- [ ] 新增的持久化调用有没有错误出口?

**第三优先:正确性**

- [ ] 错误处理:有没有裸 catch?异常类型是本包的吗?`Error` 和 `Exception` 分清了吗?
- [ ] 空安全:有没有 `!` 强解包?能证明它安全吗?
- [ ] 异步:有没有未 await 的 Future?资源释放了吗?
- [ ] 边界:空输入、单元素、超大输入测了吗?

**第四优先:可读性**

- [ ] 函数超过 40 行 / 嵌套超过 3 层了吗?
- [ ] 命名诚实吗?有没有需要注释才能懂的条件表达式?
- [ ] 注释写的是"为什么"而不是"是什么"吗?
- [ ] 有没有被注释掉的死代码?

**Reviewer 的元规则:如果你在 review 中要求了某件事三次以上,把它变成一条 lint 规则或 CI 检查。** 人肉执行的规范一定会衰减,自动化的不会。

---

## 10. 附录:可直接复制的模板

### 10.1 `pubspec.yaml`

```yaml
name: my_widget_package
description: >-
  A customizable Flutter widget for XX, with pluggable data sources and
  progress storage, and no native plugin dependencies.
version: 0.1.0
repository: https://github.com/org/my_widget_package
issue_tracker: https://github.com/org/my_widget_package/issues
topics: [widget, reader, ui]

environment:
  # 下限必须是你真的验证过的版本
  sdk: ">=3.6.0 <4.0.0"
  flutter: ">=3.27.0"

dependencies:
  flutter:
    sdk: flutter
  # 除 flutter 外尽量为空;原生插件一律交给宿主

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

### 10.2 不可变模型骨架

```dart
// lib/src/reading_position.dart
import 'package:meta/meta.dart';

/// 一个带过期时间的访问令牌。
@immutable
final class Token {
  /// 创建一个在 [expiresAt] 之后失效的令牌。
  const Token({required this.value, required this.expiresAt});

  /// 令牌字符串本身。
  final String value;

  /// 过期时刻,始终为 UTC 时间。
  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      other is Token && other.value == value && other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(value, expiresAt);

  @override
  String toString() => 'Token(expiresAt: $expiresAt)'; // 不打印 value,避免泄密
}
```

注意最后一行:**`toString()` 不得输出敏感信息**。令牌、密码、密钥一旦进了日志就等于泄露,而 `toString()` 是它们最常见的泄露路径。这条应当加进 Review 清单。

### 10.3 单元测试骨架

```dart
// test/controller/token_validator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:my_widget_package/my_widget_package.dart';

void main() {
  group('TokenValidator.isExpired', () {
    final expiry = DateTime.utc(2026, 1, 1, 12);
    final token = Token(value: 'x', expiresAt: expiry);

    TokenValidator validatorAt(DateTime now) =>
        TokenValidator(now: () => now);

    test('returns false one second before expiry', () {
      final validator = validatorAt(expiry.subtract(const Duration(seconds: 1)));
      expect(validator.isExpired(token), isFalse);
    });

    test('returns false exactly at expiry (boundary is inclusive)', () {
      expect(validatorAt(expiry).isExpired(token), isFalse);
    });

    test('returns true one second after expiry', () {
      final validator = validatorAt(expiry.add(const Duration(seconds: 1)));
      expect(validator.isExpired(token), isTrue);
    });
  });
}
```

三个用例覆盖了边界的两侧和边界本身——**边界值测试是纯逻辑层最高性价比的测试**,大多数逻辑 bug 都躲在 `>` 和 `>=` 之间。

---

## 11. Flutter UI 包专属约束(必读)

前十节的骨架对任何包都成立。这一节是**只有 UI 组件包才会踩的坑**,也是本仓库 Review 时命中率最高的部分。每一条都来自真实事故。

### 11.1 多语言完整性(MUST)

包内置文案预设时(如 `ReaderLabels` 的 12 种语言),**每个语言预设必须覆盖全部文案字段**。

**为什么这条要单列。** 未提供的字段会**静默回退英文** —— 不报错、不警告、分析器也不管。结果是日语用户看到日语的顶栏,但笔记面板、评论、相对时间、自动翻页全是英文。而新增一个文案时,只改英文默认值和母语预设就能编译通过,**缺口会随每次功能开发单调增长**。本仓库曾累积到 10 种语言各缺 25 个字段才被发现。

**MUST:** 用测试守卫,而不是靠人记 —— 解析源码比对"构造器字段"与"各预设已设字段",缺失即失败并列出字段名。见 `test/reader_labels_coverage_test.dart`。

**同样适用于示例 App 的 ARB 文件**:新增 key 必须同步全部语言,`flutter gen-l10n` 不会为缺失项报错。

### 11.2 渲染性能(MUST)

`build()` 和每帧回调是**热路径**,下面几条不是"优化建议"而是硬约束:

| 要求 | 反例 | 正例 |
|---|---|---|
| 每帧变化的绘制走 `CustomPainter` | 每帧重建 `Stack + DecoratedBox + LinearGradient` 画阴影 | `CustomPaint(foregroundPainter: …)` + `shouldRepaint` 精确比较 |
| 整页不变量提到 build 之外 | 每次 build 都 `TextPainter.layout()` 量缩进宽度、重新统计段评数 | 在 `initState` / `didUpdateWidget` 算一次并缓存,键上带失效条件 |
| 用前缀和替代重复累加 | 每个段落都从头累加块长度求偏移(单页 O(n²)) | 一次算出前缀和数组,后续 O(1) 查表 |
| 布尔路径运算能省则省 | 每帧 5 次 `Path.combine` | 用集合等价改写 + `canvas.clipPath`,把 CPU 布尔运算降到最少 |
| 列表 / 分页惰性构建 | 一次性构建整章所有段落 | `ListView.builder` / `PageView.builder`;必要时只渲染预览片段 |
| 动画交给 `AnimationController` | `Timer.periodic` 自己数帧 | `AnimationController` + `vsync`(测试里可被 `pump` 精确驱动) |

**`shouldRepaint` 必须逐字段比较,不能恒 `true`,也不能恒 `false`。** 恒 `true` 等于没优化;恒 `false` 会让画面停在旧帧 —— 后者更危险,因为它在开发机上"看起来偶尔对"。

### 11.3 主题与无障碍(MUST)

- **所有颜色取自主题对象,禁止硬编码**。包内置多套纸张主题(含夜间),写死 `Colors.white` 会在夜间主题下变成亮斑。
- **遮罩 / 蒙层的颜色必须与背景有对比**。在浅色纸张上叠半透明白 = 看不见;要么用背景色做渐隐(内容淡出),要么用反相色做磨砂(可见的膜) —— **先明确要哪一种效果**,再选颜色。这条曾让一层"蒙层"反复调了四轮才对。
- **系统字体缩放必须生效**:排版度量与渲染共用同一个 `MediaQuery.textScaler`,不得在度量时忽略它 —— 否则大字体用户会看到末行被裁切。
- **交互元素给 `Semantics`**:翻页区、菜单按钮、进度需要可被读屏识别;纯装饰性绘制用 `ExcludeSemantics`。
- **触摸目标不小于 44×44 逻辑像素**。为了"小巧"把按钮压到 20px 高,等于让手指粗的用户点不中。

### 11.4 生命周期与资源(MUST)

`State` 里创建的所有下列对象,**必须**在 `dispose()` 中释放,且顺序为"先摘监听,再销毁对象":

`AnimationController` / `Ticker` / `ScrollController` / `PageController` / `TextEditingController` / `FocusNode` / `ValueNotifier` / `StreamSubscription` / `Timer` / `OverlayEntry`

补充要求:

- **`addListener` 与 `removeListener` 必须成对**,且 `didUpdateWidget` 里换对象时要先摘旧的再挂新的。
- **`OverlayEntry` 要在 `dispose` 前 `remove()`**,否则浮层会残留在上一个路由上。
- **`InheritedWidget` 的 `updateShouldNotify` 要精确**:恒 `true` 会让整棵子树每次都重建,抵消掉分作用域的意义。
- **多个作用域按"变化频率"分组**:高频变化的(电量、朗读进度)单独一层,低频的(文案、主题)合并 —— 这是分多个 `InheritedWidget` 而不是合成一个大对象的唯一正当理由;若某层不再高频,应合并回去。

### 11.5 Flutter 特有陷阱(MUST)

**陷阱一:不要在 `State` 自身 `context` 上查询自己创建的 `InheritedWidget`。**

```dart
// ❌ ReaderLabelsScope 是本 State 在 build 里创建的,位于自己子树中;
//    dependOnInheritedWidgetOfExactType 只向上找祖先 → 取不到 → 静默回退英文默认值
final labels = ReaderLabels.of(context);

// ✅ 直接用数据源本身
final labels = widget.labels;
// ✅ 或把读取下沉到子 Widget 的 build(它才是 scope 的后代)
```

这个 bug 不会报错、不会崩溃,只会让界面显示默认语言 —— 极难察觉。本仓库因此有过一次"自动翻页文案永远是英文"的线上表现。

**陷阱二:改 `static const` 后必须热重启(`R`),热重载(`r`)不生效。** 调样式时若"改了没反应",先确认这一点,不要凭"没效果"去改逻辑。

**陷阱三:`Align` / `Center` 下的 `SizedBox` 只给一个维度会导致另一维塌陷。** 只写 `width` 不写 `height` 时,松约束下高度会变 0 —— 表现是"元素不见了",而颜色 / 层级怎么调都没用。

**陷阱四:`SafeArea` 与页面内部的固定内边距是两套基准。** 悬浮元素若想和页脚"同一行",应锚定页脚那条带的几何(内边距 + 带高),而不是各自套 `SafeArea` —— 否则会差出一个安全区高度。

**陷阱五:系统栏用 `edgeToEdge` 而非 `SystemUiMode.manual`。** 后者会改变窗口尺寸 → 触发正文重新分页 → 唤起菜单时"跳一页"。

### 11.6 给宿主留错误出口(MUST)

包对宿主提供的 `store` / `source` 的**写入**调用,不得静默丢弃失败。

```dart
// ❌ fire-and-forget:宿主的存储挂了(磁盘满 / DB 锁 / 网络失败),
//    异常进入未捕获的 zone,用户与宿主都毫不知情,书签"看着加上了"其实没落盘
widget.bookmarkStore.save(bookId, next);

// ✅ 至少显式声明意图,并把失败交给宿主
unawaited(
  widget.bookmarkStore
      .save(bookId, next)
      .catchError(widget.onStoreError ?? _ignore),
);
```

**MUST:** 入口 Widget 提供可选的 `onStoreError(Object error, StackTrace stack)`;默认 `null` 时保持现有行为(不崩),但**必须**在文档里写明"不传则失败被忽略"。

**MUST:** 开启 `unawaited_futures` lint —— 它是这条规则的自动化执行者。任何未 `await` 的 Future 都要显式 `unawaited(...)`,迫使作者当场回答"这个失败谁来管"。

---

## 结语:这份规范该怎么用

不要试图一次性把老项目改成全绿。推荐的落地顺序,按"收益 / 改造成本"排序:

1. **先上 `analysis_options.yaml` 和 CI 的 format + analyze**。一天能完成,立刻止住新代码的腐化。
2. **再补 [§11.1](#111-多语言完整性must) 的文案覆盖度测试**。成本极低(一个测试文件),却能挡住一整类静默劣化。
3. **然后补 `lib/src/` 目录隔离和入口 `export ... show`**。这是内部重构,对下游零影响,却换来长期的重构自由。
4. **接着补 `controller/` 的测试和覆盖率棘轮**。从最核心的纯逻辑开始,不追求一次到 90%,先把当前值定为基线、只许涨不许跌。
5. **最后统一错误模型([§11.6](#116-给宿主留错误出口must))和版本流程**。前者可以在 minor 版本以"新增可选回调"的方式落地,不必等 major。

规范的价值不在于写得多全,而在于**有多少条被自动化执行了**。每次你想往这份文档里加一条规则时,先问一句:它能不能变成一条 lint 或一行 CI 脚本?能,就去改配置,文档里只留一句说明;不能,才写成需要人来遵守的条文——并且要明白,这类条文的实际遵守率永远低于你的预期。


