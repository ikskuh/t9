const std = @import("std");
const t9 = @import("t9.zig");

pub const log_level = .info;

pub fn loadDictionary(allocator: std.mem.Allocator, path: []const u8) !t9.Dictionary {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var breader = std.io.bufferedReader(file.reader());
    var reader = breader.reader();

    var count: usize = 0;
    var max_len: usize = 0;
    var tot_len: usize = 0;

    var dict = t9.Dictionary.init(allocator);
    errdefer dict.deinit();

    word_loop: while (true) {
        var line_buffer: [256]u8 = undefined;

        const maybe_line = try reader.readUntilDelimiterOrEof(&line_buffer, '\n');
        const line = std.mem.trim(u8, maybe_line orelse break, " \r\n\t");
        if (line.len == 0)
            continue;

        count += 1;
        tot_len += line.len;
        max_len = std.math.max(max_len, line.len);

        var utf8 = std.unicode.Utf8View.init(line) catch |err| {
            std.log.warn("{s} is not valid UTF-8: {s}", .{ line, @errorName(err) });
            continue;
        };
        var cps = utf8.iterator();
        while (cps.nextCodepoint()) |cp| {
            var key = t9.Key.fromChar(cp) orelse {
                std.log.warn("{s} contains unsupported codepoint: U+{X:0>4} ({u})", .{ line, cp, cp });
                continue :word_loop;
            };

            _ = key;
        }

        try dict.insert(line);
    }

    std.log.info("{s}:", .{path});
    std.log.info("word count:      {d: >10}", .{count});
    std.log.info("max word length: {d: >10}", .{max_len});
    std.log.info("avg word length: {d: >10}", .{tot_len / count});

    return dict;
}

pub fn main() !void {
    // var dict = try loadDictionary(std.heap.c_allocator, "data/german.dict");
    // var dict = try loadDictionary(std.heap.c_allocator, "data/english.dict");
    var dict = try loadDictionary(std.heap.c_allocator, "data/example.dict");
    defer dict.deinit();

    var trie = try t9.Trie.build(std.heap.c_allocator, std.heap.c_allocator, dict);
    defer trie.deinit();

    std.log.info("{s}", .{
        try trie.lookUp(&.{ .@"5", .@"2", .@"4", .@"3" }),
    });

    // try trie.dumpGraphViz(std.io.getStdOut().writer());
}
