# 此记 · ThisNote

> 一张安静的纸，装得下日记、随笔和作文。  
> 本地优先 · 原生 Windows / Android · 中文书写体验优先

**中文** · [English](README.en.md) · [GitHub](https://github.com/cookernine91263/ThisNote) · [B 站](https://space.bilibili.com/628622329)

「此记」是一个**不联网也能好好写字**的桌面与移动写作空间。它把 Word 式的排版能力、日记应用的时间感、以及一点点东方的留白，收进同一个界面里。界面支持**中文 / English** 随时切换，首次启动的引导页就能直接选。

![首页](docs/screenshots/home.png)

## 为什么是「此记」

很多笔记软件在争夺你的注意力：消息、协作、AI 弹窗、订阅提醒。  
「此记」反其道而行——打开就是纸，写完就保存，所有内容留在本机。

设计上只保留三种颜色：**宣纸的暖白、墨的黑、朱砂的一点红**。没有渐变按钮，没有彩色图标，没有需要学习的新概念。

## 功能

### 2.0 新增

- **打字机模式 / 段落聚焦**：光标停在纸中央；只留下正在写的那一段，其余文字轻轻淡去
- **中文文风检查**：离线标出口水词、重复词、长句、连续标点与多余空格，点一下跳到那一句
- **全局搜索替换**：Ctrl/⌘ + Shift + H，跨所有笔记替换，替换前逐篇留历史版本
- **笔记链接与反链**：在「更多」里插入 `[[标题]]`，前后文自动连起来
- **收藏视图 / 完整标签页**：写过又舍不得删的文字有了自己的位置
- **单篇字数目标 / 写作时长**：每日目标之外，再给这一篇一个落点
- **版本对比**：恢复历史版本前先看清改了什么
- **桌面多标签页 / 分屏**：Ctrl/⌘ + Tab 切换，Ctrl/⌘ + W 关闭；两栏可以同时写两篇
- **表格块**：在工具栏插入表格，按 Tab 分隔单元格编辑，DOCX / PDF / HTML / Markdown 都能带走
- **模板与每日日记**：把当前笔记存成模板，支持 `{{date}}` / `{{weekday}}`；命令面板一键打开今天的日记
- **互操作**：新增 EPUB 导出、DOCX 导入与系统打印（先生成 PDF，再交给系统阅读器）
- **手机手势与分享**：列表左滑删除、右滑收藏；其他应用分享的文字/链接可直接落成新笔记
- **更安全**：API Key 与 WebDAV 密码存进系统钥匙串；`library.json` 只留摘要，全文进入独立索引
- **崩溃恢复**：异常退出后，比磁盘更新的草稿会在下次启动时询问是否捡回
- **冲刺与目录**：25 分钟写作冲刺；大纲可以一键插入目录
- **更轻的安装包**：字体按通用规范汉字子集化，Windows 安装包 53 → 24 MB，Android APK 79.5 → 38 MB；罕见字自动回退系统字体，仍可导入自己的完整字体
- **更快的启动与保存**：先出纸再读库；打字不再每次编码整篇文档；PDF 字体按需加载

### 写作

- **中文 / English 界面**：引导页与设置里都能切换，切换后立即生效，笔记内容不会被改写
- Word 式富文本：加粗 / 倾斜 / 变细 / 下划线 / 删除线 / 标题 1–3 / 引用 / 代码块 / 有序、无序、待办列表 / 对齐 / 缩进 / 文字颜色 / 高亮 / 链接 / 图片 / 分隔线
- **代码块卡片**：选择 Python / C++ / HTML 等语言，正文里按语言实时高亮，可整块编辑、复制或删除
- **待办勾选即删除线**：打勾后文字自动划掉，取消勾选自动恢复，导出 Word / PDF / HTML 也保留
- **手机端手势**：底部液态导航；列表顶部直接切换今日 / 全部 / 标签 / 回收站；卡片 `⋯` 可置顶、收藏、复制或删除
- **一键花字**：选中一句话，从 8 种花字气质中选择，立刻变为大字号文楷 + 专属颜色（小 / 中 / 大三档）
- 查找替换（Ctrl/⌘ + F、Ctrl/⌘ + H）、标题大纲、选中字数、复制为 Markdown / 纯文本、粘贴为纯文本
- **整理排版**：一键处理中英文之间的空格、半角标点、省略号与多余空格（有选区只整理选区）
- 图片点开即可调宽度（25/50/75/100%）、左中右对齐、替换或删除；PDF / Word 导出会保留宽度与对齐
- **截图直接粘贴**：剪贴板里只有图片时，点工具栏「粘贴图片」即可落到光标处（部分输入法会拦截 Ctrl/⌘ + V，所以保留了一个明确的按钮入口）
- **拖拽**：把图片拖进窗口就插入当前笔记；把 `.md` / `.txt` 拖进来会直接导入成新笔记
- 内置 8 种开源字体：思源黑体、思源宋体、霞鹜文楷、马善政毛笔、站酷小薇、思源细体、得意黑、思源等宽；工具栏可直接切换并实时预览
- **导入自己的字体**：从本机挑一个 TTF / OTF，存进数据目录，重启后依然可用（只在这台设备上显示）
- **写作时长**：按实际动笔累计，停顿超过一分钟不计入；旧笔记会用创建到修改的跨度做一次保守估计
- **自定义色盘**：色相/明度轮盘、内置色、常用色收藏；文字色与高亮色都可自选
- 自动保存、5 分钟自动版本快照（最多 40 个）、撤销 / 重做
- 专注模式、纸纹、深色模式、界面字号 / 正文字号 / 行距 / 段间距 / 字间距 / 页宽 / 强调色可调；数值可直接填写，大整数自动吸附
- 深/浅色切换从点击位置圆形扩散，文字不缩放
- 文件夹以卡片和笔记排在同一列表；拖到文件夹卡片中间即可放进去，拖到上/下边缘是普通排序，拖近列表边缘会自动滚动；支持多选批量操作与「固定」
- 删除笔记时卡片快速收起，底部出现「撤销」，五秒内都能恢复
- 命令面板（Ctrl/⌘ + K）：搜任一篇笔记、执行格式命令、查找 / 目录 / 整理排版 / 导出

### 日记与整理

- 日记 / 随笔 / 作文三种体裁，以及 7 种起始模板
- 日历视图：月历、写作热力、心情圆点、「那年今日」
- 心情（5 种）与天气（6 种）记录
- 标签（输入时自动补全写过的标签）、置顶、收藏、回收站（可恢复 / 永久删除）
- 文件夹卡片（可嵌套）与笔记同列表、拖拽归类与排序、「时间」视图、多选批量整理、固定不参与排序
- 今日目标、连续写作天数

### 统计

- 总字数 / 总篇数 / 连续天数 / 今日进度（数字滚动，卡片可点击）
- 最近 7 天柱状图：点任意一天看当天篇目与字数
- 最近一年写作热力图：悬停看日期，点格子回看当天
- 体裁分布、高频标签（标签可点击进入筛选）

### 导出与数据

- **Word (.docx)**：真实列表编号、标题样式、待办删除线、代码块、引用、图片与链接
- **PDF**：A4 版式，嵌入中英日字体；代码块使用等宽字体，待办勾选保留删除线
- **PNG 长图 / 分页**：重新排版成可收藏的纸页，提供 4 种纸色、日期/标签开关与 3× 分辨率；长文可以自己决定导出几张、每一张截止在哪一段（断点还能前后微调），发到社交平台也不会被压糊
- **HTML / Markdown / TXT**：代码块保留语言，列表与待办导出为语义标签
- 完整备份 zip（正文、图片、历史版本、AI 对话），一键恢复
- **整库导出为 Markdown 文件夹**（图片与 `assets/` 一起带走）
- **导入 Markdown / 纯文本**：标题、粗斜体、行内代码、链接、列表、引用、代码块（含语言）、分隔线都会保留；也可以直接把文件拖进窗口
- WebDAV 备份上传 / 恢复（自己的服务器或坚果云）

### AI（可选，默认关闭）

- 任意 OpenAI 兼容接口（DeepSeek / OpenAI / 本地网关均可）
- **多轮对话**：按笔记保存聊天记录，关掉再打开还在；可清空、重试、中途停止
- 润色、扩写、压缩、续写、起标题、生成提纲、英/日翻译；结果可插入、替换选中或用作标题
- **思考强度**：快 / 标准 / 深入三档，自己决定给模型多少时间与预算
- **一键测试连通性**：只发一句「收到」，立刻知道地址、模型和 Key 有没有填对
- 兼容思考型模型：只返回思考内容、网关不认 SSE 时会自动改用非流式再试一次
- **先生成、后预览、再写入**，不会偷偷改你的稿子
- 流式输出：边生成边读，随时可以「停止」
- API Key 只存在本机；只有点击 AI 动作时才发送选中文字

### 隐私

- 无账号、无广告、无追踪、无云端默认上传
- 4 位本地密码锁
- 所有数据是一个可以自己拷走的文件夹

## 界面

| 写作 | 花字 |
| --- | --- |
| ![编辑器](docs/screenshots/editor.png) | ![花字](docs/screenshots/huazi.png) |

| 日历 | 统计 |
| --- | --- |
| ![日历](docs/screenshots/calendar.png) | ![统计](docs/screenshots/stats.png) |

| 命令面板 | English 界面 |
| --- | --- |
| ![命令面板](docs/screenshots/palette.png) | ![English 界面](docs/screenshots/en/settings.png) |

![设置](docs/screenshots/settings.png)

首次启动会有一页简短的引导，右上角可以直接切换语言，最后一页还留了一个「去 GitHub 点个 Star」的小门（设置 →「关于此记」里可以随时重新查看）：

| 中文引导 | English 引导 |
| --- | --- |
| ![引导](docs/screenshots/onboarding.png) | ![English 引导](docs/screenshots/onboarding-en.png) |

## 给「此记」一点回声

它不联网、不弹窗、也没有订阅提醒，所以它真的只能靠你啦。

如果它陪你写下了几句真心话，去 [GitHub](https://github.com/cookernine91263/ThisNote) 点一颗 ⭐ 吧——
（小声：一颗小星星真的会让我开心一整天 ♡）

也可以在 [B 站](https://space.bilibili.com/628622329) 找到我，看看这个小小的写作空间是怎么一点点长出来的。
弹幕里打个招呼也好呀，我会回你的。

> 写下去，就已经很好了。剩下的，交给时间。

## 安装包

当前环境已生成：

- `dist/ThisNote-Setup-2.0.0.exe`（Windows x64 安装包，约 24 MB）
- `dist/ThisNote-Android-2.0.0-arm64.apk`（Android 8.0+ arm64，已签名，约 38 MB）
- `dist/SHA256SUMS.txt`

安装说明见 `dist/安装说明.txt`，更新内容见 `dist/release-2.0.0.md`。

## 技术栈

| 层 | 选择 |
| --- | --- |
| 框架 | Flutter 3.47.9 / Dart 3.13.7，Windows 使用 C++ runner + Dart AOT，Android 使用原生 embedding + Dart AOT；**没有 WebView** |
| 编辑器 | [flutter_quill 11.6](https://github.com/singerdmx/flutter-quill)，自定义工具栏、行内样式与导出 |
| 状态 | provider + ChangeNotifier |
| 存储 | 本地 JSON 文件（原子写入）+ 每篇独立文件 + 历史快照目录；无数据库依赖 |
| 导出 | `pdf`、`archive`（OOXML zip）、`xml`，自行构建 DOCX / PDF |
| 桌面 | `window_manager` 无边框窗口、自绘标题栏 |
| 字体 | Noto Sans SC（Light/Regular/Bold）、Noto Serif SC、LXGW WenKai、Ma Shan Zheng、ZCOOL XiaoWei、Smiley Sans、Source Han Mono；按通用规范汉字子集化，罕见字回退系统字体（`tools/subset_fonts.py`） |
| 图标 | Lucide Icons |
| 构建 | Windows：MSVC 2022 + Windows 11 SDK；Android：JDK 17 + Android SDK 36 + Gradle 9.3.1 |

### 目录

```
app/
  lib/
    main.dart                    启动、窗口、Provider
    src/
      app.dart                   MaterialApp / 主题 / 首屏门禁
      core/                      设计令牌、动效、格式化、中英文案、通用组件
      data/                      模型、文件仓库、模板与种子内容
      state/app_state.dart       应用状态 + 编辑会话
      features/                  页面与编辑器
      services/                  导出、AI、WebDAV
  assets/fonts/                  内置字体（OFL）
  test/                          字数和导出测试
installer/                       Inno Setup 安装包脚本
tools/                           字体准备、图标生成脚本
```

## 构建

### 依赖

- Flutter 3.47.9+（Dart 3.13.7）
- Windows：Visual Studio 2022 Build Tools（Desktop development with C++、Windows 11 SDK、CMake）
- Android：JDK 17、Android SDK Platform 36 / Build-Tools 36
- 安装包：Inno Setup 6

### Windows

```powershell
cd app
flutter pub get
flutter build windows --release --split-debug-info=build/symbols/windows
# 产物：build/windows/x64/runner/Release/this_note.exe
```

安装包：

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" ..\installer\ThisNote.iss
# 产物：dist/ThisNote-Setup-2.0.0.exe
```

### Android

准备签名文件 `android/key.properties`：

```properties
storePassword=...
keyPassword=...
keyAlias=thisnote
storeFile=thisnote-release.jks
```

```powershell
cd app
flutter build apk --release --target-platform android-arm64 `
  --split-debug-info=build/symbols/android --obfuscate
# 产物：build/app/outputs/flutter-apk/app-release.apk（arm64）
```

### 测试

```powershell
flutter test
```

## 数据位置

- Windows：`%APPDATA%\ThisNote\data`
- Android：应用私有目录下的 `ThisNote/`

结构：

```
data/
  library.json        列表索引
  settings.json       设置
  activity.json       每日实际写作字数（续写旧稿也算今天）
  notes/              每篇正文（Quill Delta + 纯文本）
  history/            历史快照
  assets/             插入的图片
```

直接复制整个 `data/` 文件夹即可迁移。设置里也可以生成 zip 备份。

## 快捷键

> 若系统输入法拦截了组合键，界面内所有功能都可以通过工具栏、侧栏与命令面板完成。

| 快捷键 | 动作 |
| --- | --- |
| `Ctrl/⌘ + K` | 命令面板 |
| `Ctrl/⌘ + N` | 新建随笔 |
| `Ctrl/⌘ + S` | 立即保存 |
| `Ctrl/⌘ + F` | 查找 |
| `Ctrl/⌘ + H` | 当前笔记内查找替换 |
| `Ctrl/⌘ + Shift + H` | 全局搜索替换 |
| `Ctrl/⌘ + Tab` | 切换标签页 |
| `Ctrl/⌘ + W` | 关闭当前标签页 |
| `Ctrl/⌘ + Shift + V` | 粘贴为纯文本 |
| `Ctrl/⌘ + B` | 加粗 |
| `Ctrl/⌘ + I` | 倾斜 |
| `Ctrl/⌘ + U` | 下划线 |
| `Ctrl/⌘ + Shift + F` | 专注模式 |
| `Ctrl/⌘ + ,` | 设置 |

## 设计说明

配色、排版、动效与交互约定见 [docs/DESIGN.md](docs/DESIGN.md)。

## 参考与致谢

这个项目站在许多开源项目的肩膀上：

- [flutter_quill](https://github.com/singerdmx/flutter-quill)：编辑器内核、Delta 文档模型与可扩展的样式钩子
- [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy)：块编辑器、命令面板与「本地优先」的产品气质
- [Memos](https://github.com/usememos/memos)：轻量记录、热力图与低摩擦输入
- [Day One](https://dayoneapp.com/)：日历、心情、On This Day 的日记体验（商业产品，仅作体验参考）
- [iA Writer](https://ia.net/writer)：专注模式与排版克制
- [Typora](https://typora.io/)：所见即所得的写作手感
- [Lucide](https://lucide.dev/)：图标
- [Noto Sans SC](https://fonts.google.com/noto/specimen/Noto+Sans+SC) 与 [LXGW WenKai](https://github.com/lxgw/LxgwWenKai)：字体
- [Smiley Sans / 得意黑](https://github.com/atelier-anchor/smiley-sans) 与 [Source Han Mono / 思源等宽](https://github.com/adobe-fonts/source-han-mono)：字体

「此记」没有复制上述项目的代码，只在产品结构与交互上做了借鉴；编辑器与导出实现基于 flutter_quill 及其公开 API。

## 许可证

代码以 [MIT](LICENSE) 发布。内置字体为 SIL Open Font License 1.1，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

