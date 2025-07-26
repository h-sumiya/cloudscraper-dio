import 'package:dio/dio.dart';

class CloudScraperInterceptor extends Interceptor {
  CloudScraperInterceptor({this.headerProvider, this.onLog});

  final Map<String, String> Function()? headerProvider;

  final void Function(String message)? onLog;

  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.5615.136 Mobile Safari/537.36';

  void _log(String msg) {
    (onLog ?? print).call('[YourInterceptor] $msg');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final headers = headerProvider?.call();
    if (headers != null && headers.isNotEmpty) {
      options.headers.addAll(headers);
    }

    // Normalize header names for lookup convenience
    String? ua =
        (options.headers['user-agent'] ?? options.headers['User-Agent']) as String?;
    if (ua != null && (ua.contains('Windows') || ua.contains('Linux'))) {
      options.headers['user-agent'] = _mobileUserAgent;
    }

    options.headers.putIfAbsent('accept', () => '*/*');
    options.headers.putIfAbsent('accept-language', () => 'en-US,en;q=0.9');
    options.headers.putIfAbsent('accept-encoding', () => 'gzip');
    _log('REQ ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log('RES ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log('ERR ${err.type} ${err.requestOptions.uri} ${err.message}');
    handler.next(err);
  }
}
