# Changelog

## 2.0.0

### 发布前修复

- 手机端：修复搜索结果在防抖后不刷新、从搜索结果返回后搜索状态丢失，以及切到其他标签后仍残留旧关键词的问题。
- 手机端：搜索时收起范围筛选与排序条，结果区不再被挤占；修复「更多」菜单被屏幕裁切，所有入口可滚动到达。
- 手机端：标题改为单行，回车直接进入正文；横屏阅读列收窄并居中；底部导航字号略微增大。
- 英文界面：设置卡片副标题和新建模板说明完整换行显示；字数按单复数显示（1 word / 145 words）；引导页语言切换不再压住状态栏。

### 文件夹、多选与时间视图

- 文件夹与笔记卡片合并到同一列表：文件夹以卡片形式出现，可以把笔记直接拖进文件夹，也能在列表里上下拖动排序。
- 把笔记拖到列表的上下边缘时会自动滚动，长列表里拖动不再需要先滚动再拖。
- 列表支持多选，可对选中的笔记批量置顶、收藏、固定、移动或删除。
- 右侧「固定」让笔记不参与列表排序，始终停在原位。
- 新增「时间」视图，按时间线浏览笔记。
- 修复在文件夹中新建笔记时，笔记没有进入该文件夹的问题。

### 细节打磨

- 文件夹卡片也支持置顶、固定和多选，可以和多篇笔记一起批量处理。
- 文件夹里的笔记可以拖到顶部「移出」条，回到上一层。
- 拖出列表上方或下方时不再弹回原处，而是落到首位或末位。
- 编辑器的标签栏会随打开数量等分整条宽度，标签可以直接拖动排序。
- 多选支持按住滑动，滑过的卡片连续选中。
- 修复表格编辑弹窗溢出、常用颜色无法删除、选区右键菜单不在指针处的问题。
- 固定卡片只锁住自己的位置，其它卡片仍可自由移动、跨过它排序。
- 标签栏直接拖动卡片就能实时换位，并带动画滑动。
- 分屏窄栏自动收起次要信息，不再出现黄黑溢出条。
- 「全部笔记」侧栏可以收起和展开。
- 表格编辑器改为可见的单元格网格，支持增删行列和表头。
- 常用色删除改为明确的「取消常用」按钮，去掉容易误触的小叉。

### Writing

- Typewriter mode and paragraph focus.
- Per-note word goals, writing-time stats, and a clearer daily progress.
- Offline Chinese style check: filler words, repetition, long sentences, punctuation and spacing.
- Outline follows the caret; version history can be compared before restoring.
- Favorites view, full tag list, note links (`[[Title]]`) and backlinks.
- User templates with `{{date}}` / `{{weekday}}` variables and a one-command daily diary.
- Desktop tabs and split view; each pane saves independently.
- Table blocks with TSV editing and DOCX/PDF/HTML/Markdown export.
- EPUB export, DOCX import, and print-to-system-PDF.
- Shortcut sheet and Alt+↑/↓ note navigation.
- Android share target: send text/links from other apps straight into a new note.
- Mobile swipe: left to trash with undo, right to favorite.
- API key and WebDAV password moved to the OS keystore, with a plaintext fallback only when the keystore is unavailable.
- `library.json` now keeps only metadata and excerpts; full text lives in `notes/` and `index/text/`, with a one-time, backed-up migration.
- Backup/restore compression runs in an isolate.
- Crash journal: drafts newer than the file on disk are offered for recovery on the next launch.
- 25-minute writing sprint with live countdown and words written.
- Outline can insert a plain table of contents at the caret.

### Data and performance

- Fonts are subset to the common Chinese charset; rare glyphs fall back to the system CJK font.
- Saving no longer encodes the whole document on every keystroke; the library index is written lazily.
- Startup shows the paper first and loads the library afterwards.
- PDF fonts are loaded only when the document needs them; embedded images decode at display size.
- WebDAV is now honestly called a backup: full archive upload/restore, no automatic sync claim.
- Backups carry a `backup-manifest.json`; the PIN lock is documented as a UI lock, not disk encryption.

### Release

- Android arm64-only builds with ABI filters; split debug symbols and obfuscation.
- CI runs analyzer and tests; release workflow builds Windows and Android artifacts.
- Removed unused `flutter_animate` / `collection` dependencies and unused brand assets.

## 1.3.1

- Restored the Android launcher icon.

## 1.3.0

- Mobile navigation, code-block highlighting, AI chat and export upgrades.

## 1.2.0

- PNG pagination, custom fonts, writing time and AI thinking levels.