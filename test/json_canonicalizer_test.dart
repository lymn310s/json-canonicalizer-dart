// Test vectors from cyberphone/json-canonicalization are Apache-2.0.
// Copyright 2018 Anders Rundgren. See LICENSE-APACHE.

import 'dart:convert';
import 'dart:typed_data';

import 'package:json_canonicalizer/json_canonicalizer.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 8785 canonicalization', () {
    test('reproduces the RFC sample', () {
      final input = jsonDecode(r'''
        {
          "numbers": [333333333.33333329, 1E30, 4.50, 2e-3,
                      0.000000000000000000000000001],
          "string": "\u20ac$\u000F\u000aA'\u0042\u0022\u005c\\\"\/",
          "literals": [null, true, false]
        }
      ''');

      expect(
        canonicalize(input),
        '{"literals":[null,true,false],'
        '"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],'
        r'''"string":"€$\u000f\nA'B\"\\\\\"/"}''',
      );
    });

    test('sorts recursively by raw UTF-16 code units', () {
      final input = <String, Object?>{
        '\u20ac': 'Euro Sign',
        '\r': 'Carriage Return',
        '\ufb33': 'Hebrew Letter Dalet With Dagesh',
        '1': 'One',
        '\u{1f600}': 'Emoji: Grinning Face',
        '\u0080': 'Control',
        '\u00f6': 'Latin Small Letter O With Diaeresis',
      };

      expect(
        canonicalize(input),
        '{"\\r":"Carriage Return","1":"One","\u0080":"Control",'
        '"\u00f6":"Latin Small Letter O With Diaeresis",'
        '"\u20ac":"Euro Sign","\u{1f600}":"Emoji: Grinning Face",'
        '"\ufb33":"Hebrew Letter Dalet With Dagesh"}',
      );
    });

    test('does not normalize Unicode', () {
      expect(
        canonicalize(<String, String>{'Unnormalized Unicode': 'A\u030a'}),
        '{"Unnormalized Unicode":"A\u030a"}',
      );
    });

    test('emits canonical UTF-8 bytes', () {
      expect(
        canonicalizeUtf8(<String, String>{'currency': '\u20ac'}),
        utf8.encode('{"currency":"\u20ac"}'),
      );
    });

    test('uses ECMAScript escapes for every C0 control', () {
      final controls = String.fromCharCodes(
        List<int>.generate(0x20, (index) => index),
      );

      expect(
        canonicalize(controls),
        r'"\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007'
        r'\b\t\n\u000b\f\r\u000e\u000f\u0010\u0011\u0012\u0013'
        r'\u0014\u0015\u0016\u0017\u0018\u0019\u001a\u001b'
        r'\u001c\u001d\u001e\u001f"',
      );
    });
  });

  group('upstream canonicalization corpus', () {
    final cases = <(String, String, String)>[
      (
        'arrays',
        '[56,{"d":true,"10":null,"1":[]}]',
        '[56,{"1":[],"10":null,"d":true}]',
      ),
      (
        'french',
        '{"peach":"This sorting order","péché":"is wrong according to French",'
            '"pêche":"but canonicalization MUST","sin":"ignore locale"}',
        '{"peach":"This sorting order","péché":"is wrong according to French",'
            '"pêche":"but canonicalization MUST","sin":"ignore locale"}',
      ),
      (
        'structures',
        '{"1":{"f":{"f":"hi","F":5},"\\n":56},"10":{},"":"empty",'
            '"a":{},"111":[{"e":"yes","E":"no"}],"A":{}}',
        '{"":"empty","1":{"\\n":56,"f":{"F":5,"f":"hi"}},"10":{},'
            '"111":[{"E":"no","e":"yes"}],"A":{},"a":{}}',
      ),
      (
        'unicode',
        r'{"Unnormalized Unicode":"A\u030a"}',
        '{"Unnormalized Unicode":"A\u030a"}',
      ),
      (
        'values',
        r'''{"numbers":[333333333.33333329,1E30,4.50,2e-3,1e-27],
             "string":"\u20ac$\u000F\u000aA'\u0042\u0022\u005c\\\"\/",
             "literals":[null,true,false]}''',
        '{"literals":[null,true,false],'
            '"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],'
            r'''"string":"€$\u000f\nA'B\"\\\\\"/"}''',
      ),
      (
        'weird',
        r'''{"\u20ac":"Euro Sign","\r":"Carriage Return",
             "\u000a":"Newline","1":"One",
             "\u0080":"Control\u007f","\ud83d\ude02":"Smiley",
             "\u00f6":"Latin Small Letter O With Diaeresis",
             "\ufb33":"Hebrew Letter Dalet With Dagesh",
             "</script>":"Browser Challenge"}''',
        '{"\\n":"Newline","\\r":"Carriage Return","1":"One",'
            '"</script>":"Browser Challenge","\u0080":"Control\u007f",'
            '"\u00f6":"Latin Small Letter O With Diaeresis",'
            '"\u20ac":"Euro Sign","\u{1f602}":"Smiley",'
            '"\ufb33":"Hebrew Letter Dalet With Dagesh"}',
      ),
    ];

    for (final (name, input, expected) in cases) {
      test(name, () {
        expect(canonicalize(jsonDecode(input)), expected);
      });
    }

    test('is idempotent for every upstream case', () {
      for (final (_, input, _) in cases) {
        final once = canonicalize(jsonDecode(input));
        expect(canonicalize(jsonDecode(once)), once);
      }
    });
  });

  group('RFC 8785 Appendix B numbers', () {
    const vectors = <String, String>{
      '0000000000000000': '0',
      '8000000000000000': '0',
      '0000000000000001': '5e-324',
      '8000000000000001': '-5e-324',
      '7fefffffffffffff': '1.7976931348623157e+308',
      'ffefffffffffffff': '-1.7976931348623157e+308',
      '4340000000000000': '9007199254740992',
      'c340000000000000': '-9007199254740992',
      '4430000000000000': '295147905179352830000',
      '44b52d02c7e14af5': '9.999999999999997e+22',
      '44b52d02c7e14af6': '1e+23',
      '44b52d02c7e14af7': '1.0000000000000001e+23',
      '444b1ae4d6e2ef4e': '999999999999999700000',
      '444b1ae4d6e2ef4f': '999999999999999900000',
      '444b1ae4d6e2ef50': '1e+21',
      '3eb0c6f7a0b5ed8c': '9.999999999999997e-7',
      '3eb0c6f7a0b5ed8d': '0.000001',
      '41b3de4355555553': '333333333.3333332',
      '41b3de4355555554': '333333333.33333325',
      '41b3de4355555555': '333333333.3333333',
      '41b3de4355555556': '333333333.3333334',
      '41b3de4355555557': '333333333.33333343',
      'becbf647612f3696': '-0.0000033333333333333333',
      '43143ff3c1cb0959': '1424953923781206.2',
    };

    for (final MapEntry(key: bits, value: expected) in vectors.entries) {
      test(bits, () {
        expect(canonicalize(_doubleFromBits(bits)), expected);
      });
    }

    test('rejects NaN and infinities', () {
      for (final bits in <String>[
        '7fffffffffffffff',
        '7ff0000000000000',
        'fff0000000000000',
      ]) {
        expect(
          () => canonicalize(_doubleFromBits(bits)),
          throwsA(isA<JsonCanonicalizationException>()),
        );
      }
    });
  });

  group('I-JSON input constraints', () {
    test('accepts exactly representable integers beyond the safe range', () {
      expect(canonicalize(9007199254740994), '9007199254740994');
    });

    test('rejects a representable int that would be rounded as a double', () {
      final value = int.tryParse('9007199254740993');
      // dart2js cannot create this int at all. Native Dart can, and must not
      // silently round it when adapting the value to RFC 8785's number model.
      if (value == null || value.toString() != '9007199254740993') return;

      expect(
        () => canonicalize(value),
        throwsA(
          isA<JsonCanonicalizationException>().having(
            (error) => error.path,
            'path',
            '',
          ),
        ),
      );
    });

    test('rejects lone surrogates in values and keys', () {
      expect(
        () => canonicalize(<String, String>{'value': 'a\ud800b'}),
        throwsA(
          isA<JsonCanonicalizationException>().having(
            (error) => error.path,
            'path',
            '/value',
          ),
        ),
      );
      expect(
        () => canonicalize(<String, String>{'\udc00': 'value'}),
        throwsA(isA<JsonCanonicalizationException>()),
      );
    });

    test('rejects non-string map keys and unsupported values', () {
      expect(
        () => canonicalize(<Object?, Object?>{1: 'one'}),
        throwsA(isA<JsonCanonicalizationException>()),
      );
      expect(
        () => canonicalize(DateTime.utc(2026)),
        throwsA(isA<JsonCanonicalizationException>()),
      );
    });

    test('reports an escaped RFC 6901 path', () {
      final input = <String, Object?>{
        'outer': <Object?>[
          <String, Object?>{'a/b~c': double.nan},
        ],
      };

      expect(
        () => canonicalize(input),
        throwsA(
          isA<JsonCanonicalizationException>().having(
            (error) => error.path,
            'path',
            '/outer/0/a~1b~0c',
          ),
        ),
      );
    });

    test('rejects cycles but permits shared subtrees', () {
      final cyclic = <Object?>[];
      cyclic.add(cyclic);
      expect(
        () => canonicalize(cyclic),
        throwsA(
          isA<JsonCanonicalizationException>().having(
            (error) => error.path,
            'path',
            '/0',
          ),
        ),
      );

      final shared = <String, int>{'a': 1};
      expect(
        canonicalize(<Object?>[shared, shared]),
        '[{"a":1},{"a":1}]',
      );
    });
  });

  group('allowInvalidUnicode', () {
    test('escapes a lone surrogate instead of throwing', () {
      expect(
        canonicalize(
          <String, String>{'value': 'a\ud800b'},
          allowInvalidUnicode: true,
        ),
        r'{"value":"a\ud800b"}',
      );
      expect(
        canonicalize(
          <String, String>{'\udc00': 'value'},
          allowInvalidUnicode: true,
        ),
        r'{"\udc00":"value"}',
      );
    });

    test('leaves valid Unicode alone', () {
      expect(
        canonicalize(
          <String, String>{'emoji': 'a\u{1f600}b'},
          allowInvalidUnicode: true,
        ),
        '{"emoji":"a\u{1f600}b"}',
      );
    });

    test('keeps the escaped text readable by any JSON parser', () {
      const truncated = 'hello \ud83d';
      final text = canonicalize(truncated, allowInvalidUnicode: true);

      expect(text, r'"hello \ud83d"');
      expect(jsonDecode(text), truncated);
      expect(canonicalize(jsonDecode(text), allowInvalidUnicode: true), text);
    });

    test('encodes UTF-8 without a replacement character', () {
      expect(
        canonicalizeUtf8('hello \ud83d', allowInvalidUnicode: true),
        utf8.encode(r'"hello \ud83d"'),
      );
    });

    test('relaxes nothing but Unicode', () {
      expect(
        () => canonicalize(double.nan, allowInvalidUnicode: true),
        throwsA(isA<JsonCanonicalizationException>()),
      );
      expect(
        () => canonicalize(
          <Object?, Object?>{1: 'one'},
          allowInvalidUnicode: true,
        ),
        throwsA(isA<JsonCanonicalizationException>()),
      );
    });
  });

  group('deep containers', () {
    test('handles 100,000 nested arrays without using the call stack', () {
      Object? value = <Object?>[];
      for (var depth = 0; depth < 100000; depth++) {
        value = <Object?>[value];
      }

      expect(canonicalize(value), hasLength(200002));
    });

    test('handles 100,000 nested objects without using the call stack', () {
      Object? value = <String, Object?>{};
      for (var depth = 0; depth < 100000; depth++) {
        value = <String, Object?>{'a': value};
      }

      expect(canonicalize(value), hasLength(600002));
    });
  });
}

double _doubleFromBits(String hex) {
  final padded = hex.padLeft(16, '0');
  final bytes = ByteData(8)
    ..setUint32(0, int.parse(padded.substring(0, 8), radix: 16))
    ..setUint32(4, int.parse(padded.substring(8), radix: 16));
  return bytes.getFloat64(0);
}
