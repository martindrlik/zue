const Allocator = std.mem.Allocator;
const Message = @import("message.zig");
const Self = @This();
const httpz = @import("httpz");
const std = @import("std");

queue: std.PriorityQueue(Message, void, cmp),

fn cmp(_: void, a: Message, b: Message) std.math.Order {
    return std.math.order(b.priority, a.priority);
}

pub fn init(allocator: Allocator) Self {
    return .{
        .queue = .init(allocator, undefined),
    };
}

pub fn deinit(self: *Self) void {
    self.queue.deinit();
}

pub fn store(self: *Self, req: *httpz.Request) !void {
    const message = try Message.parse(self.queue.allocator, req);
    errdefer message.free(self.queue.allocator);
    try persist(message);
    try self.queue.add(message);
}

fn persist(message: Message) !void {
    const fd = try std.posix.open(message.name, .{
        .ACCMODE = .WRONLY,
        .APPEND = true,
        .CREAT = true,
    }, 0o644);
    defer std.posix.close(fd);
    if (try std.posix.write(fd, message.body) != message.body.len) {
        return error.NotAllBytesWritten;
    }
}

pub fn pop(self: *Self, allocator: Allocator) !?Message {
    if (self.queue.removeOrNull()) |message| {
        defer message.free(self.queue.allocator);
        return try message.copy(allocator);
    }
    return null;
}
