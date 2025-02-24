const std = @import("std");
const parser = @import("parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak detected", .{});
        }
    }
    const allocator = gpa.allocator();

    var args = std.process.args();
    defer args.deinit();

    _ = args.skip(); // skip program name

    const src_path_arg = if (args.next()) |arg| arg else {
        std.debug.print("expected source file path argument\n", .{});
        return error{MissingArgument}.MissingArgument;
    };

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const src_path = try std.fs.cwd().realpath(src_path_arg, &path_buf);

    const src_unit = parser.SourceUnit{ .path = src_path };
    const src_chars = try src_unit.readAll(allocator);
    defer allocator.free(src_chars);

    var tokens = std.ArrayList(parser.Token).init(allocator);
    defer tokens.deinit();

    var tokenizer = parser.Tokenizer{};
    tokenizer.tokenize(src_chars, &tokens) catch |err| {
        std.debug.print("{any} in {s}", .{err, src_path});
        const msg = tokenizer.err_msg orelse unreachable;
        std.debug.print(" at {any}", .{msg.location});
        if (msg.lexeme) |l| {
            std.debug.print(" :: {s}", .{l});
        }
        std.debug.print("\n", .{});
        return;
    };

    const stdout = std.io.getStdOut().writer();

    try stdout.print("tokens in {s}:\n", .{src_path});
    for (tokens.items) |token| {
        try stdout.print("  {any}\n", .{token});
    }
}
