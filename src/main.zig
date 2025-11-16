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
    router.put("/q/:queue_name/:content", putMessage, .{});
    router.get("/q/:queue_name", getMessage, .{});

    try server.listen();
}

fn putMessage(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse "default";
    const content = req.params.get("content") orelse "";
    try app.add(queue_name, content);
}

fn getMessage(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const queue_name = req.params.get("queue_name") orelse "default";
    res.body = try app.removeOrWait(res.arena, queue_name);
}
