const std = @import("std");
const Allocator = std.mem.Allocator;

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
