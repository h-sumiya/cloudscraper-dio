import 'dart:convert';
import 'package:dio/dio.dart';

import 'cloudscraper.dart';
import 'interpre/base.dart';
import 'interpre/nodejs.dart';

class DioCloudscraper extends Cloudscraper {
  @override
  bool debug;

  @override
  double? delay;

  @override
  JavaScriptInterpreter interpreter;

  final Dio dio;
  final Map<String, String> _headers = {};
  final Map<String, Map<String, String>> _cookies = {};

  DioCloudscraper({
    required this.dio,
    this.debug = false,
    this.delay,
    JavaScriptInterpreter? interpreter,
  }) : interpreter = interpreter ?? NodeJSInterpreter();

  @override
  Map<String, String> get headers => _headers;

  String _hostKey(Uri url) => url.host;

  void _applyCookies(Uri url, Map<String, String> headers) {
    final jar = _cookies[_hostKey(url)];
    if (jar != null && jar.isNotEmpty) {
      headers['cookie'] = jar.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
  }

  void _saveCookies(Uri url, Headers headers) {
    final setCookies = headers.map['set-cookie'];
    if (setCookies == null) return;
    final jar = _cookies.putIfAbsent(_hostKey(url), () => {});
    for (final c in setCookies) {
      final part = c.split(';')[0];
      final idx = part.indexOf('=');
      if (idx > 0) {
        final name = part.substring(0, idx);
        final value = part.substring(idx + 1);
        jar[name] = value;
      }
    }
  }

  @override
  Future<CfResponse> request(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Map<String, String>? data,
    bool allowRedirects = true,
  }) async {
    final reqHeaders = {..._headers, if (headers != null) ...headers};
    _applyCookies(url, reqHeaders);

    final opts = Options(
      method: method,
      headers: reqHeaders,
      followRedirects: allowRedirects,
      validateStatus: (_) => true,
    );

    Response res;
    if (method.toUpperCase() == 'GET') {
      res = await dio.getUri(url, options: opts);
    } else if (method.toUpperCase() == 'POST') {
      res = await dio.postUri(url, data: data, options: opts);
    } else {
      res = await dio.requestUri(url, options: opts, data: data);
    }

    _saveCookies(url, res.headers);

    final respHeaders = <String, String>{};
    res.headers.forEach((k, v) => respHeaders[k] = v.join(','));

    final body = res.data is String
        ? res.data as String
        : res.data is List<int>
        ? utf8.decode(res.data as List<int>)
        : res.data.toString();

    return CfResponse(
      statusCode: res.statusCode ?? 0,
      headers: respHeaders,
      body: body,
      url: res.realUri,
      request: CfRequest(method, url),
    );
  }
}
