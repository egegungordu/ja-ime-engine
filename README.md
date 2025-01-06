# Jaime

A Japanese IME (Input Method Editor) engine for Zig projects, focusing on romaji to hiragana/full-width character conversion.

<table>
<tr>
<td>

On the **terminal** with libvaxis

[View repository](https://github.com/egegungordu/ja-ime-terminal-demo)

<img src=".github/assets/term-demo.gif" width="400" alt="Terminal demo">

</td>
<td>

On the **web** with webassembly

Coming soon!

<img src=".github/assets/web-demo.jpg" width="400" alt="Web demo (AI slop)">

</td>
</tr>
</table>

## Zig Version

The minimum Zig version required is 0.13.0.

## Integrating zig-ime-ja into your Zig Project

You first need to add zig-ime-ja as a dependency in your `build.zig.zon` file:

```bash
zig fetch --save git+https://github.com/egegungordu/jaime
```

Then instantiate the dependency in your `build.zig`:

```zig
const jaime = b.dependency("ja-ime-engine", .{});
exe.root_module.addImport("jaime", jaime.module("jaime"));
```

## Usage

The library provides a simple API for converting romaji (Latin characters) to hiragana:

```zig
const jaime = @import("jaime");

test "Basic romaji to hiragana conversion" {
    var ime = jaime.init(std.testing.allocator);
    defer ime.deinit();

    for ("konnnichiha") |c| {
        try ime.insert(&.{c});
        std.debug.print("{s}\n", .{ime.input.buf.items});
    }

    try std.testing.expectEqualStrings("こんにちは", ime.input.buf.items);
}
```

## Features

- Romaji to hiragana/full-width character conversion based on Google IME mapping
- Support for common Japanese input patterns:
  - Basic hiragana (あ、い、う、え、お、か、き、く...)
    - a -> あ
    - ka -> か
  - Small hiragana (ゃ、ゅ、ょ...)
    - xya -> や
    - li -> ぃ
  - Sokuon (っ)
    - tte -> って
  - Full-width characters
    - k -> ｋ
    - 1 -> １
  - Punctuation
    - . -> 。
    - ? -> ？
    - [ -> 「

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a Pull Request.

## Acknowledgments

- Based on Google IME transliteration mappings
