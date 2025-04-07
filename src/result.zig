const std = @import("std");

pub fn Result(comptime T: type, comptime E: type) type {
    return struct {
        const Self = @This();
        const IsOk = error{Error};
        const IsErr = error{Error};

        ok_value: T = undefined,
        err_value: ?E = null,

        pub fn ok(value: T) Self {
            return Self{ .ok_value = value };
        }

        pub fn err(value: E) Self {
            return Self{ .err_value = value };
        }

        pub fn is_ok(self: *const Self) bool {
            return null == self.err_value;
        }

        pub fn get(self: *const Self) IsErr!T {
            return if (self.is_ok()) self.ok_value else IsErr.Error;
        }

        pub fn get_err(self: *const Self) IsOk!E {
            return if (self.is_ok()) IsOk.Error else self.err_value.?;
        }
    };
}

test "results" {
    const t = std.testing;
    const R = Result(u64, []const u8);

    const ok_result = R.ok(1337);
    try t.expect(ok_result.is_ok());
    try t.expectEqual(1337, ok_result.get());
    try t.expectError(R.IsOk.Error, ok_result.get_err());

    const err_result = R.err("oh no!");
    try t.expect(!err_result.is_ok());
    try t.expectError(R.IsErr.Error, err_result.get());
    try t.expectEqualStrings("oh no!", try err_result.get_err());

    const N = Result(?u8, []const u8);

    const null_result = N.ok(null);
    try t.expect(null_result.is_ok());
    try t.expectEqual(null, null_result.get());
}
