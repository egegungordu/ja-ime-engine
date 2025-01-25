const std = @import("std");
const testing = std.testing;

const kana = @import("kana");

test "convert" {
    const res = try kana.convert(testing.allocator, "beibi-");
    defer testing.allocator.free(res);

    try testing.expectEqualStrings("べいびー", res);
}

test "convertBuf" {
    var buf: [100]u8 = undefined;
    const res = try kana.convertBuf(&buf, "beibi-");

    try testing.expectEqualStrings("べいびー", res);
}
