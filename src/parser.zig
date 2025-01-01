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

const Token = struct {
    type: TokenType,
    start: usize,
    end: usize,

    pub fn slice(self: Token, input: []const u8) []const u8 {
        return input[self.start..self.end];
    }
};

fn tokenize(allocator: Allocator, src: []const u8) !std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);
    errdefer tokens.deinit();

    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        switch (src[i]) {
            ' ', '\n', '\r', '\t' => {},
            '{' => try tokens.append(Token{ .type = TokenType.LBrace, .start = i, .end = i + 1 }),
            '}' => try tokens.append(Token{ .type = TokenType.RBrace, .start = i, .end = i + 1 }),
            '[' => try tokens.append(Token{ .type = TokenType.LBracket, .start = i, .end = i + 1 }),
            ']' => try tokens.append(Token{ .type = TokenType.RBracket, .start = i, .end = i + 1 }),
            ':' => try tokens.append(Token{ .type = TokenType.Colon, .start = i, .end = i + 1 }),
            ',' => try tokens.append(Token{ .type = TokenType.Comma, .start = i, .end = i + 1 }),
            't' => {
                if (i + 4 <= src.len and std.mem.eql(u8, src[i .. i + 4], "true")) {
                    try tokens.append(Token{ .type = TokenType.True, .start = i, .end = i + 4 });
                    i += 3;
                } else {
                    return std.debug.panic("unexpected token: '{c}' ({})", .{ src[i], i });
                }
            },
            'f' => {
                if (i + 5 <= src.len and std.mem.eql(u8, src[i .. i + 5], "false")) {
                    try tokens.append(Token{ .type = TokenType.False, .start = i, .end = i + 5 });
                    i += 4;
                } else {
                    return std.debug.panic("unexpected token: '{c}' ({})", .{ src[i], i });
                }
            },
            'n' => {
                if (i + 4 <= src.len and std.mem.eql(u8, src[i .. i + 4], "null")) {
                    try tokens.append(Token{ .type = TokenType.Null, .start = i, .end = i + 4 });
                    i += 3;
                } else {
                    return std.debug.panic("unexpected token: '{c}' ({})", .{ src[i], i });
                }
            },
            '"' => {
                var j = i + 1;
                while (j < src.len) : (j += 1) {
                    if (src[j] == '"') {
                        try tokens.append(Token{ .type = TokenType.String, .start = i + 1, .end = j });
                        i = j;
                        break;
                    }
                }
                if (j == src.len) {
                    return std.debug.panic("unexpected end of file", .{});
                }
            },
            else => {
                if (src[i] >= '0' and src[i] <= '9') {
                    var j = i + 1;
                    while (j < src.len) : (j += 1) {
                        if ((src[j] < '0' or src[j] > '9') and src[j] != '.') {
                            try tokens.append(Token{ .type = TokenType.Number, .start = i, .end = j });
                            i = j - 1;
                            break;
                        }
                    }
                } else {
                    return std.debug.panic("unexpected token: '{c}' ({})", .{ src[i], i });
                }
            },
        }
    }

    return tokens;
}

test "tokenize sample" {
    // { "key": 12.34, "key2": [true, false, null] }
    const src = "{ \"num\": 12.34, \"bool\": [true, false, null] }";

    const allocator = std.heap.page_allocator;
    const tokens = try tokenize(allocator, src);
    defer allocator.free(tokens.items);

    const expected = [_]Token{
        Token{ .type = TokenType.LBrace, .start = 0, .end = 1 },
        Token{ .type = TokenType.String, .start = 3, .end = 6 },
        Token{ .type = TokenType.Colon, .start = 7, .end = 8 },
        Token{ .type = TokenType.Number, .start = 9, .end = 14 },
        Token{ .type = TokenType.Comma, .start = 14, .end = 15 },
        Token{ .type = TokenType.String, .start = 17, .end = 21 },
        Token{ .type = TokenType.Colon, .start = 22, .end = 23 },
        Token{ .type = TokenType.LBracket, .start = 24, .end = 25 },
        Token{ .type = TokenType.True, .start = 25, .end = 29 },
        Token{ .type = TokenType.Comma, .start = 29, .end = 30 },
        Token{ .type = TokenType.False, .start = 31, .end = 36 },
        Token{ .type = TokenType.Comma, .start = 36, .end = 37 },
        Token{ .type = TokenType.Null, .start = 38, .end = 42 },
        Token{ .type = TokenType.RBracket, .start = 42, .end = 43 },
        Token{ .type = TokenType.RBrace, .start = 44, .end = 45 },
    };

    try std.testing.expectEqual(tokens.items.len, expected.len);

    for (tokens.items, 0..) |token, i| {
        try std.testing.expectEqual(expected[i].type, token.type);
        try std.testing.expectEqual(expected[i].start, token.start);
        try std.testing.expectEqual(expected[i].end, token.end);
    }
}
