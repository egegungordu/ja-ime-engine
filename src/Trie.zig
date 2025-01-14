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
