const std = @import("std");
const Allocator = std.mem.Allocator;

// JSON Grammar:
//  object
//      '{' '}'
//      '{' members '}'
//  members
//      pair
//      pair ',' members
//  pair
//      string ':' value
//  array
//      '[' ']'
//      '[' elements ']'
//  elements
//      value
//      value ',' elements
//  value
//      string
//      number
//      object
//      array
//      true
//      false
//      null

pub const TokenType = enum {
    String,
    Number,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Colon,
    Comma,
    True,
    False,
    Null,
};

pub const SourceUnit = struct {
    path: []const u8,

    const Self = @This();
    const MAX_FILE_SIZE: usize = 1024 * 1024 * 1024; // 1GB

    pub fn readAll(self: Self, allocator: Allocator) ![]u8 {
        const file = try std.fs.openFileAbsolute(self.path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, MAX_FILE_SIZE);
    }
};

pub const Location = struct {
    line: usize,
    column: usize,

    const Self = @This();

    fn init() Location {
        return of(1, 1);
    }

    fn of(line: usize, column: usize) Location {
        return Location{
            .line = line,
            .column = column,
        };
    }

    fn next_line(self: *Self) void {
        self.line += 1;
        self.column = 1;
    }

    fn advance_by(self: *Self, n: usize) void {
        self.column += n;
    }

    fn advance(self: *Self) void {
        self.advance_by(1);
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{d}:{d}", .{ self.line, self.column });
    }
};

pub const Token = struct {
    token_type: TokenType,
    location: Location,
    value: []const u8,

    const Self = @This();

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("(Token {any} {any} {s})", .{ self.token_type, self.location, self.value });
    }
};

pub const Tokenizer = struct {
    err_msg: ?ErrorMsg = null,

    const Self = @This();

    pub const Error = error{ UnclosedQuote, UnexpectedCharacter };
    pub const ErrorMsg = struct {
        location: Location,
        lexeme: ?[]const u8 = null,
    };

    fn error_unclosed_quote(self: *Self, l: Location) Error {
        self.err_msg = .{ .location = l };
        return Error.UnclosedQuote;
    }

    fn error_unexpected_char(self: *Self, c: []const u8, l: Location) Error {
        self.err_msg = .{ .location = l, .lexeme = c };
        return Error.UnexpectedCharacter;
    }

    pub fn tokenize(self: *Self, src: []const u8, tokens: *std.ArrayList(Token)) (Allocator.Error || Error)!void {
        self.err_msg = null;

        var i: usize = 0;
        var loc: Location = Location.init();
        while (i < src.len) : (i += 1) {
            switch (src[i]) {
                '\n' => loc.next_line(),
                ' ', '\r', '\t' => loc.advance(),
                '{' => {
                    try tokens.append(Token{ .token_type = TokenType.LBrace, .location = loc, .value = "{" });
                    loc.advance();
                },
                '}' => {
                    try tokens.append(Token{ .token_type = TokenType.RBrace, .location = loc, .value = "}" });
                    loc.advance();
                },
                '[' => {
                    try tokens.append(Token{ .token_type = TokenType.LBracket, .location = loc, .value = "[" });
                    loc.advance();
                },
                ']' => {
                    try tokens.append(Token{ .token_type = TokenType.RBracket, .location = loc, .value = "]" });
                    loc.advance();
                },
                ':' => {
                    try tokens.append(Token{ .token_type = TokenType.Colon, .location = loc, .value = ":" });
                    loc.advance();
                },
                ',' => {
                    try tokens.append(Token{ .token_type = TokenType.Comma, .location = loc, .value = "," });
                    loc.advance();
                },
                't' => {
                    if (i + 4 <= src.len and std.mem.eql(u8, src[i .. i + 4], "true")) {
                        try tokens.append(Token{ .token_type = TokenType.True, .location = loc, .value = "true" });
                        loc.advance_by(4);
                        i += 3;
                    } else {
                        return self.error_unexpected_char(src[i .. i + 1], loc);
                    }
                },
                'f' => {
                    if (i + 5 <= src.len and std.mem.eql(u8, src[i .. i + 5], "false")) {
                        try tokens.append(Token{ .token_type = TokenType.False, .location = loc, .value = "false" });
                        loc.advance_by(5);
                        i += 4;
                    } else {
                        return self.error_unexpected_char(src[i .. i + 1], loc);
                    }
                },
                'n' => {
                    if (i + 4 <= src.len and std.mem.eql(u8, src[i .. i + 4], "null")) {
                        try tokens.append(Token{ .token_type = TokenType.Null, .location = loc, .value = "null" });
                        loc.advance_by(4);
                        i += 3;
                    } else {
                        return self.error_unexpected_char(src[i .. i + 1], loc);
                    }
                },
                '"' => {
                    var j = i + 1;
                    while (j < src.len) : (j += 1) {
                        if (src[j] == '"') {
                            try tokens.append(Token{ .token_type = TokenType.String, .location = loc, .value = src[i + 1 .. j] });
                            loc.advance_by(j - i + 1);
                            i = j;
                            break;
                        }
                    }
                    if (j == src.len) {
                        return self.error_unclosed_quote(loc);
                    }
                },
                else => {
                    if (src[i] >= '0' and src[i] <= '9') {
                        var j = i + 1;
                        while (j < src.len) : (j += 1) {
                            if ((src[j] < '0' or src[j] > '9') and src[j] != '.') {
                                try tokens.append(Token{ .token_type = TokenType.Number, .location = loc, .value = src[i..j] });
                                loc.advance_by(j - i);
                                i = j - 1;
                                break;
                            }
                        }
                    } else {
                        return self.error_unexpected_char(src[i .. i + 1], loc);
                    }
                },
            }
        }
    }
};

