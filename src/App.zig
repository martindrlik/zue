const std = @import("std");
const Messages = @import("Messages.zig");

allocator: std.mem.Allocator,
messages: Messages,

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .allocator = allocator,
        .messages = .init(allocator),
    };
}
