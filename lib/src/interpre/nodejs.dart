import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudscraper_dio/src/exceptions.dart';
import 'package:cloudscraper_dio/src/interpre/base.dart';
// Pythonの `from .encapsulated import template` 相当。
// 実際の配置に合わせてパスを調整してください。
import 'package:cloudscraper_dio/src/interpre/encapsulated.dart' show template;

class NodeJSInterpreter extends JavaScriptInterpreter {
  NodeJSInterpreter();

  @override
  Future<num> eval(String body, String domain) async {
    // Python: base64.b64encode(template(body, domain).encode('UTF-8'))
    final challengeSource = template(body, domain);
    final encoded = base64.encode(utf8.encode(challengeSource));

    // Python で組み立てている JS と等価
    final js = [
      'var atob=function(str){return Buffer.from(str,"base64").toString("binary");};',
      'var challenge=atob("$encoded");',
      'var context={atob:atob};',
      'var options={filename:"iuam-challenge.js",timeout:4000};',
      'var answer=require("vm").runInNewContext(challenge,context,options);',
      'process.stdout.write(String(answer));',
    ].join('');

    try {
      final result = await _runNodeWithFallback(js)
          // VM 側で4秒タイムアウト設定なので、少し余裕を見て待機
          .timeout(const Duration(milliseconds: 5000));

      if (result.exitCode != 0) {
        // Node が起動できたが、実行時エラーになったケース
        final stderrStr = _decodeAny(result.stderr).trim();
        throw CloudflareSolveError(
          'Error executing Cloudflare IUAM Javascript in Node.js: $stderrStr',
        );
      }

      final stdoutStr = _decodeAny(result.stdout).trim();
      final parsed = num.tryParse(stdoutStr);
      if (parsed == null) {
        throw StateError('Invalid result from Node.js eval: $stdoutStr');
      }
      return parsed;
    } on TimeoutException {
      throw CloudflareSolveError(
        'Timed out executing Cloudflare IUAM Javascript in Node.js.',
      );
    } on ProcessException catch (e) {
      // `node` も `nodejs` も見つからない等
      throw CloudflareSolveError(
        'Missing Node.js runtime. Node must be in PATH (check with `node -v`). '
        'Some systems use `nodejs` as the binary name; install the legacy alias if needed. '
        'Original error: ${e.message}',
      );
    }
  }

  /// `node -e <script>` を試し、見つからなければ `nodejs -e <script>` にフォールバック
  Future<ProcessResult> _runNodeWithFallback(String js) async {
    try {
      return await Process.run('node', ['-e', js]);
    } on ProcessException {
      // フォールバック: 一部ディストロでは node バイナリ名が `nodejs`
      return await Process.run('nodejs', ['-e', js]);
    }
  }

  String _decodeAny(Object data) {
    if (data is String) return data;
    if (data is List<int>) return utf8.decode(data);
    return data.toString();
  }
}
