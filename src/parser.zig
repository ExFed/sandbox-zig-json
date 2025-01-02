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
    token_type: TokenType,
    start: usize,
    end: usize,
};

const TokenizeError = error{ UnclosedQuote, UnexpectedCharacter };

fn error_unclosed_quote(i: usize) TokenizeError {
    std.debug.print("unclosed quote (@ {})\n", .{i});
    return TokenizeError.UnclosedQuote;
}

fn error_unexpected_char(src: []const u8, i: usize) TokenizeError {
    std.debug.print("unexpected character: '{c}' (@ {})\n", .{ src[i], i });
    return TokenizeError.UnexpectedCharacter;
}

fn tokenize(allocator: Allocator, src: []const u8) (Allocator.Error || TokenizeError)!std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);
    errdefer tokens.deinit();

    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        switch (src[i]) {
            ' ', '\n', '\r', '\t' => {},
            '{' => try tokens.append(Token{ .token_type = TokenType.LBrace, .start = i, .end = i + 1 }),
            '}' => try tokens.append(Token{ .token_type = TokenType.RBrace, .start = i, .end = i + 1 }),
            '[' => try tokens.append(Token{ .token_type = TokenType.LBracket, .start = i, .end = i + 1 }),
            ']' => try tokens.append(Token{ .token_type = TokenType.RBracket, .start = i, .end = i + 1 }),
            ':' => try tokens.append(Token{ .token_type = TokenType.Colon, .start = i, .end = i + 1 }),
            ',' => try tokens.append(Token{ .token_type = TokenType.Comma, .start = i, .end = i + 1 }),
            't' => {
                if (i + 4 <= src.len and std.mem.eql(u8, src[i .. i + 4], "true")) {
                    try tokens.append(Token{ .token_type = TokenType.True, .start = i, .end = i + 4 });
                    i += 3;
                } else {
                    return error_unexpected_char(src, i);
                }
            },
            'f' => {
                if (i + 5 <= src.len and std.mem.eql(u8, src[i .. i + 5], "false")) {
                    try tokens.append(Token{ .token_type = TokenType.False, .start = i, .end = i + 5 });
                    i += 4;
                } else {
                    return error_unexpected_char(src, i);
                }
            },
            'n' => {
                if (i + 4 <= src.len and std.mem.eql(u8, src[i .. i + 4], "null")) {
                    try tokens.append(Token{ .token_type = TokenType.Null, .start = i, .end = i + 4 });
                    i += 3;
                } else {
                    return error_unexpected_char(src, i);
                }
            },
            '"' => {
                var j = i + 1;
                while (j < src.len) : (j += 1) {
                    if (src[j] == '"') {
                        try tokens.append(Token{ .token_type = TokenType.String, .start = i + 1, .end = j });
                        i = j;
                        break;
                    }
                }
                if (j == src.len) {
                    return error_unclosed_quote(i);
                }
            },
            else => {
                if (src[i] >= '0' and src[i] <= '9') {
                    var j = i + 1;
                    while (j < src.len) : (j += 1) {
                        if ((src[j] < '0' or src[j] > '9') and src[j] != '.') {
                            try tokens.append(Token{ .token_type = TokenType.Number, .start = i, .end = j });
                            i = j - 1;
                            break;
                        }
                    }
                } else {
                    return error_unexpected_char(src, i);
                }
            },
        }
    }

    return tokens;
}

test "tokenize sample" {
    const src =
        \\{ "num": 12.34, "bool": [true, false, null] }
    ;

    const allocator = std.heap.page_allocator;
    const tokens = try tokenize(allocator, src);
    defer allocator.free(tokens.items);

    const expected = [_]Token{
        Token{ .token_type = TokenType.LBrace, .start = 0, .end = 1 },
        Token{ .token_type = TokenType.String, .start = 3, .end = 6 },
        Token{ .token_type = TokenType.Colon, .start = 7, .end = 8 },
        Token{ .token_type = TokenType.Number, .start = 9, .end = 14 },
        Token{ .token_type = TokenType.Comma, .start = 14, .end = 15 },
        Token{ .token_type = TokenType.String, .start = 17, .end = 21 },
        Token{ .token_type = TokenType.Colon, .start = 22, .end = 23 },
        Token{ .token_type = TokenType.LBracket, .start = 24, .end = 25 },
        Token{ .token_type = TokenType.True, .start = 25, .end = 29 },
        Token{ .token_type = TokenType.Comma, .start = 29, .end = 30 },
        Token{ .token_type = TokenType.False, .start = 31, .end = 36 },
        Token{ .token_type = TokenType.Comma, .start = 36, .end = 37 },
        Token{ .token_type = TokenType.Null, .start = 38, .end = 42 },
        Token{ .token_type = TokenType.RBracket, .start = 42, .end = 43 },
        Token{ .token_type = TokenType.RBrace, .start = 44, .end = 45 },
    };

    try std.testing.expectEqual(tokens.items.len, expected.len);

    for (tokens.items, 0..) |token, i| {
        try std.testing.expectEqual(expected[i].token_type, token.token_type);
        try std.testing.expectEqual(expected[i].start, token.start);
        try std.testing.expectEqual(expected[i].end, token.end);
    }
}

test "tokenize error: quote not closed" {
    const src =
        \\[
        \\  "unclosed",
        \\  "quote...
        \\]
    ;
    const result = tokenize(std.heap.page_allocator, src);
    try std.testing.expectError(TokenizeError.UnclosedQuote, result);
}

test "tokenize error: unexpected character" {
    const src =
        \\{
        \\  "unexpected": "character",
        \\  !!!
        \\}
    ;
    const result = tokenize(std.heap.page_allocator, src);
    try std.testing.expectError(TokenizeError.UnexpectedCharacter, result);
}
