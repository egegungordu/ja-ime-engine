# Jaime

A Japanese IME (Input Method Editor) engine for Zig projects, focusing on romaji to hiragana/full-width character conversion. Based on Google IME behavior.

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

The library provides several ways to convert romaji (Latin characters) to hiragana:

### Quick Conversion Functions

For simple one-off conversions, use these helper functions:

```zig
const jaime = @import("jaime");

// Using a provided buffer (no allocations)
var buf: [100]u8 = undefined;
const result = try jaime.bufConvert(&buf, "konnnichiha");
try std.testing.expectEqualStrings("こんにちは", result);

// Using an allocator (returns owned slice)
const result2 = try jaime.allocConvert(allocator, "konnnichiha");
defer allocator.free(result2);
try std.testing.expectEqualStrings("こんにちは", result2);
```

### Interactive IME

For interactive input handling, you can use the IME type which supports both owned (ArrayList) and borrowed (fixed-size) buffers:

```zig
const jaime = @import("jaime");

// Using owned buffer (with allocator)
var ime = jaime.Ime(.owned).init(allocator);
defer ime.deinit();  // deinit required for owned buffers

// Using borrowed buffer (fixed size, no allocations)
var buf: [100]u8 = undefined;
var ime = jaime.Ime(.borrowed).init(&buf);
// no deinit needed for borrowed buffers

// Both versions support the same API
try ime.insert("k");
try ime.insert("o");
try ime.insert("n");
try std.testing.expectEqualStrings("こん", ime.input.buf.items());

// Cursor movement and editing
ime.moveCursorBack();  // Move cursor left
try ime.insert("y");   // Insert at cursor
ime.clear();          // Clear the buffer
```

## Features

- Romaji to hiragana/full-width character conversion based on Google IME mapping
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
- Memory management options:
  - Owned buffer using ArrayList for dynamic sizing
  - Borrowed buffer for fixed-size, allocation-free usage

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a Pull Request.

## Acknowledgments

- Based on Google IME transliteration mappings