test "tokenize sample" {
    const src =
        \\{
        \\  "num": 12.34, "bool": [true, false, null]
        \\}
    ;

    var tokenizer = try Tokenizer.init(std.heap.page_allocator);
    defer tokenizer.deinit();

    const result = try tokenizer.tokenize(src);
    defer result.deinit();

    const expected = [_]Token{
        Token{ .token_type = TokenType.LBrace, .location = Location.of(1, 1), .value = "{" },
        Token{ .token_type = TokenType.String, .location = Location.of(2, 3), .value = "num" },
        Token{ .token_type = TokenType.Colon, .location = Location.of(2, 8), .value = ":" },
        Token{ .token_type = TokenType.Number, .location = Location.of(2, 10), .value = "12.34" },
        Token{ .token_type = TokenType.Comma, .location = Location.of(2, 15), .value = "," },
        Token{ .token_type = TokenType.String, .location = Location.of(2, 17), .value = "bool" },
        Token{ .token_type = TokenType.Colon, .location = Location.of(2, 23), .value = ":" },
        Token{ .token_type = TokenType.LBracket, .location = Location.of(2, 25), .value = "[" },
        Token{ .token_type = TokenType.True, .location = Location.of(2, 26), .value = "true" },
        Token{ .token_type = TokenType.Comma, .location = Location.of(2, 30), .value = "," },
        Token{ .token_type = TokenType.False, .location = Location.of(2, 32), .value = "false" },
        Token{ .token_type = TokenType.Comma, .location = Location.of(2, 37), .value = "," },
        Token{ .token_type = TokenType.Null, .location = Location.of(2, 39), .value = "null" },
        Token{ .token_type = TokenType.RBracket, .location = Location.of(2, 43), .value = "]" },
        Token{ .token_type = TokenType.RBrace, .location = Location.of(3, 1), .value = "}" },
    };

    try std.testing.expectEqual(result.items.len, expected.len);

    for (result.items, 0..) |actual, i| {
        try std.testing.expectEqualDeep(expected[i], actual);
    }
}

test "tokenize error: quote not closed" {
    const src =
        \\[
        \\  "unclosed",
        \\  "quote...
        \\]
    ;

    var tokenizer = try Tokenizer.init(std.heap.page_allocator);
    defer tokenizer.deinit();

    const result = tokenizer.tokenize(src);
    if (result) |tokens| {
        defer tokens.deinit();
    } else |_| {
        // noop
    }

    try std.testing.expectError(Tokenizer.Error.UnclosedQuote, result);
    try std.testing.expectEqual(Location.of(3, 3), tokenizer.err_msg.?.location);
}

test "tokenize error: unexpected character" {
    const src =
        \\{
        \\  "expected": "character",
        \\  "unexpected": !!!
        \\}
    ;

    var tokenizer = try Tokenizer.init(std.heap.page_allocator);
    defer tokenizer.deinit();

    const result = tokenizer.tokenize(src);
    if (result) |tokens| {
        defer tokens.deinit();
    } else |_| {
        // noop
    }

    try std.testing.expectError(Tokenizer.Error.UnexpectedCharacter, result);

    const err_msg = tokenizer.err_msg.?;
    try std.testing.expectEqual(Location.of(3, 17), err_msg.location);
    try std.testing.expectEqualDeep("!", err_msg.lexeme);
}
