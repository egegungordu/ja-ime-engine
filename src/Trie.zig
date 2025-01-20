const std = @import("std");
const mem = std.mem;

pub fn Trie(comptime V: type) type {
    return struct {
        allocator: mem.Allocator,
        root: Node,

        const Node = struct {
            edges: std.StringHashMap(Node),
            label: ?[]const u8,
            values: std.ArrayList(V),

            pub fn init(allocator: mem.Allocator, label: ?[]const u8) Node {
                return .{
                    .edges = std.StringHashMap(Node).init(allocator),
                    .label = label,
                    .values = std.ArrayList(V).init(allocator),
                };
            }

            pub fn deinit(self: *Node) void {
                var it = self.edges.valueIterator();
                while (it.next()) |node| {
                    node.deinit();
                }
                self.edges.deinit();
                self.values.deinit();
            }
        };

        pub fn init(allocator: mem.Allocator) Trie(V) {
            return .{
                .allocator = allocator,
                .root = Node.init(allocator, null),
            };
        }

        pub fn deinit(self: *Trie(V)) void {
            self.root.deinit();
        }

        // TODO: make this faster
        pub fn insert(self: *Trie(V), key: []const u8, value: V) !void {
            var current_node = &self.root;
            var it = (try std.unicode.Utf8View.init(key)).iterator();
            while (it.nextCodepointSlice()) |char| {
                if (current_node.edges.getPtr(char)) |child| {
                    current_node = child;
                } else {
                    const new_node = Node.init(self.allocator, char);
                    try current_node.edges.put(char, new_node);
                    current_node = current_node.edges.getPtr(char).?;
                }
            }
            try current_node.values.append(value);
        }

        pub fn iterator(self: *Trie(V), allocator: mem.Allocator) !TrieIterator(V) {
            var queue = std.ArrayList(*Trie(V).Node).init(allocator);
            try queue.append(&self.root);
            return TrieIterator(V){
                .queue = queue,
            };
        }
    };
}

/// BFS iterator
pub fn TrieIterator(comptime V: type) type {
    return struct {
        queue: std.ArrayList(*Trie(V).Node),

        pub fn deinit(self: *TrieIterator(V)) void {
            self.queue.deinit();
        }

        pub fn next(self: *TrieIterator(V)) !?Trie(V).Node {
            if (self.queue.items.len == 0) {
                return null;
            }

            const node = self.queue.orderedRemove(0);

            var it = node.edges.valueIterator();
            while (it.next()) |child| {
                try self.queue.append(child);
            }

            return node.*;
        }
    };
}

const testing = std.testing;

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
