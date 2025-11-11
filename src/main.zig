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
    router.put("/message/:content", putMessage, .{});
    router.get("/message", getMessage, .{});

    try server.listen();
}

fn putMessage(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    if (req.params.get("content")) |content| {
        var message = try app.allocator.create(Message);
        std.mem.copyForwards(u8, &message.content, content);
        message.content_len = content.len;
        try app.messages.add(message);
    }
}

fn getMessage(app: *App, _: *httpz.Request, res: *httpz.Response) !void {
    const message = app.messages.pop();
    defer app.allocator.destroy(message);
    var body = try res.arena.alloc(u8, message.content_len);
    @memcpy(body[0..message.content_len], message.content[0..message.content_len]);
    res.body = body;
}
