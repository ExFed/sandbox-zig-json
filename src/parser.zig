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

const TokenType = enum {
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

const Location = struct {
    const Self = @This();
    line: usize,
    column: usize,

    fn init() Location {
        return Location{
            .line = 1,
            .column = 1,
        };
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

        try writer.print("{}:{}", .{ self.line, self.column });
    }
};

const Token = struct {
    const Self = @This();
    token_type: TokenType,
    location: Location,
    value: []const u8,

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("(Token {} {} {s})", .{ self.token_type, self.location, self.value });
    }
};

const Tokenizer = struct {
    const Self = @This();
    filename: []const u8,
    source: []const u8,

    pub const Error = error{ UnclosedQuote, UnexpectedCharacter };

    var err_location: Location = undefined;
    var err_lexeme: []const u8 = undefined;

    fn error_unclosed_quote(l: Location) Tokenizer.Error {
        // std.debug.print("unclosed quote (@ {s})\n", .{l});
        err_location = l;
        return Tokenizer.Error.UnclosedQuote;
    }

    fn error_unexpected_char(c: []const u8, l: Location) Tokenizer.Error {
        // std.debug.print("unexpected character: '{c}' (@ {s})\n", .{ c, l });
        err_location = l;
        err_lexeme = c;
        return Tokenizer.Error.UnexpectedCharacter;
    }

    fn tokenize(allocator: Allocator, src: []const u8) (Allocator.Error || Tokenizer.Error)!std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(allocator);
        errdefer tokens.deinit();

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
                        return error_unexpected_char(src[i .. i + 1], loc);
                    }
                },
                'f' => {
                    if (i + 5 <= src.len and std.mem.eql(u8, src[i .. i + 5], "false")) {
                        try tokens.append(Token{ .token_type = TokenType.False, .location = loc, .value = "false" });
                        loc.advance_by(5);
                        i += 4;
                    } else {
                        return error_unexpected_char(src[i .. i + 1], loc);
                    }
                },
                'n' => {
                    if (i + 4 <= src.len and std.mem.eql(u8, src[i .. i + 4], "null")) {
                        try tokens.append(Token{ .token_type = TokenType.Null, .location = loc, .value = "null" });
                        loc.advance_by(4);
                        i += 3;
                    } else {
                        return error_unexpected_char(src[i .. i + 1], loc);
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
                        return error_unclosed_quote(loc);
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
                        return error_unexpected_char(src[i .. i + 1], loc);
                    }
                },
            }
        }

        return tokens;
    }
};

test "tokenize sample" {
    const src =
        \\{
        \\  "num": 12.34, "bool": [true, false, null]
        \\}
    ;

    const allocator = std.heap.page_allocator;
    const tokens = try Tokenizer.tokenize(allocator, src);
    defer allocator.free(tokens.items);

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

    try std.testing.expectEqual(tokens.items.len, expected.len);

    for (tokens.items, 0..) |actual, i| {
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
    const result = Tokenizer.tokenize(std.heap.page_allocator, src);
    try std.testing.expectError(Tokenizer.Error.UnclosedQuote, result);
    try std.testing.expectEqual(Location.of(3, 3), Tokenizer.err_location);
}

test "tokenize error: unexpected character" {
    const src =
        \\{
        \\  "expected": "character",
        \\  "unexpected": !!!
        \\}
    ;
    const result = Tokenizer.tokenize(std.heap.page_allocator, src);
    try std.testing.expectError(Tokenizer.Error.UnexpectedCharacter, result);
    try std.testing.expectEqual(Location.of(3, 17), Tokenizer.err_location);
    try std.testing.expectEqualDeep("!", Tokenizer.err_lexeme);
}
