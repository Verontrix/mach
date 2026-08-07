const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;

const App = @This();

const log = std.log.scoped(.triangles);

/// The scene is a big rotating ring of `outer_count` small circles, each small circle made of
/// `mid_count` triangles, and each triangle spins on its own. Bump these to increase GPU load.
const outer_count = 12;
const mid_count = 12;
const triangle_count = outer_count * mid_count;

const Uniforms = extern struct {
    time: f32,
    outer_count: f32,
    mid_count: f32,
    aspect: f32,
};

// The set of Mach modules our application may use.
pub const Modules = mach.Modules(.{
    mach.Core,
    App,
});

pub const mach_module = .app;

pub const mach_systems = .{
    .main,
    .init,
    .tick,
    .tickApp,
    .render,
    .deinit,
};

pub const main = mach.schedule(.{
    .{ mach.Core, .init },
    .{ App, .init },
    .{ mach.Core, .main },
});

pipeline: ?*gpu.RenderPipeline = null,
bind_group: ?*gpu.BindGroup = null,
uniform_buffer: ?*gpu.Buffer = null,
app_thread: mach.Thread,
window: mach.ObjectID,

/// Seconds since start; used to compute a per-frame delta for animation.
timer: mach.time.Timer,
/// Cadence timer for periodic FPS logging to the console.
log_timer: mach.time.Timer,

/// Animation speed multiplier (1x, 2x, 3x, ...), controlled with the up/down arrow keys.
speed_mult: u32 = 1,
/// How the animation time fed to the shader is derived, toggled with the 't' key:
/// - .frame_delta: accumulate per-frame deltas (frame-rate independent, smooth across speed changes)
/// - .absolute: recompute directly from the absolute wall clock each frame
time_mode: enum { frame_delta, absolute } = .frame_delta,
/// Animation time fed to the shader (see time_mode).
anim_time: f32 = 0,
/// timer.read() at the previous frame, used to compute the per-frame delta.
last_time: f32 = 0,

pub fn init(
    core: *mach.Core,
    app: *App,
    app_mod: mach.Mod(App),
    core_mod: mach.Mod(mach.Core),
    io: std.Io,
) !void {
    core.on_exit = app_mod.id.deinit;

    const window = try core.windows.new(.{
        .title = "core-triangles",
        .on_render = app_mod.id.render,
    });

    app.* = .{
        .app_thread = try mach.startThread(core, app_mod.id.tick, core_mod, .app),
        .window = window,
        .timer = mach.time.Timer.start(io),
        .log_timer = mach.time.Timer.start(io),
    };
}

fn setupPipeline(core: *mach.Core, app: *App) !void {
    const window = core.windows.getValue(core.window);
    const device = window.device;
    const label = @tagName(mach_module) ++ ".init";

    const shader_module = device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = window.framebuffer_format,
        .blend = &blend,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    // Uniform buffer holding time / count / aspect, updated once per frame.
    const uniform_buffer = device.createBuffer(&.{
        .label = label ++ " uniforms",
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(Uniforms),
        .mapped_at_creation = .false,
    });

    const bind_group_layout = device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = label,
        .entries = &.{gpu.BindGroupLayout.Entry.initBuffer(0, .{ .vertex = true }, .uniform, false, 0)},
    }));
    defer bind_group_layout.release();

    const bind_group = device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .label = label,
        .layout = bind_group_layout,
        .entries = &.{gpu.BindGroup.Entry.initBuffer(0, uniform_buffer, 0, @sizeOf(Uniforms), @sizeOf(Uniforms))},
    }));

    const bind_group_layouts = [_]*gpu.BindGroupLayout{bind_group_layout};
    const pipeline_layout = device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = label,
        .bind_group_layouts = &bind_group_layouts,
    }));
    defer pipeline_layout.release();

    app.pipeline = device.createRenderPipeline(&gpu.RenderPipeline.Descriptor{
        .label = label,
        .fragment = &fragment,
        .layout = pipeline_layout,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
    });
    app.bind_group = bind_group;
    app.uniform_buffer = uniform_buffer;
}

pub const tick = mach.schedule(.{
    .{ App, .tickApp },
    .{ mach.Core, .snapshotStart },
    .{ mach.Core, .snapshotEnd },
});

