// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:async/async.dart';
import 'package:oak_dart_openfeign/src/http/client_http_request.dart';
import 'package:http/http.dart';

/// TODO 基于 [ClientHttpRequest] 重新实现 retry
/// An HTTP client wrapper that automatically retries failing requests.
class RetryClient extends BaseClient {
  /// The wrapped client.
  final Client _inner;

  /// The number of times a request should be retried.
  final int _retries;

  /// The callback that determines whether a request should be retried.
  final bool Function(BaseResponse) _when;

  /// The callback that determines whether a request when an error is thrown.
  final bool Function(dynamic, StackTrace) _whenError;

  /// The callback that determines how long to wait before retrying a request.
  final Duration Function(int) _delay;

  /// The callback to call to indicate that a request is being retried.
  final void Function(int, BaseRequest, BaseResponse?) _onRetry;

  /// Creates a client wrapping [_inner] that retries HTTP requests.
  ///
  /// This retries a failing request [retries] times (3 by default). Note that
  /// `n` retries means that the request will be sent at most `n + 1` times.
  ///
  /// By default, this retries requests whose responses have status code 503
  /// Temporary Failure. If [when] is passed, it retries any request for whose
  /// response [when] returns `true`. If [whenError] is passed, it also retries
  /// any request that throws an error for which [whenError] returns `true`.
  ///
  /// By default, this waits 500ms between the original request and the first
  /// retry, then increases the delay by 1.5x for each subsequent retry. If
  /// [delay] is passed, it's used to determine the time to wait before the
  /// given (zero-based) retry.
  ///
  /// If [onRetry] is passed, it's called immediately before each retry so that
  /// the client has a chance to perform side effects like logging. The
  /// `response` parameter will be null if the request was retried due to an
  /// error for which [whenError] returned `true`.
  RetryClient(
    this._inner, {
    int retries: 3,
    bool Function(BaseResponse)? when,
    bool Function(dynamic, StackTrace)? whenError,
    Duration Function(int retryCount)? delay,
    void Function(int, BaseRequest, BaseResponse?)? onRetry,
  })  : _retries = retries,
        _when = when ?? ((response) => response.statusCode == 503),
        _whenError = whenError ?? ((_, __) => false),
        _delay = delay ?? ((retryCount) => const Duration(milliseconds: 500) * math.pow(1.5, retryCount)),
        _onRetry = onRetry ?? ((count, req, resp) => null) {
    RangeError.checkNotNegative(_retries, 'retries');
  }

  /// Like [new RetryClient], but with a pre-computed list of [delays]
  /// between each retry.
  ///
  /// This will retry a request at most `delays.length` times, using each delay
  /// in order. It will wait for `delays[0]` after the initial request,
  /// `delays[1]` after the first retry, and so on.
  RetryClient.withDelays(
    Client inner,
    Iterable<Duration> delays, {
    bool Function(BaseResponse)? when,
    bool Function(dynamic, StackTrace)? whenError,
    void Function(int, BaseRequest, BaseResponse?)? onRetry,
  }) : this._withDelays(
          inner,
          delays.toList(),
          when: when,
          whenError: whenError,
          onRetry: onRetry,
        );

  RetryClient._withDelays(
    Client inner,
    List<Duration> delays, {
    bool Function(BaseResponse)? when,
    bool Function(dynamic, StackTrace)? whenError,
    void Function(int, BaseRequest, BaseResponse?)? onRetry,
  }) : this(
          inner,
          retries: delays.length,
          delay: (retryCount) => delays[retryCount],
          when: when,
          whenError: whenError,
          onRetry: onRetry,
        );

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final splitter = StreamSplitter(request.finalize());

    var i = 0;
    for (;;) {
      StreamedResponse? response;
      try {
        response = await _inner.send(_copyRequest(request, splitter.split()));
      } catch (error, stackTrace) {
        if (i == _retries || !_whenError(error, stackTrace)) rethrow;
        response = new StreamedResponse(Stream.empty(), 500);
      }
      // TODO
      if (i == _retries || !_when(response)) {
        return response;
      }
      // Make sure the response stream is listened to so that we don't leave
      // dangling connections.
      unawaited(response.stream.listen((_) {}).cancel().catchError((_) {}));
      await Future.delayed(_delay(i));
      _onRetry(i, request, response);
      i++;
    }
  }

  /// Returns a copy of [original] with the given [body].
  StreamedRequest _copyRequest(BaseRequest original, Stream<List<int>> body) {
    final request = StreamedRequest(original.method, original.url)
      ..contentLength = original.contentLength
      ..followRedirects = original.followRedirects
      ..headers.addAll(original.headers)
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;

    body.listen(request.sink.add, onError: request.sink.addError, onDone: request.sink.close, cancelOnError: true);

    return request;
  }

  @override
  void close() => _inner.close();
}
