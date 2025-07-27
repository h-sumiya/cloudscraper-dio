import 'dart:async';

import 'package:cloudscraper_dio/src/exceptions.dart';

abstract class JavaScriptInterpreter {
  Future<num> eval(String jsEnv, String js);

  Future<String> solveChallenge(String body, String domain) async {
    try {
      final v = await eval(body, domain);
      final d = (v is double) ? v : v.toDouble();
      if (d.isNaN || d.isInfinite) {
        throw StateError('Invalid result from eval: $d');
      }

      return d.toStringAsFixed(10);
    } catch (e) {
      throw CloudflareSolveError(
        'Error trying to solve Cloudflare IUAM Javascript, they may have changed their technique.',
      );
    }
  }
}
