# json_canonicalizer

A dependency-free [RFC 8785 JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785.html)
implementation for Dart.

## Install

```sh
dart pub add json_canonicalizer
```

## Use

```dart
import 'package:json_canonicalizer/json_canonicalizer.dart';

canonicalize({'b': 1, 'a': 2}); // {"a":2,"b":1}
canonicalizeUtf8({'a': 1});
```

Accepts parsed I-JSON values only. Invalid values throw
`JsonCanonicalizationException`, whose `path` is an RFC 6901 pointer.

Tests cover RFC 8785 examples, number vectors, the upstream JCS corpus, cycles,
and 100,000-level containers.

## License

Unlicense. Upstream test vectors in `test/` are Apache-2.0.
