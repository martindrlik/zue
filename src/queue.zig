const std = @import("std");
const Message = @import("Message.zig");
const errors = @import("errors.zig");

pub const Queue = union(enum) {
    file: FileQueue,
    memory: *MemoryQueue,

    pub fn create(self: Queue, queue: []const u8) !void {
        switch (self) {
            .file => {},
            .memory => |mem| return mem.createQueue(queue),
        }
    }

    pub fn contains(self: Queue, queue: []const u8) !bool {
        switch (self) {
            .file => |file| return file.contains(queue),
            .memory => |mem| return mem.contains(queue),
        }
    }

    pub fn enqueue(self: Queue, queue: []const u8, data: []const u8) !void {
        switch (self) {
            .file => |file| return file.enqueue(queue, data),
            .memory => |mem| return mem.enqueue(queue, data),
        }
    }

    pub fn dequeue(self: Queue, allocator: std.mem.Allocator, queue: []const u8) ![]const u8 {
        switch (self) {
            .file => |file| return file.dequeue(allocator, queue),
            .memory => |mem| return mem.dequeueOrWait(allocator, queue),
        }
    }
};

pub const FileQueue = struct {
    pub fn contains(_: FileQueue, queue: []const u8) !bool {
        var dir = try queueDir();
        defer dir.close();
        _ = dir.statFile(queue) catch |err| switch (err) {
            std.fs.File.OpenError.FileNotFound => return false,
            else => return err,
        };
        return true;
    }

    pub fn enqueue(_: FileQueue, queue: []const u8, data: []const u8) !void {
        var dir = try queueDir();
        defer dir.close();
        const file = try dir.createFile(queue, .{
            .truncate = false,
            .lock = .exclusive,
        });
        defer file.close();
        try file.seekFromEnd(0);
        var buf: [1024]u8 = undefined;
        var writer = file.writerStreaming(&buf);

        try writer.interface.writeInt(usize, data.len, .little);
        try writer.interface.writeAll(data[0..data.len]);
        try writer.interface.writeInt(usize, data.len, .little);

        try writer.interface.flush();
    }

    pub fn dequeue(_: FileQueue, allocator: std.mem.Allocator, queue: []const u8) ![]const u8 {
        var dir = try queueDir();
        defer dir.close();
        const file = try dir.createFile(queue, .{
            .truncate = false,
            .lock = .exclusive,
            .read = true,
        });
        defer file.close();
        try file.seekFromEnd(-@sizeOf(usize));
        var buf: [1024]u8 = undefined;
        var reader = file.readerStreaming(&buf);
        const data_len = try reader.interface.takeInt(usize, .little);
        try file.seekFromEnd(-@as(i64, @intCast(data_len)) - @sizeOf(usize));
        var data = try allocator.alloc(u8, data_len);
        const buf_data = try reader.interface.take(data_len);
        @memcpy(data[0..data_len], buf_data);
        try file.setEndPos(try file.getEndPos() - (2 * @sizeOf(usize) + data_len));
        return data;
    }

    fn queueDir() !std.fs.Dir {
        return try std.fs.cwd().openDir("queue", .{ .iterate = true });
    }
};

pub const MemoryQueue = struct {
    const Q = SimpleQueue(*Message, 100);

    allocator: std.mem.Allocator = undefined,
    cond: std.Thread.Condition = undefined,
    mutex: std.Thread.Mutex = undefined,
    queues: std.StringArrayHashMapUnmanaged(*Q) = undefined,

    pub fn init(allocator: std.mem.Allocator) MemoryQueue {
        return .{
            .allocator = allocator,
            .cond = .{},
            .mutex = .{},
            .queues = .{},
        };
    }

    pub fn contains(self: *MemoryQueue, queue: []const u8) !bool {
        return self.queues.contains(queue);
    }

    fn enqueue(self: *MemoryQueue, queue: []const u8, data: []const u8) !void {
        var message = try self.allocator.create(Message);
        std.mem.copyForwards(u8, &message.data, data);
        message.data_len = data.len;

        self.mutex.lock();
        errdefer self.mutex.unlock();
        if (self.queues.contains(queue)) {
            var q = self.queues.get(queue) orelse unreachable;
            try q.add(message);
        } else {
            const k = try self.allocator.dupe(u8, queue);
            var q = try self.allocator.create(Q);
            q.* = .{};
            try self.queues.put(self.allocator, k, q);
            try q.add(message);
        }
        self.mutex.unlock();
        self.cond.signal();
    }

    fn dequeueOrWait(self: *MemoryQueue, allocator: std.mem.Allocator, queue: []const u8) ![]const u8 {
        const message = try self.dequeue(queue);
        defer self.allocator.destroy(message);
        var data = try allocator.alloc(u8, message.data_len);
        @memcpy(data[0..message.data_len], message.data[0..message.data_len]);
        return data;
    }

    fn dequeue(self: *MemoryQueue, queue: []const u8) !*Message {
        self.mutex.lock();
        errdefer self.mutex.unlock();
        if (self.queues.get(queue)) |q| {
            self.mutex.unlock();
            return q.removeOrWait();
        } else {
            return errors.Queue.QueueNotFound;
        }
    }

    fn createQueue(self: *MemoryQueue, queue: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.queues.contains(queue)) {
            return errors.Queue.QueueAlreadyExists;
        }
        const k = try self.allocator.dupe(u8, queue);
        const q = try self.allocator.create(Q);
        q.* = .{};
        try self.queues.put(self.allocator, k, q);
    }

    fn deleteQueue(self: *MemoryQueue, allocator: std.mem.Allocator, queue: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.queues.get(queue)) |q| {
            while (q.removeOrNull()) |item| {
                allocator.free(&item.data);
            }
            if (self.queues.swapRemove(q)) {
                return;
            }
        }
        return errors.Queue.QueueNotFound;
    }
};

fn SimpleQueue(comptime T: type, capacity: usize) type {
    return struct {
        const Self = @This();

        cond: std.Thread.Condition = .{},
        mutex: std.Thread.Mutex = .{},
        items: [capacity]T = undefined,
        head: usize = 0,
        tail: usize = 0,
        size: usize = 0,

        pub fn add(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.size == self.items.len) {
                return error.Full;
            }
            self.size += 1;
            self.items[self.head] = item;
            self.head = (self.head + 1) % self.items.len;
            self.cond.signal();
        }

        pub fn removeOrWait(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (self.size == 0) {
                self.cond.wait(&self.mutex);
            }
            return self.remove();
        }

        pub fn removeOrNull(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.size == 0) {
                return null;
            } else {
                return self.remove();
            }
        }

        fn remove(self: *Self) T {
            self.size -= 1;
            const item = self.items[self.tail];
            self.tail = (self.tail + 1) % self.items.len;
            return item;
        }
    };
}

test SimpleQueue {
    var queue = SimpleQueue(u8, 2){};
    try queue.add(1);
    try queue.add(2);
    try std.testing.expectError(error.Full, queue.add(3));
    try std.testing.expectEqual(1, try queue.remove());
    try queue.add(3);
    try std.testing.expectEqual(2, try queue.remove());
    try std.testing.expectEqual(3, try queue.remove());
    try std.testing.expectError(error.Empty, queue.remove());
}
