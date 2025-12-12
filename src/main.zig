const std = @import("std");

const httpz = @import("httpz");

const App = @import("App.zig");
const errors = @import("errors.zig");
const Message = @import("Message.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();
    while (args_it.next()) |arg| {
        std.debug.print("{s}\n", .{arg});
    }

    var app = try App.init(allocator, .{ .use_file = false });

    var server = try httpz.Server(*App).init(allocator, .{ .port = 5883 }, &app);
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.put("/create/queue/:queue", createQueue, .{});
    router.put("/queue/:queue", putMessage, .{});
    router.get("/queue/:queue", getMessage, .{});

    try server.listen();
}

fn createQueue(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue = req.params.get("queue") orelse return errors.Queue.MissingQueueName;
    try app.createQueue(queue);
}

fn putMessage(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue = req.params.get("queue") orelse return errors.Queue.MissingQueueName;
    const data = req.body() orelse return error.MissingContent;
    if (!try app.containsQueue(queue)) return errors.Queue.QueueNotFound;
    try app.enqueueMessage(queue, data);
}

fn getMessage(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const queue = req.params.get("queue") orelse return errors.Queue.MissingQueueName;
    if (!try app.containsQueue(queue)) return errors.Queue.QueueNotFound;
    res.body = try app.dequeueMessageOrWait(res.arena, queue);
}
