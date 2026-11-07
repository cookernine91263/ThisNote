# 第三方软件与字体声明

「此记 · ThisNote」的代码以 MIT 发布；随应用分发的字体与开源依赖保留各自许可证。

字体文件经过子集化（只保留通用规范汉字 / 一级常用字与标点）以减小安装包；这是 SIL OFL 1.1 允许的修改，许可证原文随字体一起分发。罕见字由系统 CJK 字体回退。

## 字体

### Noto Sans SC

- 用途：界面与正文通用字体（Light / Regular / Bold）
- 来源：https://fonts.google.com/noto/specimen/Noto+Sans+SC
- 许可证：SIL Open Font License 1.1
- 许可证全文：`app/assets/fonts/OFL-NotoSansSC.txt`


### Noto Serif SC

- 用途：宋体正文
- 来源：https://fonts.google.com/noto/specimen/Noto+Serif+SC
- 许可证：SIL Open Font License 1.1
- 许可证全文：`app/assets/fonts/OFL-NotoSerifSC.txt`

### Ma Shan Zheng / 马善政毛笔

- 用途：手写标题与花字
- 来源：https://fonts.google.com/specimen/Ma+Shan+Zheng
- 许可证：SIL Open Font License 1.1
- 许可证全文：`app/assets/fonts/OFL-MaShanZheng.txt`

### ZCOOL XiaoWei / 站酷小薇

- 用途：雅致标题
- 来源：https://fonts.google.com/specimen/ZCOOL+XiaoWei
- 许可证：SIL Open Font License 1.1
- 许可证全文：`app/assets/fonts/OFL-ZCOOLXiaoWei.txt`

### LXGW WenKai / 霞鹜文楷

- 用途：标题、字标与「花字」
- 来源：https://github.com/lxgw/LxgwWenKai
- 许可证：SIL Open Font License 1.1
- 许可证全文：`app/assets/fonts/OFL-LXGW-WenKai.txt`

### Smiley Sans / 得意黑

- 用途：有性格的标题
- 来源：https://github.com/atelier-anchor/smiley-sans
- 许可证：SIL Open Font License 1.1
- 许可证全文：`app/assets/fonts/OFL-SmileySans.txt`

### Source Han Mono / 思源等宽

- 用途：代码块、行内代码与等宽排版
- 来源：https://github.com/adobe-fonts/source-han-mono
- 许可证：SIL Open Font License 1.1
- 许可证全文：`app/assets/fonts/OFL-SourceHanMono.txt`

## 主要开源依赖

| 依赖 | 许可证 | 用途 |
| --- | --- | --- |
| Flutter / Dart | BSD-3-Clause | 跨平台框架与运行时 |
| flutter_quill | MIT | 富文本编辑器与 Delta 文档模型 |
| quill_delta | MIT | Delta 数据结构 |
| provider | MIT | 状态管理 |
| path_provider | BSD-3-Clause | 应用数据目录 |
| window_manager | MIT | 无边框窗口与窗口控制 |
| file_selector | BSD-3-Clause | 文件选择与保存 |
| share_plus | BSD-3-Clause | 系统分享 |
| url_launcher | BSD-3-Clause | 打开外部链接 |
| pdf | Apache-2.0 | PDF 生成 |
| archive | MIT | ZIP / DOCX 打包 |
| xml | MIT | OOXML / WebDAV XML |
| http | BSD-3-Clause | AI 与 WebDAV 请求 |
| highlight | MIT | 代码块语法高亮 |
| intl | BSD-3-Clause | 日期与本地化 |
| uuid | MIT | 文档 ID |
| crypto | BSD-3-Clause | 密码哈希 |
| flutter_secure_storage | BSD-3-Clause | API Key / WebDAV 密码进系统钥匙串 |
| lucide_icons_flutter | ISC | 图标（本地精简为单一常规字重） |
| flutter_secure_storage_windows（本地补丁） | BSD-3-Clause | 去除 ATL 依赖，使用 Win32 凭证 API |
| Inno Setup | Inno Setup License | Windows 安装包 |

以上依赖的完整许可证文本可在各自 pub 包或项目仓库中查阅。
