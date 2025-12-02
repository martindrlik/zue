const std = @import("std");
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const httpz = @import("httpz");

const Message = @import("Message.zig");
const Messages = @import("Messages.zig");

allocator: std.mem.Allocator,
messages: Messages = .{},

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !Self {
    var self = Self{
        .allocator = allocator,
    };
    try self.loadQueues();
    return self;
}

pub fn createQueue(self: *Self, queue_name: []const u8) !void {
    try self.messages.createQueue(self.allocator, queue_name);
}

pub fn containsQueue(self: *Self, queue_name: []const u8) bool {
    return self.messages.queues.contains(queue_name);
}

pub fn add(self: *Self, queue_name: []const u8, content: []const u8) !void {
    try self.addInternal(queue_name, content);
    try saveMessage(queue_name, content);
}

fn addInternal(self: *Self, queue_name: []const u8, content: []const u8) !void {
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
    try dropMessage(queue_name);
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

fn saveMessage(queue_name: []const u8, content: []const u8) !void {
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

fn dropMessage(queue_name: []const u8) !void {
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
    try file.setEndPos(try file.getEndPos() - (2 * @sizeOf(usize) + content_len));
}

fn loadMessage(self: *Self, queue_name: []const u8, reader: *std.fs.File.Reader) !void {
    const content_len = try reader.interface.takeInt(usize, .little);
    const content = try reader.interface.take(content_len);
    std.debug.assert(content_len == try reader.interface.takeInt(usize, .little));
    try self.addInternal(queue_name, content);
}

fn loadMessages(self: *Self, queue_name: []const u8, reader: *std.fs.File.Reader) !void {
    while (true) {
        self.loadMessage(queue_name, reader) catch |err| switch (err) {
            std.Io.Reader.Error.EndOfStream => break,
            else => return err,
        };
    }
}

fn loadQueues(self: *Self) !void {
    var dir = try queueDir();
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        try self.createQueue(entry.name);
        const file = try dir.openFile(entry.name, .{});
        defer file.close();
        var buf: [1024]u8 = undefined;
        var reader = file.reader(&buf);
        try self.loadMessages(entry.name, &reader);
        const queue = self.messages.queues.get(entry.name) orelse unreachable;
        std.debug.print("queue '{s}' loaded with {d} message(s)\n", .{ entry.name, queue.size });
    }
}

fn queueDir() !std.fs.Dir {
    return try std.fs.cwd().openDir("queue", .{ .iterate = true });
}