pub fn tickApp(core: *mach.Core, app: *App) void {
    var iter = core.events(.default);
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| switch (ev.key) {
                .v => {
                    // V key: cycle to the next vsync mode and print it to the console.
                    const vsync = core.windows.get(ev.window_id, .vsync_mode);
                    const new_vsync: mach.Core.VSyncMode = switch (vsync) {
                        .double => .triple,
                        .triple => .low_latency,
                        .low_latency => .adaptive,
                        .adaptive => .none_low_latency,
                        .none_low_latency => .none_max_throughput,
                        .none_max_throughput => .double,
                    };
                    core.windows.set(ev.window_id, .vsync_mode, new_vsync);
                    log.info("vsync mode -> {s}", .{@tagName(new_vsync)});
                },
                .up => {
                    // Up arrow: increase animation speed (capped at 64x).
                    if (app.speed_mult < 64) app.speed_mult += 1;
                    log.info("speed -> {d}x", .{app.speed_mult});
                },
                .down => {
                    // Down arrow: decrease animation speed (minimum 1x).
                    if (app.speed_mult > 1) app.speed_mult -= 1;
                    log.info("speed -> {d}x", .{app.speed_mult});
                },
                .t => {
                    // T key: toggle how animation time is derived.
                    app.time_mode = switch (app.time_mode) {
                        .frame_delta => .absolute,
                        .absolute => .frame_delta,
                    };
                    log.info("animation time: {s}", .{switch (app.time_mode) {
                        .frame_delta => "frame delta",
                        .absolute => "absolute",
                    }});
                },
                else => {},
            },
            .close => core.exit(),
            else => {},
        }
    }
}

pub fn render(app: *App, core: *mach.Core) !void {
    const pipeline = app.pipeline orelse {
        try setupPipeline(core, app);
        return;
    };
    const label = @tagName(mach_module) ++ ".render";
    const window = core.windows.getValue(core.window);

    const back_buffer_view = window.swap_chain.getCurrentTextureView() orelse return;
    defer back_buffer_view.release();

    const encoder = window.device.createCommandEncoder(&.{ .label = label });
    defer encoder.release();

    // Derive animation time (scaled by the speed multiplier) using the mode toggled by the 't' key.
    const now = app.timer.read();
    const speed: f32 = @floatFromInt(app.speed_mult);
    switch (app.time_mode) {
        // Accumulate per-frame deltas: frame-rate independent and continuous across speed changes.
        .frame_delta => app.anim_time += (now - app.last_time) * speed,
        // Recompute directly from the absolute wall clock each frame.
        .absolute => app.anim_time = now * speed,
    }
    app.last_time = now;

    // Update per-frame uniforms (all animation is driven on the GPU from these).
    const aspect: f32 = @as(f32, @floatFromInt(window.width)) / @as(f32, @floatFromInt(@max(window.height, 1)));
    const uniforms = Uniforms{
        .time = app.anim_time,
        .outer_count = @floatFromInt(outer_count),
        .mid_count = @floatFromInt(mid_count),
        .aspect = aspect,
    };
    encoder.writeBuffer(app.uniform_buffer.?, 0, &[_]Uniforms{uniforms});

    const sky_blue_background = gpu.Color{ .r = 0.776, .g = 0.988, .b = 1, .a = 1 };
    const color_attachments = [_]gpu.RenderPassColorAttachment{.{
        .view = back_buffer_view,
        .clear_value = sky_blue_background,
        .load_op = .clear,
        .store_op = .store,
    }};
    const render_pass = encoder.beginRenderPass(&gpu.RenderPassDescriptor.init(.{
        .label = label,
        .color_attachments = &color_attachments,
    }));
    defer render_pass.release();

    // Draw all triangle instances in a single instanced draw call.
    render_pass.setPipeline(pipeline);
    render_pass.setBindGroup(0, app.bind_group.?, &.{});
    render_pass.draw(3, triangle_count, 0, 0);

    render_pass.end();

    var command = encoder.finish(&.{ .label = label });
    defer command.release();
    window.queue.submit(&[_]*gpu.CommandBuffer{command});

    // Print FPS / input rate / vsync mode to the console about once per second.
    if (app.log_timer.read() >= 1.0) {
        _ = app.log_timer.lap();
        const vsync = core.windows.get(app.window, .vsync_mode);
        log.info("[ {d}fps ] [ input {d}hz ] [ triangles: {d} ] [ vsync: {s} ]", .{
            window.frame.rate, core.input.rate, triangle_count, @tagName(vsync),
        });
    }
}

pub fn deinit(app: *App) void {
    app.app_thread.join();
    if (app.pipeline) |p| p.release();
    if (app.bind_group) |b| b.release();
    if (app.uniform_buffer) |b| b.release();
}
