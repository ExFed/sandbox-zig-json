const std = @import("std");

pub fn Result(comptime T: type, comptime E: type) type {
    return struct {
        const Self = @This();
        const IsOk = error{Error};
        const IsErr = error{Error};

        ok_value: ?T = null,
        err_value: ?E = null,

        pub fn ok(value: T) Self {
            return Self{ .ok_value = value };
        }

        pub fn err(value: E) Self {
            return Self{ .err_value = value };
        }

        pub fn is_ok(self: *const Self) bool {
            return null != self.err_value;
        }

        pub fn get(self: *const Self) IsErr!T {
            if (self.ok_value) |v| {
                return v;
            }
            return IsErr.Error;
        }

        pub fn get_err(self: *const Self) IsOk!E {
            if (self.err_value) |v| {
                return v;
            }
            return IsOk.Error;
        }
    };
}

test "results" {
    const t = std.testing;
    const R = Result(u64, []const u8);

    const ok_result = R.ok(1337);
    try t.expectEqual(1337, ok_result.get());
    try t.expectError(R.IsOk.Error, ok_result.get_err());

    const err_result = R.err("oh no!");
    try t.expectError(R.IsErr.Error, err_result.get());
    try t.expectEqualStrings("oh no!", try err_result.get_err());

    const N = Result(?bool, []const u8);

    const null_result = N.ok(null);
    try t.expectEqual(null, null_result.get());
}
