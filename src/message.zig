const Allocator = std.mem.Allocator;
const Message = @import("message.zig");
const Self = @This();
const httpz = @import("httpz");
const std = @import("std");

priority: u8,
name: []const u8,
nanoTimestamp: i128,
body: []const u8,

const Validation = error{
    MissingBody,
    MissingName,
    MissingPriority,
    PriorityOverflow,
    PriorityInvalidCharacter,
};

pub fn parse(allocator: Allocator, req: *httpz.Request) !Message {
    const priority_str = req.param("priority") orelse return Validation.MissingPriority;
    const name = req.param("name") orelse return Validation.MissingName;
    const body = req.body() orelse return Validation.MissingBody;
    const priority = std.fmt.parseInt(u8, priority_str, 16) catch |err| switch (err) {
        std.fmt.ParseIntError.Overflow => return Validation.PriorityOverflow,
        std.fmt.ParseIntError.InvalidCharacter => return Validation.PriorityInvalidCharacter,
    };
    return .{
        .body = try allocator.dupe(u8, body),
        .name = try allocator.dupe(u8, name),
        .nanoTimestamp = std.time.nanoTimestamp(),
        .priority = priority,
    };
}

pub fn copy(self: Self, allocator: Allocator) !Message {
    return .{
        .body = try allocator.dupe(u8, self.body),
        .name = try allocator.dupe(u8, self.name),
        .nanoTimestamp = self.nanoTimestamp,
        .priority = self.priority,
    };
}

pub fn free(self: Self, allocator: Allocator) void {
    allocator.free(self.body);
    allocator.free(self.name);
}
