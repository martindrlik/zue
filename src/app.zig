const Allocator = std.mem.Allocator;
const App = @import("app.zig");
const Message = @import("message.zig");
const Request = @import("request.zig");
const Self = @This();
const Storage = @import("storage.zig");
const httpz = @import("httpz");
const std = @import("std");

storage: Storage = undefined,

pub fn init(allocator: Allocator) Self {
    return .{
        .storage = Storage.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.storage.deinit();
}

pub fn dispatch(self: *Self, action: httpz.Action(*Request), req: *httpz.Request, res: *httpz.Response) !void {
    var timer = try std.time.Timer.start();
    var ctx = Request{ .app = self };
    try action(&ctx, req, res);
    const elapsed = timer.lap() / 1000; // ns to µs
    std.log.info("{s} {s} {d}µs", .{ req.method_string, req.url.path, elapsed });
}

pub fn notFound(_: *App, req: *httpz.Request, res: *httpz.Response) !void {
    res.body = "Not Found";
    res.status = 404;
    std.log.info("404 {s} {s}", .{ req.method_string, req.url.path });
}

pub fn uncaughtError(_: *App, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
    res.body = "Error";
    res.status = 500;
    std.log.info("500 {s} {s} {}", .{ req.method_string, req.url.path, err });
}
