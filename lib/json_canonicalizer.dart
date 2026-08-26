/// RFC 8785 JSON Canonicalization Scheme for parsed I-JSON values.
///
/// ```dart
/// final bytes = canonicalizeUtf8({'b': 1, 'a': 2});
/// ```
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Thrown when a value is outside RFC 8785's input domain.
final class JsonCanonicalizationException implements Exception {
  const JsonCanonicalizationException(this.message, {this.path = ''});

  final String message;

  /// The RFC 6901 pointer to the invalid value.
  final String path;

  @override
  String toString() => 'JsonCanonicalizationException: $message at '
      '${path.isEmpty ? '<root>' : path}';
}

/// Canonicalizes parsed I-JSON [value] according to RFC 8785.
///
/// Throws [JsonCanonicalizationException] for invalid JSON values.
///
/// Dart strings can contain a lone UTF-16 surrogate, which is not valid
/// Unicode. RFC 8785 requires rejecting it. Set [allowInvalidUnicode] to
/// escape it as `\uXXXX` instead. The output is valid JSON but no longer an
/// RFC 8785 canonical form.
String canonicalize(Object? value, {bool allowInvalidUnicode = false}) {
  final output = StringBuffer();
  final activeContainers = HashSet<Object>.identity();
  _write(output, value, activeContainers, allowInvalidUnicode);
  return output.toString();
}

/// Canonicalizes [value] as UTF-8 bytes. See [canonicalize].
Uint8List canonicalizeUtf8(Object? value, {bool allowInvalidUnicode = false}) =>
    Uint8List.fromList(
      utf8.encode(
          canonicalize(value, allowInvalidUnicode: allowInvalidUnicode)),
    );

sealed class _ContainerFrame {}

final class _ArrayFrame extends _ContainerFrame {
  _ArrayFrame(this.value, this.path);

  final List<Object?> value;
  final _Path path;
  var index = 0;
}

final class _ObjectFrame extends _ContainerFrame {
  _ObjectFrame(this.value, this.path, this.keys);

  final Map<Object?, Object?> value;
  final _Path path;
  final List<String> keys;
  var index = 0;
}

final class _Path {
  const _Path._(this.parent, this.segment);

  static const root = _Path._(null, null);

  final _Path? parent;
  final String? segment;

  _Path child(String segment) => _Path._(this, segment);

  String get pointer {
    if (segment == null) return '';
    final segments = <String>[];
    for (var path = this; path.segment != null; path = path.parent!) {
      segments.add(
        path.segment!.replaceAll('~', '~0').replaceAll('/', '~1'),
      );
    }
    return '/${segments.reversed.join('/')}';
  }
}

void _write(
  StringBuffer output,
  Object? value,
  HashSet<Object> activeContainers,
  bool allowInvalidUnicode,
) {
  final frames = <_ContainerFrame>[];
  var currentValue = value;
  var path = _Path.root;

  serialize:
  while (true) {
    if (currentValue == null) {
      output.write('null');
    } else if (currentValue is bool) {
      output.write(currentValue ? 'true' : 'false');
    } else if (currentValue is num) {
      _writeNumber(output, currentValue, path);
    } else if (currentValue is String) {
      _writeString(output, currentValue, path, allowInvalidUnicode);
    } else if (currentValue is List<Object?>) {
      _enterContainer(currentValue, path, activeContainers);
      output.write('[');
      if (currentValue.isNotEmpty) {
        frames.add(_ArrayFrame(currentValue, path));
        currentValue = currentValue.first;
        path = path.child('0');
        continue;
      }
      output.write(']');
      activeContainers.remove(currentValue);
    } else if (currentValue is Map<Object?, Object?>) {
      _enterContainer(currentValue, path, activeContainers);
      final keys = _sortedKeys(currentValue, path);
      output.write('{');
      if (keys.isNotEmpty) {
        frames.add(_ObjectFrame(currentValue, path, keys));
        final key = keys.first;
        path = path.child(key);
        _writeString(output, key, path, allowInvalidUnicode);
        output.write(':');
        currentValue = currentValue[key];
        continue;
      }
      output.write('}');
      activeContainers.remove(currentValue);
    } else {
      throw JsonCanonicalizationException(
        'unsupported type ${currentValue.runtimeType}',
        path: path.pointer,
      );
    }

    while (frames.isNotEmpty) {
      final frame = frames.last;
      if (frame is _ArrayFrame) {
        frame.index++;
        if (frame.index < frame.value.length) {
          output.write(',');
          currentValue = frame.value[frame.index];
          path = frame.path.child(frame.index.toString());
          continue serialize;
        }
        output.write(']');
        activeContainers.remove(frame.value);
        frames.removeLast();
        continue;
      }

      final objectFrame = frame as _ObjectFrame;
      objectFrame.index++;
      if (objectFrame.index < objectFrame.keys.length) {
        output.write(',');
        final key = objectFrame.keys[objectFrame.index];
        path = objectFrame.path.child(key);
        _writeString(output, key, path, allowInvalidUnicode);
        output.write(':');
        currentValue = objectFrame.value[key];
        continue serialize;
      }
      output.write('}');
      activeContainers.remove(objectFrame.value);
      frames.removeLast();
    }
    return;
  }
}

