const std = @import("std");

/// This enum declares all possible keys for a phone keypad:
/// ```
/// 1 2 3
/// 4 5 6
/// 7 8 9
/// * 0 #
/// ```
pub const Key = enum {
    /// Select special characters
    @"1",

    /// ABC
    @"2",

    /// DEF
    @"3",

    /// GHI
    @"4",

    /// JKL
    @"5",

    /// MNO
    @"6",

    /// PQRS
    @"7",

    /// TUV
    @"8",

    /// WXYZ
    @"9",

    /// Separate words
    @"0",

    /// Select next alternative
    @"*",

    /// Switch current case
    @"#",

    pub fn fromChar(codepoint: u21) ?Key {
        return switch (codepoint) {
            '1', '.', ',', '!', '"', '?', ':', ';', '\'', '-', '/', '\\', '&' => .@"1",
            '2', 'A', 'a', 'B', 'b', 'C', 'c', 'Ä', 'ä', 'Å', 'å', 'á', 'ç', 'â', 'à', 'æ', 'ã' => .@"2",
            '3', 'D', 'd', 'E', 'e', 'F', 'f', 'é', 'É', 'è', 'ë', 'ê' => .@"3",
            '4', 'G', 'g', 'H', 'h', 'I', 'i', 'î', 'í', 'ì', 'ï' => .@"4",
            '5', 'J', 'j', 'K', 'k', 'L', 'l' => .@"5",
            '6', 'M', 'm', 'N', 'n', 'O', 'o', 'Ö', 'ö', 'ô', 'ó', 'ò', 'ñ', 'ø' => .@"6",
            '7', 'P', 'p', 'Q', 'q', 'R', 'r', 'S', 's', 'ẞ', 'ß' => .@"7",
            '8', 'T', 't', 'U', 'u', 'V', 'v', 'Ü', 'ü', 'ú', 'û' => .@"8",
            '9', 'W', 'w', 'X', 'x', 'Y', 'y', 'Z', 'z' => .@"9",
            '0', ' ' => .@"0",
            else => null,
        };
    }
};

/// A flat, unsorted dictionary.
/// It's a bag of words used for trie construction.
pub const Dictionary = struct {
    pub const Iterator = std.StringHashMapUnmanaged(void).KeyIterator;

    arena: std.heap.ArenaAllocator,
    words: std.StringHashMapUnmanaged(void),

    pub fn init(allocator: std.mem.Allocator) Dictionary {
        return Dictionary{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .words = .{},
        };
    }

    pub fn deinit(self: *Dictionary) void {
        self.arena.deinit();
    }

    pub fn insert(self: *Dictionary, word: []const u8) !void {
        const gop = try self.words.getOrPut(self.arena.allocator(), word);
        if (gop.found_existing)
            return;
        errdefer _ = self.words.remove(word);
        gop.key_ptr.* = try self.arena.allocator().dupe(u8, word);
    }

    pub fn contains(self: Dictionary, word: []const u8) bool {
        return self.words.contains(word);
    }

    pub fn iterator(self: *const Dictionary) Iterator {
        return self.words.keyIterator();
    }
};

