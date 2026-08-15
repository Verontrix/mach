const std = @import("std");
const Io = std.Io;
const build_info = @import("build_info");

pub const ProjectMetadata = struct {
    name: []const u8,
    fingerprint: u64,
};

pub const TemplateFile = struct {
    path: []const u8,
    contents: []const u8,
};

pub fn projectMetadata(io: Io, arena: std.mem.Allocator) !ProjectMetadata {
    const cwd_path = try std.process.currentPathAlloc(io, arena);
    const cwd_basename = std.fs.path.basename(cwd_path);
    const project_name = try sanitizeProjectName(arena, cwd_basename);

    // Generate a fingerprint matching what `zig init` would produce.
    const rng: std.Random.IoSource = .{ .io = io };
    const id = rng.interface().intRangeLessThan(u32, 1, 0xffffffff);
    const checksum = std.hash.Crc32.hash(project_name);

    return .{
        .name = project_name,
        .fingerprint = (@as(u64, checksum) << 32) | @as(u64, id),
    };
}

pub fn refuseExistingFiles(
    io: Io,
    command_name: []const u8,
    paths: []const []const u8,
    stderr: *Io.Writer,
) !void {
    const cwd = Io.Dir.cwd();
    for (paths) |path| {
        if (cwd.access(io, path, .{})) |_| {
            try stderr.print(
                "mach {s}: refusing to overwrite existing file '{s}'\n",
                .{ command_name, path },
            );
            std.process.exit(1);
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    }
}

pub fn writeFile(io: Io, dir: Io.Dir, sub_path: []const u8, contents: []const u8) !void {
    try dir.writeFile(io, .{ .sub_path = sub_path, .data = contents });
}

pub fn substituteZonTemplate(
    arena: std.mem.Allocator,
    command_name: []const u8,
    template: []const u8,
    project: ProjectMetadata,
) ![]const u8 {
    const new_name = try std.fmt.allocPrint(arena, ".name = .{s},", .{project.name});
    const new_fingerprint = try std.fmt.allocPrint(
        arena,
        ".fingerprint = 0x{x},",
        .{project.fingerprint},
    );

    const after_name = try replaceExpected(
        arena,
        command_name,
        template,
        ".name = .init_project,",
        new_name,
    );
    const after_fingerprint = try replaceExpected(
        arena,
        command_name,
        after_name,
        ".fingerprint = 0x72e87e5112345678,",
        new_fingerprint,
    );

    // The generated manifest receives its remote dependency from `zig fetch`.
    const mach_dependency =
        \\        .mach = .{
        \\            .path = "../..",
        \\        },
        \\
    ;
    return replaceExpected(
        arena,
        command_name,
        after_fingerprint,
        mach_dependency,
        "",
    );
}

pub fn fetchMachDependency(
    io: Io,
    arena: std.mem.Allocator,
    command_name: []const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !void {
    const mach_url = try std.fmt.allocPrint(
        arena,
        "https://pkg.hexops.org/pkg/hexops/mach/{s}.tar.gz",
        .{build_info.mach_version},
    );
    const fetch_argv = [_][]const u8{ "zig", "fetch", "--save=mach", mach_url };
    try stdout.print("running $ zig fetch --save=mach {s}\n", .{mach_url});
    try stdout.flush();

    var child = std.process.spawn(io, .{ .argv = &fetch_argv }) catch |err| {
        try stderr.print(
            "mach {s}: failed to spawn `zig fetch`: {t}\n" ++
                "Make sure `zig` is in your PATH and run this command from the generated " ++
                "project directory:\n" ++
                "  $ zig fetch --save=mach {s}\n",
            .{ command_name, err, mach_url },
        );
        try stderr.flush();
        std.process.exit(1);
    };
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) {
            try stderr.print(
                "mach {s}: `zig fetch` exited with code {d}\n" ++
                    "Run this command from the generated project directory to finish setup:\n" ++
                    "  $ zig fetch --save=mach {s}\n",
                .{ command_name, code, mach_url },
            );
            try stderr.flush();
            std.process.exit(1);
        },
        else => {
            try stderr.print(
                "mach {s}: `zig fetch` terminated abnormally\n" ++
                    "Run this command from the generated project directory to finish setup:\n" ++
                    "  $ zig fetch --save=mach {s}\n",
                .{ command_name, mach_url },
            );
            try stderr.flush();
            std.process.exit(1);
        },
    }
}

fn replaceExpected(
    arena: std.mem.Allocator,
    command_name: []const u8,
    haystack: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]const u8 {
    const count = std.mem.count(u8, haystack, needle);
    if (count != 1) {
        std.log.err(
            "mach {s}: expected '{s}' exactly once in the manifest template, found it {d} times",
            .{ command_name, needle, count },
        );
        return error.InitTemplateMalformed;
    }
    return std.mem.replaceOwned(u8, arena, haystack, needle, replacement);
}

// Borrowed from `zig init`.
fn sanitizeProjectName(
    arena: std.mem.Allocator,
    bytes: []const u8,
) error{OutOfMemory}![]const u8 {
    const max_name_len = 32;
    var result: std.ArrayList(u8) = .empty;
    for (bytes, 0..) |byte, i| switch (byte) {
        '0'...'9' => {
            if (i == 0) try result.append(arena, '_');
            try result.append(arena, byte);
        },
        '_', 'a'...'z', 'A'...'Z' => try result.append(arena, byte),
        '-', '.', ' ' => try result.append(arena, '_'),
        else => continue,
    };
    if (!std.zig.isValidId(result.items)) return "foo";
    if (result.items.len > max_name_len) result.shrinkRetainingCapacity(max_name_len);

    return result.toOwnedSlice(arena);
}
