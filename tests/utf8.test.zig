const std = @import("std");
const testing = std.testing;

const utf8utils = @import("utf8utils");
const Utf8BidirectionalView = utf8utils.utf8.Utf8BidirectionalView;
const createUtf8ShrinkingIterator = utf8utils.utf8.createUtf8ShrinkingIterator;

test "utf8: bidirectional - kanji iteration" {
    const s = Utf8BidirectionalView.initUnchecked("東京市");

    var it1 = s.iterator();
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "東");
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "京");
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "市");
    try testing.expect(it1.nextCodepointSlice() == null);
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "市");
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "京");
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "東");
    try testing.expect(it1.prevCodepointSlice() == null);

    var it2 = s.iterator();
    try testing.expectEqual(it2.nextCodepoint().?, 0x6771);
    try testing.expectEqual(it2.nextCodepoint().?, 0x4eac);
    try testing.expectEqual(it2.nextCodepoint().?, 0x5e02);
    try testing.expect(it2.nextCodepoint() == null);
    try testing.expectEqual(it2.prevCodepoint().?, 0x5e02);
    try testing.expectEqual(it2.prevCodepoint().?, 0x4eac);
    try testing.expectEqual(it2.prevCodepoint().?, 0x6771);
    try testing.expect(it2.prevCodepoint() == null);
}

test "utf8: bidirectional - ascii iteration" {
    const s = Utf8BidirectionalView.initUnchecked("abc");

    var it1 = s.iterator();
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "a");
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "b");
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "c");
    try testing.expect(it1.nextCodepointSlice() == null);
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "c");
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "b");
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "a");
    try testing.expect(it1.prevCodepointSlice() == null);

    var it2 = s.iterator();
    try testing.expectEqual(it2.nextCodepoint().?, 'a');
    try testing.expectEqual(it2.nextCodepoint().?, 'b');
    try testing.expectEqual(it2.nextCodepoint().?, 'c');
    try testing.expect(it2.nextCodepoint() == null);
    try testing.expectEqual(it2.prevCodepoint().?, 'c');
    try testing.expectEqual(it2.prevCodepoint().?, 'b');
    try testing.expectEqual(it2.prevCodepoint().?, 'a');
    try testing.expect(it2.prevCodepoint() == null);
}

test "utf8: bidirectional - mixed text iteration" {
    const s = Utf8BidirectionalView.initUnchecked("リズムにyeah");
    var it = s.iterator();
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "リ");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "ズ");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "ム");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "に");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "y");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "e");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "a");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "h");
    try testing.expect(it.nextCodepointSlice() == null);
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "h");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "a");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "e");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "y");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "に");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "ム");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "ズ");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "リ");
    try testing.expect(it.prevCodepointSlice() == null);
}

test "utf8: bidirectional - peek operations" {
    const s = Utf8BidirectionalView.initUnchecked("てtoらpoっど");
    var it = s.iterator();
    try testing.expectEqualStrings("て", it.peekForward(1).slice);
    try testing.expectEqualStrings("てt", it.peekForward(2).slice);
    try testing.expectEqualStrings("てto", it.peekForward(3).slice);
    try testing.expectEqualStrings("てtoら", it.peekForward(4).slice);
    try testing.expectEqualStrings("てtoらp", it.peekForward(5).slice);
    try testing.expectEqualStrings("てtoらpo", it.peekForward(6).slice);
    try testing.expectEqualStrings("てtoらpoっ", it.peekForward(7).slice);
    try testing.expectEqualStrings("てtoらpoっど", it.peekForward(8).slice);
    try testing.expectEqualStrings("てtoらpoっど", it.peekForward(99999).slice);
    try testing.expectEqual(8, it.peekForward(99999).codepoint_len);
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    try testing.expectEqualStrings("ら", it.peekBack(1).slice);
    try testing.expectEqualStrings("oら", it.peekBack(2).slice);
    try testing.expectEqualStrings("toら", it.peekBack(3).slice);
    try testing.expectEqualStrings("てtoら", it.peekBack(4).slice);
    try testing.expectEqualStrings("てtoら", it.peekBack(99999).slice);
    try testing.expectEqual(4, it.peekBack(99999).codepoint_len);
}

test "utf8: shrinking - basic iteration" {
    const s = "きょうは";
    var it = createUtf8ShrinkingIterator(s);

    // First iteration: "きょうは"
    if (it.next()) |segment| {
        try testing.expectEqualStrings("きょうは", segment.it.bytes);
        try testing.expectEqual(@as(usize, 4), segment.codepoint_len);
    } else {
        try testing.expect(false);
    }

    // Second iteration: "ょうは"
    if (it.next()) |segment| {
        try testing.expectEqualStrings("ょうは", segment.it.bytes);
        try testing.expectEqual(@as(usize, 3), segment.codepoint_len);
    } else {
        try testing.expect(false);
    }

    // Third iteration: "うは"
    if (it.next()) |segment| {
        try testing.expectEqualStrings("うは", segment.it.bytes);
        try testing.expectEqual(@as(usize, 2), segment.codepoint_len);
    } else {
        try testing.expect(false);
    }

    // Fourth iteration: "は"
    if (it.next()) |segment| {
        try testing.expectEqualStrings("は", segment.it.bytes);
        try testing.expectEqual(@as(usize, 1), segment.codepoint_len);
    } else {
        try testing.expect(false);
    }

    // Fourth iteration: should be null
    try testing.expect(it.next() == null);
}
