const std = @import("std");
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const httpz = @import("httpz");

const Message = @import("Message.zig");
const Messages = @import("Messages.zig");

allocator: std.mem.Allocator,
messages: Messages = .{},

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn createQueue(self: *Self, queue_name: []const u8) !void {
    try self.messages.createQueue(self.allocator, queue_name);
}

pub fn containsQueue(self: *Self, queue_name: []const u8) bool {
    return self.messages.queues.contains(queue_name);
}

pub fn add(self: *Self, queue_name: []const u8, content: []const u8) !void {
    var message = try self.allocator.create(Message);
    std.mem.copyForwards(u8, &message.content, content);
    message.content_len = content.len;
    try self.messages.add(self.allocator, queue_name, message);
}

pub fn removeOrWait(self: *Self, allocator: std.mem.Allocator, queue_name: []const u8) ![]const u8 {
    const message = try self.messages.removeOrWait(queue_name);
    defer self.allocator.destroy(message);
    var content = try allocator.alloc(u8, message.content_len);
    @memcpy(content[0..message.content_len], message.content[0..message.content_len]);
    return content;
}

pub fn deleteQueue(self: *Self, queue_name: []const u8) !void {
    try self.messages.deleteQueue(self.allocator, queue_name);
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
