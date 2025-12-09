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

    var app = try App.init(allocator, .{ .use_file = true });

    var server = try httpz.Server(*App).init(allocator, .{ .port = 5883 }, &app);
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.put("/create/queue/:queue_name", createQueue, .{});
    router.put("/queue/:queue_name", putMessage, .{});
    router.get("/queue/:queue_name", getMessage, .{});
    router.delete("/delete/queue/:queue_name", deleteQueue, .{});

    try server.listen();
}

fn createQueue(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse return errors.Queue.MissingQueueName;
    try app.createQueue(queue_name);
}

fn putMessage(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse return errors.Queue.MissingQueueName;
    const content = req.body() orelse return error.MissingContent;
    if (!try app.containsQueue(queue_name)) return errors.Queue.QueueNotFound;
    try app.enqueueMessage(queue_name, content);
}

fn getMessage(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse return errors.Queue.MissingQueueName;
    if (!try app.containsQueue(queue_name)) return errors.Queue.QueueNotFound;
    res.body = try app.popMessageOrWait(res.arena, queue_name);
}

fn deleteQueue(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse return errors.Queue.MissingQueueName;
    try app.deleteQueue(queue_name);
}
