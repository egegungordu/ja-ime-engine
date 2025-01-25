const std = @import("std");
const testing = std.testing;

const datastructs = @import("datastructs");
const Trie = datastructs.trie.Trie;

test "trie: basic operations" {
    const allocator = testing.allocator;
    var trie = Trie([]const u8).init(allocator);
    defer trie.deinit();

    try trie.insert("きど", "喜怒");
    try trie.insert("あいらく", "哀楽");
    try trie.insert("のる", "乗る");
    try trie.insert("のる", "載る");

    // Test root node
    try testing.expectEqual(@as(usize, 3), trie.root.edges.count());
    try testing.expect(trie.root.values.items.len == 0);

    // Test "のる" node
    const noru_node = trie.root.edges.get("の").?.edges.get("る").?;
    try testing.expectEqualStrings("る", noru_node.label.?);
    try testing.expectEqual(@as(usize, 0), noru_node.edges.count());
    try testing.expectEqual(@as(usize, 2), noru_node.values.items.len);
    try testing.expectEqualStrings("乗る", noru_node.values.items[0]);
    try testing.expectEqualStrings("載る", noru_node.values.items[1]);

    // Test "あいらく" path
    const ai_node = trie.root.edges.get("あ").?;
    try testing.expectEqualStrings("あ", ai_node.label.?);
    const aira_node = ai_node.edges.get("い").?.edges.get("ら").?;
    try testing.expectEqualStrings("ら", aira_node.label.?);
    const airaku_node = aira_node.edges.get("く").?;
    try testing.expectEqualStrings("く", airaku_node.label.?);
    try testing.expectEqual(@as(usize, 1), airaku_node.values.items.len);
    try testing.expectEqualStrings("哀楽", airaku_node.values.items[0]);
}

test "trie: iterator" {
    const allocator = testing.allocator;
    var trie = Trie([]const u8).init(allocator);
    defer trie.deinit();

    try trie.insert("きど", "喜怒");
    try trie.insert("あいらく", "哀楽");
    try trie.insert("のる", "乗る");

    var it = try trie.iterator(allocator);
    defer it.deinit();

    // Root node
    var node = (try it.next()).?;
    try testing.expect(node.label == null);
    try testing.expectEqual(@as(usize, 3), node.edges.count());

    // First level nodes (BFS order)
    node = (try it.next()).?;
    try testing.expectEqualStrings("き", node.label.?);
    node = (try it.next()).?;
    try testing.expectEqualStrings("あ", node.label.?);
    node = (try it.next()).?;
    try testing.expectEqualStrings("の", node.label.?);

    // Ensure we can iterate through all nodes without errors
    while (try it.next()) |_| {}
}
