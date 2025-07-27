// lib/src/interpre/encapsulated.dart
import 'dart:developer' as dev;

/// Python版 template(body, domain) の Dart 変換。
/// 引数:
///  - [body]: Cloudflare IUAM を含む HTML/JS 本文
///  - [domain]: 対象ドメイン（例: "example.com"）
/// 返り値:
///  - Node.js の vm.runInNewContext で実行するための JS 文字列
String template(String body, String domain) {
  const bugReport =
      'Cloudflare may have changed their technique, or there may be a bug in the script.';

  // 1) setTimeout(...) 内の実行本体（a.value=...toFixed(10); まで）を抽出
  final jsMatch = RegExp(
    r'setTimeout\(function\(\)\{\s+(.*?a\.value\s*=\s*\S+toFixed\(10\);)',
    multiLine: true,
    dotAll: true,
  ).firstMatch(body);

  if (jsMatch == null || jsMatch.groupCount < 1) {
    throw StateError(
      'Unable to identify Cloudflare IUAM Javascript on website. $bugReport',
    );
  }
  var js = jsMatch.group(1)!;

  // 2) Python 実装と同じ置換（文字列リテラルとしての置換）
  js = js.replaceAll(
    r'(setInterval(function(){}, 100),t.match(/https?:\/\/)[0]);',
    r't.match(/https?:\/\/)[0];',
  );

  // 3) k の抽出: 例)  k = 'someprefix';
  final kMatch = RegExp(r" k\s*=\s*'(\S+)';").firstMatch(body);
  if (kMatch == null || kMatch.groupCount < 1) {
    dev.log('Error extracting variable k. $bugReport');
    throw StateError('Error extracting Cloudflare IUAM Javascript. $bugReport');
  }
  final k = kMatch.group(1)!;

  // 4) <div id="{k}{id}"> JSF*** </div> を走査して subVars を構築
  final divRe = RegExp(
    '<div id="$k(\\d+)">\\s*([^<>]*)</div>',
    multiLine: true,
    dotAll: true,
  );

  final buffer = StringBuffer();
  for (final m in divRe.allMatches(body)) {
    final id = m.group(1)!;
    final jsfuck = (m.group(2) ?? '').trimRight();
    buffer.writeln('\t\t$k$id: $jsfuck,');
  }

  // 末尾の",\n"を落とす（Python: subVars = subVars[:-2] 相当）
  var subVars = buffer.toString();
  if (subVars.endsWith(',\n')) {
    subVars = subVars.substring(0, subVars.length - 2);
  }

  // 5) 実行環境（document, subVars 等）を整備する JS 文字列を生成
  var jsEnv =
      '''
String.prototype.italics=function(str) {return "<i>" + this + "</i>";};
    var subVars= {$subVars};
    var document = {
        createElement: function () {
            return { firstChild: { href: "https://$domain/" } }
        },
        getElementById: function (str) {
            return {"innerHTML": subVars[str]};
        }
    };
''';

  // Python の re.sub(r'\s{2,}', ' ', ...) と同等の圧縮（jsEnv のみ）
  jsEnv = jsEnv.replaceAll(
    RegExp(r'\s{2,}', multiLine: true, dotAll: true),
    ' ',
  );

  // 6) jsEnv + challenge 本体を連結して返す
  return '$jsEnv$js';
}
