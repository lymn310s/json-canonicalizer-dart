# json_canonicalizer

A dependency-free [RFC 8785 JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785.html)
implementation for Dart.

## Install

```sh
dart pub add json_canonicalizer
```

## Usage

- `canonicalize(value)` returns canonical JSON as a `String`.
- `canonicalizeUtf8(value)` returns the same JSON as UTF-8 bytes for hashing or signing.

Both accept an already-parsed JSON value.

## Examples

```dart
import 'package:json_canonicalizer/json_canonicalizer.dart';

// Sorts object keys by UTF-16 order and removes extra spaces.
canonicalize({'b': 1, '\u{e000}': 'private use', '😳': 'flushed', 'a': 2});
// {"a":2,"b":1,"😳":"flushed","":"private use"}

// Formats numbers the same way as JavaScript JSON.
canonicalize(<Object?>[-0.0, 333333333.33333329, 1e30, 0.000001]);
// [0,333333333.3333333,1e+30,0.000001]

// Returns UTF-8 bytes for hashing or signing.
canonicalizeUtf8({'currency': '€'});
// [123, 34, 99, 117, 114, 114, 101, 110, 99, 121, 34, 58, 34, 226, 130, 172, 34, 125]
```

## Boundaries

Pass in a JSON value that has already been parsed. It can contain `null`,
booleans, finite numbers, valid Unicode strings, lists, and maps with string
keys. This package only canonicalizes the value; it does not parse, normalize,
hash, sign, or call `toJson`.

| Case | Result |
| --- | --- |
| Arrays | Preserve their original order. |
| Object keys | Sort by UTF-16 code units. |
| Strings | Escape control characters, quotes, and backslashes. Keep other Unicode unchanged. |
| `-0.0` | Writes `0`. |
| `NaN`, infinity, lossy `int`, lone surrogate, non-string key, cycle | Throw `JsonCanonicalizationException`. |
| Nested lists and maps | Work up to 100,000 levels deep. |

Errors point to the invalid value with an RFC 6901 path:

```dart
try {
  canonicalize({
    'payload': [
      {'a/b~c': double.nan},
    ],
  });
} on JsonCanonicalizationException catch (error) {
  print(error.path);
  // /payload/0/a~1b~0c
}
```

The [test suite](https://github.com/lymn310s/json-canonicalizer-dart/blob/main/test/json_canonicalizer_test.dart)
covers RFC 8785 examples,
Appendix B number vectors, the upstream JCS corpus, Unicode, escaping, invalid
input, cycles, shared subtrees, and 100,000-level lists and maps.

## License

Unlicense. Upstream test vectors in `test/` are Apache-2.0.
