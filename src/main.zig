const std = @import("std");
const parser = @import("parser.zig");

const MAX_FILE_SIZE: usize = 1024 * 1024 * 1024; // 1GB

fn read_source(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, MAX_FILE_SIZE);
}

pub fn main() !void {
    // const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     const deinit_status = gpa.deinit();
    //     //fail test; can't try in defer as defer is executed after we return
    //     if (deinit_status == .leak) {
    //         std.log.err("memory leak detected", .{});
    //     }
    // }
    var args = std.process.args();
    defer args.deinit();

    _ = args.skip();
    const src_path_arg = if (args.next()) |arg| arg else {
        std.debug.print("expected source file path argument\n", .{});
        return error{MissingArgument}.MissingArgument;
    };

    const allocator = std.heap.page_allocator;

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const src_path = try std.fs.cwd().realpath(src_path_arg, &path_buf);

    const source = try read_source(allocator, src_path);
    defer allocator.free(source);

    var tokenizer = try parser.Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize(source);
    defer tokens.deinit();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("tokens in {s}:\n", .{src_path});
    for (tokens.items) |token| {
        try stdout.print("  {any}\n", .{token});
    }
}
