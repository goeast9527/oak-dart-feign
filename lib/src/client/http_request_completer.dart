import 'dart:async';

import 'package:oak_dart_openfeign/src/http/http_request.dart';

class HttpRequestCompleter {
  /// 过期时间，-1 表示不过期
  final int expireTime;

  final HttpRequest request;

  final Completer completer;

  HttpRequestCompleter(this.expireTime, this.request, this.completer);

  bool isExpire(int currentTimes) {
    if (expireTime == -1) {
      return false;
    }
    return expireTime < currentTimes;
  }
}
