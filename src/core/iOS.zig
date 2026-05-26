//! iOS backend for mach.Core

const std = @import("std");
const mach = @import("../main.zig");
const Core = @import("../Core.zig");

pub const Native = struct {};

pub fn wakeMainThread(_: *Core) void {}

pub fn run(comptime on_each_update_fn: anytype, args_tuple: std.meta.ArgsTuple(@TypeOf(on_each_update_fn))) void {
    _ = @call(.auto, on_each_update_fn, args_tuple) catch |err| std.debug.panic("{s}", .{@errorName(err)});
}

pub fn tick(_: *Core, _: mach.Mod(Core), _: std.Io) !void {}
