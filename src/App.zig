const std = @import("std");
const Allocator = std.mem.Allocator;

const httpz = @import("httpz");

const errors = @import("errors.zig");
const Message = @import("Message.zig");
const Messages = @import("Messages.zig");

const Self = @This();

allocator: std.mem.Allocator,
messages: Messages = .{},
config: Config,

pub const Config = struct {
    use_file: bool,
};

pub fn init(allocator: std.mem.Allocator, comptime config: Config) !Self {
    return .{
        .allocator = allocator,
        .config = config,
    };
}

pub fn createQueue(self: *Self, queue_name: []const u8) !void {
    try if (!self.config.use_file) self.messages.createQueue(self.allocator, queue_name);
}

pub fn containsQueue(self: *Self, queue_name: []const u8) !bool {
    if (self.config.use_file) {
        return try fileExists(queue_name);
    } else {
        return self.messages.queues.contains(queue_name);
    }
}

fn fileExists(queue_name: []const u8) !bool {
    var dir = try queueDir();
    defer dir.close();
    _ = dir.statFile(queue_name) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => return false,
        else => return err,
    };
    return true;
}

pub fn enqueueMessage(self: *Self, queue_name: []const u8, content: []const u8) !void {
    if (self.config.use_file) {
        try fileEnqueue(queue_name, content);
    } else {
        try self.memEnqueue(queue_name, content);
    }
}

pub fn popMessageOrWait(self: *Self, allocator: std.mem.Allocator, queue_name: []const u8) ![]const u8 {
    if (self.config.use_file) {
        return try filePopNoWaitImplemented(allocator, queue_name);
    } else {
        return try self.memPopMessageOrWait(allocator, queue_name);
    }
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

fn memEnqueue(self: *Self, queue_name: []const u8, content: []const u8) !void {
    var message = try self.allocator.create(Message);
    std.mem.copyForwards(u8, &message.content, content);
    message.content_len = content.len;
    try self.messages.add(self.allocator, queue_name, message);
}

fn fileEnqueue(queue_name: []const u8, content: []const u8) !void {
    var dir = try queueDir();
    defer dir.close();
    const file = try dir.createFile(queue_name, .{
        .truncate = false,
        .lock = .exclusive,
    });
    defer file.close();
    try file.seekFromEnd(0);
    var buf: [1024]u8 = undefined;
    var writer = file.writerStreaming(&buf);

    try writer.interface.writeInt(usize, content.len, .little);
    try writer.interface.writeAll(content[0..content.len]);
    try writer.interface.writeInt(usize, content.len, .little);

    try writer.interface.flush();
}

fn memPopMessageOrWait(self: *Self, allocator: std.mem.Allocator, queue_name: []const u8) ![]const u8 {
    const message = try self.messages.removeOrWait(queue_name);
    defer self.allocator.destroy(message);
    var content = try allocator.alloc(u8, message.content_len);
    @memcpy(content[0..message.content_len], message.content[0..message.content_len]);
    return content;
}

fn filePopNoWaitImplemented(allocator: std.mem.Allocator, queue_name: []const u8) ![]const u8 {
    var dir = try queueDir();
    defer dir.close();
    const file = try dir.createFile(queue_name, .{
        .truncate = false,
        .lock = .exclusive,
        .read = true,
    });
    defer file.close();
    try file.seekFromEnd(-@sizeOf(usize));
    var buf: [1024]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    const content_len = try reader.interface.takeInt(usize, .little);
    try file.seekFromEnd(-@as(i64, @intCast(content_len)) - @sizeOf(usize));
    var content = try allocator.alloc(u8, content_len);
    const buf_content = try reader.interface.take(content_len);
    @memcpy(content[0..content_len], buf_content);
    try file.setEndPos(try file.getEndPos() - (2 * @sizeOf(usize) + content_len));
    return content;
}

fn queueDir() !std.fs.Dir {
    return try std.fs.cwd().openDir("queue", .{ .iterate = true });
}
