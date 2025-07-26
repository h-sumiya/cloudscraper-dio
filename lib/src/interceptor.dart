import 'package:dio/dio.dart';

class CloudScraperInterceptor extends Interceptor {
  CloudScraperInterceptor({this.headerProvider, this.onLog});

  final Map<String, String> Function()? headerProvider;

  final void Function(String message)? onLog;

  void _log(String msg) {
    (onLog ?? print).call('[YourInterceptor] $msg');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final headers = headerProvider?.call();
    if (headers != null && headers.isNotEmpty) {
      options.headers.addAll(headers);
    }
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
