# プロジェクト概要

このプロジェクでは、python パッケージの cloudscraper を Dart で実装し test\live_test.dart の合格を目標とします。
live_test を実行するためには Stealth mode や Turnstile は必要ありません。
Dio のインターセプターとして最終的に実装を提供します。

```bash
.
├── cloudscraper #参考にする Python リポジトリ
├── lib
│   ├── src
│   │   ├── interpre
│   │   │   ├── base.dart
│   │   │   ├── encapsulated.dart
│   │   │   └── nodejs.dart
│   │   ├── user_agent
│   │   │   ├── baes.dart
│   │   │   └── browsers.dart
│   │   ├── utils
│   │   │   └── html_unescape
│   │   │       ├── src
│   │   │       │   ├── data
│   │   │       │   │   ├── named_chars_all.dart
│   │   │       │   │   └── named_chars_basic.dart
│   │   │       │   └── base.dart
│   │   │       ├── html_unescape_small.dart
│   │   │       └── html_unescape.dart
│   │   ├── cloudflare_v2.dart
│   │   ├── cloudflare_v3.dart
│   │   ├── cloudscraper.dart
│   │   ├── exceptions.dart
│   │   └── interceptor.dart
│   └── cloudscraper_dio.dart
├── test
│   └── live_test.dart
├── .gitignore
├── AGENTS.md
├── analysis_options.yaml
├── CHANGELOG.md
├── pubspec.lock
├── pubspec.yaml
└── README.md
```
