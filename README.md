# zig-ime-ja

A Japanese IME (Input Method Editor) library for Zig projects, focusing on romaji to hiragana conversion.

## Zig Version

The minimum Zig version required is 0.13.0.

## Integrating zig-ime-ja into your Zig Project

You first need to add zig-ime-ja as a dependency in your `build.zig.zon` file:

```bash
zig fetch --save git+https://github.com/egegungordu/ja-ime-engine
```

Then instantiate the dependency in your `build.zig`:

```zig
const ime = b.dependency("zig-ime-ja", .{});
exe.root_module.addImport("romaji_parser", ime.module("romaji_parser"));
```

## Usage

The library provides a simple API for converting romaji (Latin characters) to hiragana:

```zig
const romaji_parser = @import("romaji_parser");

test "Basic romaji to hiragana conversion" {
    const allocator = std.testing.allocator;

    const input = "konnnichiha";
    // returns owned slice
    const result = try romaji_parser.parseRomaji(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("こんにちは", result);
}
```

## Features

- Romaji to hiragana conversion based on Google IME mapping
- Efficient FSM (Finite State Machine) based parsing
- Support for common Japanese input patterns:
  - Basic hiragana (あ、い、う、え、お、か、き、く...)
  - Small hiragana (ゃ、ゅ、ょ...)
  - Double consonants (っ)
  - N-consonant (ん)

## Implementation Details

The library uses a finite state machine to parse romaji input and convert it to hiragana. The implementation is based on the following components:

- `RomajiParseFsm`: Core FSM implementation for parsing romaji input
- `TransliterationMap`: Static mapping of romaji to hiragana based on Google IME
- `SmallTransliterationMap`: Mapping for small hiragana characters

The FSM handles various input states including:

- Single consonants (k, s, t, etc.)
- Palatalized consonants (ky, py, etc.)
- Special consonants (n, ch, ts, etc.)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Based on Google IME transliteration mappings
