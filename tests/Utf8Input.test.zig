const std = @import("std");
const testing = std.testing;
const unicode = std.unicode;

const utf8utils = @import("utf8utils");
const Utf8Input = utf8utils.Utf8Input;

test "utf8 input: basic validation" {
    var utf8_input = Utf8Input.init(testing.allocator);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try testing.expectEqualStrings("a", utf8_input.buf.items);
    try testing.expectError(error.InvalidUtf8, utf8_input.insert(&.{ 0x80, 0x80 }));
    try testing.expectError(error.ExpectedSingleCodepoint, utf8_input.insert("こんにちは世界"));
}

test "utf8 input: cursor movement" {
    var utf8_input = Utf8Input.init(testing.allocator);
    defer utf8_input.deinit();

    try ins(&utf8_input, "こんにちは");
    try ins(&utf8_input, "世界");
    utf8_input.moveCursorBack(2);
    try ins(&utf8_input, ", 素晴らしい");
    utf8_input.moveCursorBack(999);
    try ins(&utf8_input, "はーい");

    try testing.expectEqualStrings("はーいこんにちは, 素晴らしい世界", utf8_input.buf.items);
}

test "utf8 input: peek operations" {
    var utf8_input = Utf8Input.init(testing.allocator);
    defer utf8_input.deinit();

    try ins(&utf8_input, "こんにちは");
    try ins(&utf8_input, "世界");
    utf8_input.moveCursorBack(2);

    try testing.expectEqualStrings("世", utf8_input.peekForward(1).slice);
    try testing.expectEqualStrings("世界", utf8_input.peekForward(2).slice);
    try testing.expectEqualStrings("は", utf8_input.peekBack(1).slice);
    try testing.expectEqualStrings("ちは", utf8_input.peekBack(2).slice);

    utf8_input.moveCursorForward(999);
    try testing.expectEqualStrings("こんにちは世界", utf8_input.peekBack(999).slice);
}

test "utf8 input: delete operations" {
    var utf8_input = Utf8Input.init(testing.allocator);
    defer utf8_input.deinit();

    try ins(&utf8_input, "こんにちは");

    utf8_input.deleteBack(2);
    try testing.expectEqualStrings("こんに", utf8_input.buf.items);
    utf8_input.moveCursorBack(2);
    utf8_input.deleteForward(1);
    try testing.expectEqualStrings("こに", utf8_input.buf.items);
    utf8_input.deleteForward(999);
    try testing.expectEqualStrings("こ", utf8_input.buf.items);
    utf8_input.deleteBack(999);
    try testing.expectEqualStrings("", utf8_input.buf.items);
}

test "utf8 input: replace range" {
    var utf8_input = Utf8Input.init(testing.allocator);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try utf8_input.insert("b");
    try utf8_input.replaceBack(1, "c");
    try testing.expectEqualStrings("ac", utf8_input.buf.items);
}

test "utf8 input: clear buffer" {
    var utf8_input = Utf8Input.init(testing.allocator);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try utf8_input.insert("b");
    try testing.expectEqualStrings("ab", utf8_input.buf.items);
    utf8_input.clear();
    try testing.expectEqualStrings("", utf8_input.buf.items);
}

/// Helper function used in testing to insert multiple codepoints.
fn ins(utf8_input: *Utf8Input, s: []const u8) !void {
    var it = unicode.Utf8View.initUnchecked(s).iterator();
    while (it.nextCodepointSlice()) |codepoint| {
        try utf8_input.insert(codepoint);
    }
}
