//! `mach init` initializes a new Mach project in the current directory.
const std = @import("std");
const Io = std.Io;
const common = @import("init-common.zig");

/// Files that are emitted verbatim from the editor/init-project/ template.
/// build.zig is special-cased separately so we can substitute the project name.
const verbatim_files = [_]common.TemplateFile{
    .{ .path = "src/App.zig", .contents = @embedFile("init-project/src/App.zig") },
    .{ .path = "src/shader.wgsl", .contents = @embedFile("init-project/src/shader.wgsl") },
};

const build_zig_template = @embedFile("init-project/build.zig");
const build_zig_zon_template = @embedFile("init-project/build.zig.zon");

const usage =
    \\Usage: mach init
    \\
    \\Initializes a new Mach project in the current directory.
    \\The project name is taken from the current directory name.
    \\
;

pub fn run(
    io: Io,
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !void {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or
            std.mem.eql(u8, arg, "--help"))
        {
            try stdout.writeAll(usage);
            return;
        }
        try stderr.print("mach init: unrecognized argument '{s}'\n\n", .{arg});
        try stderr.writeAll(usage);
        std.process.exit(1);
    }

    const project = try common.projectMetadata(io, arena);
    const cwd = Io.Dir.cwd();

    // Refuse to clobber existing files in the current directory.
    const all_files = [_][]const u8{
        "build.zig",
        "build.zig.zon",
        "src/App.zig",
        "src/shader.wgsl",
    };
    try common.refuseExistingFiles(io, "init", &all_files, stderr);

    // Write build.zig (substitute the placeholder binary name "hello-world" with the project name).
    const build_zig_contents = try std.mem.replaceOwned(
        u8,
        arena,
        build_zig_template,
        "hello-world",
        project.name,
    );
    try common.writeFile(io, cwd, "build.zig", build_zig_contents);
    try stdout.print("created build.zig\n", .{});

    // Generate build.zig.zon by performing substitutions on the embedded template.
    const zon_contents = try common.substituteZonTemplate(
        arena,
        "init",
        build_zig_zon_template,
        project,
    );
    try common.writeFile(io, cwd, "build.zig.zon", zon_contents);
    try stdout.print("created build.zig.zon\n", .{});

    // Write the verbatim source files.
    cwd.createDirPath(io, "src") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    for (verbatim_files) |f| {
        try common.writeFile(io, cwd, f.path, f.contents);
        try stdout.print("created {s}\n", .{f.path});
    }

    try common.fetchMachDependency(io, arena, "init", stdout, stderr);

    try stdout.print(
        \\
        \\Created Mach project "{s}".
        \\
        \\Run the project:
        \\
        \\  $ zig build run
        \\
        \\
    , .{project.name});
}
