const std = @import("std");
const Allocator = std.mem.Allocator;
const httpz = @import("httpz");
const errors = @import("errors.zig");
const queue_impls = @import("queue.zig");
const Self = @This();

allocator: std.mem.Allocator,
queue: queue_impls.Queue,

pub const Config = struct {
    use_file: bool,
};

pub fn init(allocator: std.mem.Allocator, comptime config: Config) !Self {
    return .{
        .allocator = allocator,
        .queue = try pickQueueImpl(allocator, config.use_file),
    };
}

fn pickQueueImpl(allocator: Allocator, use_file: bool) !queue_impls.Queue {
    if (use_file) {
        return .{ .file = .{} };
    } else {
        const mem = try allocator.create(queue_impls.MemoryQueue);
        mem.* = .init(allocator);
        return .{ .memory = mem };
    }
}

pub fn createQueue(self: *Self, queue: []const u8) !void {
    try self.queue.create(queue);
}

pub fn containsQueue(self: *Self, queue: []const u8) !bool {
    return self.queue.contains(queue);
}

pub fn enqueueMessage(self: *Self, queue: []const u8, data: []const u8) !void {
    return self.queue.enqueue(queue, data);
}

pub fn dequeueMessageOrWait(self: *Self, allocator: std.mem.Allocator, queue: []const u8) ![]const u8 {
    return self.queue.dequeue(allocator, queue);
}

pub fn uncaughtError(_: *Self, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
    switch (err) {
        errors.Queue.MissingQueueName => {
            res.status = 400;
            res.body = "missing queue name";
        },
        errors.Queue.QueueAlreadyExists => {
            res.status = 400;
            res.body = "queue already exists";
        },
        errors.Queue.QueueNotFound => {
            res.status = 400;
            res.body = "queue not found";
        },
        else => {
            res.status = 500;
            res.body = "something went wrong";
        },
    }
    std.log.info("{} {} {s} {}", .{ res.status, req.method, req.url.path, err });
}
