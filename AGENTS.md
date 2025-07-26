# プロジェクト概要

このプロジェクでは、python パッケージの cloudscraper を Dart で実装し test\live_test.dart の合格を目標とします。
live_test を実行するためには Stealth mode や Turnstile は必要ありません。
Dio のインターセプターとして最終的に実装を提供します。
一時的に UserAgent の変更によって回避が成功する場合があります。しかし根本的な解決にはなりません。
チャレンジページを実際に解き通過する必要があります。

```bash
.
├── cloudscraper #参考にする Python リポジトリ
├── src
│   ├── cloudscraper_dio_base.dart
│   └── interceptor.dart
├── cloudscraper_dio.dart
├── test
│ ├── cloudscraper_dio_test.dart
│ └── live_test.dart #合格を目指すテスト
├── .gitignore
├── AGENTS.md
├── analysis_options.yaml
├── CHANGELOG.md
├── pubspec.lock
├── pubspec.yaml
└── README.md
```
