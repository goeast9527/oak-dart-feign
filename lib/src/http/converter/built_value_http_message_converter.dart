import 'dart:async';
import 'dart:io';

import 'package:built_value/serializer.dart';
import 'package:oak_dart_basic/index.dart';
import 'package:oak_dart_openfeign/src/client/response_extractor.dart';
import 'package:oak_dart_openfeign/src/http/converter/abstract_http_message_converter.dart';
import 'package:oak_dart_openfeign/src/http/http_input_message.dart';
import 'package:oak_dart_openfeign/src/util/encoding_utils.dart';
import 'package:logging/logging.dart';

import '../http_output_message.dart';

/// 基于built value 的http message converter
/// 用于写入和读取 Content-Type 为[ContentType.json]的数据
class BuiltValueHttpMessageConverter extends AbstractGenericHttpMessageConverter {
  static const String _TAG = "BuiltValueHttpMessageConverter";

  ///  兼容一些旧服务器响应
  @deprecated
  static final ContentType _textJson = new ContentType("text", "json", charset: "utf-8");

  static final _log = Logger(_TAG);

  final BuiltJsonSerializers _builtJsonSerializers;

  final BusinessResponseExtractor _businessResponseExtractor;

  BuiltValueHttpMessageConverter(
      BuiltJsonSerializers builtJsonSerializers, BusinessResponseExtractor? businessResponseExtractor)
      : this._builtJsonSerializers = builtJsonSerializers,
        this._businessResponseExtractor = businessResponseExtractor ?? noneBusinessResponseExtractor,
        super([ContentType.json, _textJson]);

  factory(BuiltJsonSerializers builtJsonSerializers, {BusinessResponseExtractor? businessResponseExtractor}) {
    return new BuiltValueHttpMessageConverter(builtJsonSerializers, businessResponseExtractor);
  }

  Future<E> read<E>(HttpInputMessage inputMessage, ContentType mediaType,
      {Type? serializeType, FullType specifiedType = FullType.unspecified}) {
    return getContentTypeEncoding(mediaType).decodeStream(inputMessage.body).then((responseBody) {
      if (_log.isLoggable(Level.FINER)) {
        _log.finer("read http response body ==> $responseBody");
      }
      return this._businessResponseExtractor(responseBody).then((result) {
        return _resolveExtractorResult(result, specifiedType, serializeType);
      });
    });
  }

  _resolveExtractorResult(result, FullType specifiedType, Type? serializeType) {
    if (_isBaseType(specifiedType, serializeType) || result == null) {
      // 基础数据类型
      return result;
    }
    return this._builtJsonSerializers.parseObject(result, resultType: serializeType, specifiedType: specifiedType);
  }

  _isBaseType(FullType specifiedType, Type? serializeType) {
    final type = serializeType == null ? specifiedType.root : serializeType;
    if (type == null) {
      return true;
    }
    for (final baseType in AbstractHttpMessageConverter.base_types) {
      if (baseType == type) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> write(data, ContentType mediaType, HttpOutputMessage outputMessage) {
    final text = this._builtJsonSerializers.toJson(data);
    if (_log.isLoggable(Level.FINER)) {
      _log.finer("write data ==> $text");
    }
    super.writeBody(text, ContentType.json, outputMessage);
    return Future.value();
  }
}