List<String> _sortedKeys(Map<Object?, Object?> value, _Path path) {
  final keys = <String>[];
  for (final key in value.keys) {
    if (key is! String) {
      throw JsonCanonicalizationException(
        'object key has unsupported type ${key.runtimeType}',
        path: path.pointer,
      );
    }
    keys.add(key);
  }
  keys.sort((first, second) => first.compareTo(second));
  return keys;
}

void _enterContainer(
  Object container,
  _Path path,
  HashSet<Object> activeContainers,
) {
  if (!activeContainers.add(container)) {
    throw JsonCanonicalizationException(
      'cyclic lists and maps are not JSON values',
      path: path.pointer,
    );
  }
}

void _writeNumber(StringBuffer output, num value, _Path path) {
  final double ieee754;
  if (value is int) {
    ieee754 = value.toDouble();
    if (!ieee754.isFinite || ieee754.toInt() != value) {
      throw JsonCanonicalizationException(
        'integer is not exactly representable as an IEEE-754 double',
        path: path.pointer,
      );
    }
  } else {
    ieee754 = value.toDouble();
  }

  if (!ieee754.isFinite) {
    throw JsonCanonicalizationException(
      'NaN and infinity are not JSON numbers',
      path: path.pointer,
    );
  }

  output.write(_ecmaScriptNumber(ieee754));
}

String _ecmaScriptNumber(double value) {
  if (value == 0) return '0';

  final text = value.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

const _shortEscapes = <int, String>{
  0x08: r'\b',
  0x09: r'\t',
  0x0a: r'\n',
  0x0c: r'\f',
  0x0d: r'\r',
  0x22: r'\"',
  0x5c: r'\\',
};

void _writeString(
  StringBuffer output,
  String value,
  _Path path,
  bool allowInvalidUnicode,
) {
  output.write('"');
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    final shortEscape = _shortEscapes[codeUnit];
    if (shortEscape != null) {
      output.write(shortEscape);
    } else if (codeUnit < 0x20) {
      _writeUnicodeEscape(output, codeUnit);
    } else if (_isLoneSurrogate(value, index, codeUnit)) {
      if (!allowInvalidUnicode) {
        throw JsonCanonicalizationException(
          'string contains a lone UTF-16 surrogate',
          path: path.pointer,
        );
      }
      // utf8.encode would replace it with U+FFFD. Escape instead.
      _writeUnicodeEscape(output, codeUnit);
    } else {
      output.writeCharCode(codeUnit);
    }
  }
  output.write('"');
}

void _writeUnicodeEscape(StringBuffer output, int codeUnit) {
  output
    ..write(r'\u')
    ..write(codeUnit.toRadixString(16).padLeft(4, '0'));
}

bool _isLoneSurrogate(String value, int index, int codeUnit) {
  if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
    final next = index + 1 < value.length ? value.codeUnitAt(index + 1) : -1;
    return next < 0xdc00 || next > 0xdfff;
  }
  if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
    final previous = index == 0 ? -1 : value.codeUnitAt(index - 1);
    return previous < 0xd800 || previous > 0xdbff;
  }
  return false;
}