pub const Trie = struct {
    pub const Node = struct {
        children: [9]?*Node = [1]?*Node{null} ** 9,
        words: [][]const u8,
    };

    memory: std.heap.ArenaAllocator,
    root: *Node,

    pub fn deinit(self: *Trie) void {
        self.memory.deinit();
    }

    pub fn build(structure_allocator: std.mem.Allocator, temporary_allocator: std.mem.Allocator, dictionary: Dictionary) !Trie {
        var storage = std.heap.ArenaAllocator.init(structure_allocator);
        errdefer storage.deinit();

        var root = Node{
            .words = try temporary_allocator.alloc([]const u8, 0),
        };
        defer freeNodeRecursive(temporary_allocator, &root);

        var word_iterator = dictionary.iterator();
        while (word_iterator.next()) |word| {
            const dupe = try storage.allocator().dupe(u8, word.*);
            errdefer storage.allocator().free(dupe);

            var utf8 = std.unicode.Utf8View.initUnchecked(dupe);
            var cpiter = utf8.iterator();

            try insertAndAppendWord(
                &root,
                temporary_allocator,
                dupe,
                &cpiter,
            );
        }

        var trie = Trie{
            .memory = undefined,
            .root = undefined,
        };

        trie.root = try cloneNodeStruct(storage.allocator(), root);

        trie.memory = storage;
        return trie;
    }

    fn freeNodeRecursive(allocator: std.mem.Allocator, node: *Node) void {
        for (node.children) |*maybe_child| {
            if (maybe_child.*) |child| {
                freeNodeRecursive(allocator, child);
                allocator.destroy(child);
            }
            maybe_child.* = null;
        }
        allocator.free(node.words);
    }

    fn keyToIndex(key: Key) ?usize {
        return switch (key) {
            .@"1" => 0,
            .@"2" => 1,
            .@"3" => 2,
            .@"4" => 3,
            .@"5" => 4,
            .@"6" => 5,
            .@"7" => 6,
            .@"8" => 7,
            .@"9" => 8,

            .@"0" => null,
            .@"*" => null,
            .@"#" => null,
        };
    }

    fn indexToKey(index: usize) Key {
        return switch (index) {
            0 => .@"1",
            1 => .@"2",
            2 => .@"3",
            3 => .@"4",
            4 => .@"5",
            5 => .@"6",
            6 => .@"7",
            7 => .@"8",
            8 => .@"9",

            else => unreachable, // out of bounds
        };
    }

    fn insertAndAppendWord(node: *Node, temp_allocator: std.mem.Allocator, word: []const u8, char_iter: *std.unicode.Utf8Iterator) error{ OutOfMemory, InvalidWord }!void {
        if (char_iter.nextCodepoint()) |child_codepoint| {
            const child_key = Key.fromChar(child_codepoint) orelse return error.InvalidWord;
            const child_index = keyToIndex(child_key) orelse return error.InvalidWord;

            if (node.children[child_index]) |child_node| {
                // recurse into the trie
                try insertAndAppendWord(child_node, temp_allocator, word, char_iter);
            } else {
                // construct more trie nodes ad-hoc

                const new_node = try temp_allocator.create(Node);
                errdefer temp_allocator.destroy(new_node);

                new_node.* = Node{
                    .words = try temp_allocator.alloc([]const u8, 0),
                };
                errdefer freeNodeRecursive(temp_allocator, new_node);

                try insertAndAppendWord(new_node, temp_allocator, word, char_iter);

                node.children[child_index] = new_node;
            }
        } else {
            // we arrived at the final character node,
            // so insert the word into the .words array:

            const new_index = node.words.len;

            const new_mem = try temp_allocator.realloc(node.words, new_index + 1);
            new_mem[new_index] = word;
            node.words = new_mem;
        }
    }

    /// Clones the Node structure by recursing through all childs,
    /// but **does not** clone the backing storage of the strings, only the array.
    fn cloneNodeStruct(allocator: std.mem.Allocator, src: Node) error{OutOfMemory}!*Node {
        const node = try allocator.create(Node);
        errdefer allocator.destroy(node);

        node.* = Node{
            .words = try allocator.dupe([]const u8, src.words),
        };
        errdefer allocator.free(node.words);

        for (src.children) |maybe_child, i| {
            node.children[i] = if (maybe_child) |child|
                try cloneNodeStruct(allocator, child.*)
            else
                null;
        }

        return node;
    }

    pub fn dumpGraphViz(trie: Trie, stream: anytype) !void {
        try stream.writeAll("digraph {\n");

        try stream.writeAll("  START [shape=point, label=\"\"];\n");
        try stream.print("  START -> n{d};\n", .{@ptrToInt(trie.root)});

        try dumpGraphVizRecursive(trie.root, stream);
        try stream.writeAll("}\n");
    }

    fn dumpGraphVizRecursive(node: *const Node, stream: anytype) @TypeOf(stream).Error!void {
        if (node.words.len > 0) {
            try stream.print("  n{d} [shape=box,label=\"", .{@ptrToInt(node)});
            for (node.words) |word, i| {
                if (i > 0)
                    try stream.writeAll(", ");
                try stream.writeAll(word);
            }
            try stream.writeAll("\"];\n");
        } else {
            try stream.print("  n{d} [shape=point,label=\"\"];\n", .{@ptrToInt(node)});
        }

        for (node.children) |maybe_child, index| {
            if (maybe_child) |child| {
                try stream.print("  n{d} -> n{d} [label=\"{s}\"];\n", .{
                    @ptrToInt(node),
                    @ptrToInt(child),
                    @tagName(indexToKey(index)),
                });

                try dumpGraphVizRecursive(child, stream);
            }
        }
    }

    pub fn lookUp(trie: Trie, sequence: []const Key) ![]const []const u8 {
        var current = trie.root;

        for (sequence) |key| {
            const index = keyToIndex(key) orelse return error.UnexpectedKey;
            current = current.children[index] orelse return &[0][]const u8{};
        }

        return current.words;
    }
};

pub const Editor = struct {
    sequence: std.BoundedArray(Key, 128) = .{},
    selection: usize,
};
