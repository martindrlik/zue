const std = @import("std");
const Allocator = std.mem.Allocator;

const Message = @import("Message.zig");

const Queue = @import("queue.zig").Queue(*Message, 100);

cond: std.Thread.Condition = .{},
mutex: std.Thread.Mutex = .{},
queues: std.StringArrayHashMapUnmanaged(*Queue) = .{},

const Self = @This();

pub fn createQueue(self: *Self, allocator: std.mem.Allocator, queue_name: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.queues.contains(queue_name)) {
        return error.QueueAlreadyExists;
    }
    const k = try allocator.dupe(u8, queue_name);
    const q = try allocator.create(Queue);
    q.* = .{};
    try self.queues.put(allocator, k, q);
}

pub fn add(self: *Self, allocator: std.mem.Allocator, queue_name: []const u8, message: *Message) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.queues.contains(queue_name)) {
        var q = self.queues.get(queue_name) orelse unreachable;
        try q.add(message);
    } else {
        const k = try allocator.dupe(u8, queue_name);
        var q = try allocator.create(Queue);
        q.* = .{};
        try self.queues.put(allocator, k, q);
        try q.add(message);
    }
    self.cond.signal();
}

pub fn removeOrWait(self: *Self, queue_name: []const u8) !*Message {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.queues.get(queue_name)) |queue| {
        return queue.removeOrWait();
    } else {
        return error.QueueNotFound;
    }
}

pub fn deleteQueue(self: *Self, allocator: std.mem.Allocator, queue_name: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.queues.get(queue_name)) |queue| {
        while (queue.removeOrNull()) |item| {
            allocator.free(&item.content);
        }
        if (!self.queues.swapRemove(queue_name)) return error.QueueNotFound;
    } else {
        return error.QueueNotFound;
    }
}
