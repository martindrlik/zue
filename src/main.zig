const std = @import("std");

const httpz = @import("httpz");

const App = @import("App.zig");
const Message = @import("Message.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = App.init(allocator);

    var server = try httpz.Server(*App).init(allocator, .{ .port = 5882 }, &app);
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.put("/create/queue/:queue_name", createQueue, .{});
    router.put("/queue/:queue_name/:content", putMessage, .{});
    router.get("/queue/:queue_name", getMessage, .{});
    router.delete("/delete/queue/:queue_name", deleteQueue, .{});

    try server.listen();
}

fn createQueue(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse return error.MissingQueueName;
    try app.createQueue(queue_name);
}

fn putMessage(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse return error.MissingQueueName;
    const content = req.params.get("content") orelse return error.MissingContent;
    if (!app.containsQueue(queue_name)) return error.QueueNotFound;
    try app.add(queue_name, content);
}

fn getMessage(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse return error.MissingQueueName;
    if (!app.containsQueue(queue_name)) return error.QueueNotFound;
    res.body = try app.removeOrWait(res.arena, queue_name);
}

fn deleteQueue(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse return error.MissingQueueName;
    try app.deleteQueue(queue_name);
}
