const App = @import("app.zig");
const Request = @import("request.zig");
const httpz = @import("httpz");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app: App = .init(allocator);
    defer app.deinit();

    var server = try httpz.Server(*App).init(allocator, .{ .port = 5882 }, &app);
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.method("PUSH", "/:priority/:name", push, .{});
    router.method("POP", "/", pop, .{});

    try server.listen();
}

fn push(ctx: *Request, req: *httpz.Request, res: *httpz.Response) !void {
    try ctx.app.storage.store(req);
    res.status = 200;
}

fn pop(ctx: *Request, _: *httpz.Request, res: *httpz.Response) !void {
    if (try ctx.app.storage.pop(res.arena)) |message| {
        try res.json(message, .{});
    }
    res.status = 200;
}
