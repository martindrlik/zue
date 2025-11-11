const std = @import("std");

const Message = @import("Message.zig");

cond: std.Thread.Condition,
mutex: std.Thread.Mutex,
queue: Queue,

const Self = @This();
const Queue = std.PriorityQueue(*Message, void, compare);

fn compare(_: void, _: *Message, _: *Message) std.math.Order {
    return .eq;
}

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .cond = .{},
        .mutex = .{},
        .queue = .init(allocator, {}),
    };
}

pub fn deinit(self: *Self) void {
    self.queue.deinit();
}

pub fn add(self: *Self, message: *Message) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    try self.queue.add(message);
    self.cond.signal();
}

pub fn pop(self: *Self) *Message {
    self.mutex.lock();
    while (self.queue.peek() == null) {
        self.cond.wait(&self.mutex);
    }
    const message = self.queue.remove();
    self.mutex.unlock();
    return message;
}
