# Simple Reader / 简约阅读器

## 简介
本项目是一个本地电子书阅读器（iOS/Android），支持 `EPUB / PDF / TXT / Markdown` 导入与阅读，提供书架与文件夹分类功能、基础阅读设置（翻页/字号/背景色/目录）。

## Features
- Bookshelf with folders (本地书架 + 文件夹分类)
- Import from Files + Open in app (文件导入 + 其他 App “打开方式”导入)
- Formats: EPUB / PDF / TXT / Markdown
- Basic reader: page turning, font size, background, TOC (basic)

## 项目结构
- `lib/main.dart` 应用入口
- `lib/models/library.dart` 数据模型
- `lib/services/library_store.dart` 本地数据存储（JSON）
- `lib/services/settings_store.dart` 阅读设置
- `lib/screens/bookshelf_screen.dart` 书架
- `lib/screens/reader_screen.dart` 阅读器

## 运行（iOS）
1. 安装依赖：
   - `flutter pub get`
2. 启动模拟器或真机：
   - `flutter run`

## 导入方式说明（iOS）
1. 文件 App 导入：在书架页点 `+` 选择文件。
2. 其他 App 打开：在文件/第三方 App 中选择 “在 Simple Reader 中打开”。  
   iOS 会将文件拷贝到应用的 `Documents/Inbox`，应用启动/回到前台时自动导入。

## Android 说明（后续接入）
当前工程已保持跨平台结构。需要 Android SDK 后即可直接运行：
- 安装 Android Studio + SDK
- `flutter doctor --android-licenses`
- `flutter run`

## Notes
- Import files are copied into app storage (`Documents/Books`) for sandbox safety.
- Reading progress (page/scroll offset) is stored locally.

---

## English

### Overview
Simple Reader is a local-only ebook reader (iOS/Android) with bookshelf + folder organization. It supports `EPUB / PDF / TXT / Markdown` import and basic reading features (page turning, font size, background, TOC).

### Features
- Bookshelf + folders
- Import from Files / Open in app
- Formats: EPUB / PDF / TXT / Markdown
- Reader settings: page turning, font size, background, TOC

### Run (iOS)
1. Install deps:
   - `flutter pub get`
2. Run:
   - `flutter run`

### Import on iOS
1. From Files: tap `+` in the bookshelf.
2. From other apps: use “Open in Simple Reader”.  
   iOS copies the file into `Documents/Inbox`, and the app imports it on launch/resume.

### Android (later)
Project structure is Android-ready. After installing Android SDK:
- `flutter doctor --android-licenses`
- `flutter run`
