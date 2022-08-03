const testing = @import("std").testing;

pub fn shouldPassAll(_parser: anytype, slice: []const u8) !void {
    var parser = _parser;
    const len = slice.len;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const res = try parser.parse(slice[i..]);
        try testing.expect(res.input.len == slice.len - i - 1);
    }
}
