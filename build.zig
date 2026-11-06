//! nanoui-controls: controls for nanoui apps that nanoui's kit doesn't
//! have. An app adds it with `zig fetch --save` and imports the module:
//!
//!     const controls = b.dependency("nanoui_controls", .{ .target = target, .optimize = optimize });
//!     exe.root_module.addImport("nanoui_controls", controls.module("nanoui_controls"));

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nanoui = b.dependency("nanoui", .{ .target = target, .optimize = optimize }).module("nanoui");

    const controls = b.addModule("nanoui_controls", .{
        .root_source_file = b.path("src/controls.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "nanoui", .module = nanoui }},
    });

    const tests = b.addTest(.{ .root_module = controls });
    b.step("test", "Run the controls' tests").dependOn(&b.addRunArtifact(tests).step);

    // The snapshot tests draw with nanoui's own text and CPU renderer, so
    // a drawing is the same on any machine (tests/snapshots.zig).
    const update = b.option(bool, "update-snapshots", "Write the snapshot tests' PNGs instead of comparing them") orelse false;
    const portable = b.dependency("nanoui", .{ .target = target, .optimize = optimize, .portable = true }).module("nanoui");
    const snapshot_options = b.addOptions();
    snapshot_options.addOption(bool, "update", update);
    const snapshots = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/snapshots.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nanoui", .module = portable },
            .{ .name = "nanoui_controls", .module = b.createModule(.{
                .root_source_file = b.path("src/controls.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "nanoui", .module = portable }},
            }) },
        },
    }) });
    snapshots.root_module.addOptions("snapshot_options", snapshot_options);
    const run_snapshots = b.addRunArtifact(snapshots);
    run_snapshots.setCwd(b.path("."));
    // The PNGs are read at run time: a changed one runs the tests again.
    run_snapshots.has_side_effects = true;
    b.step("test-snapshots", "Compare the grid's drawings with tests/snapshots").dependOn(&run_snapshots.step);

    const docs = b.addObject(.{ .name = "nanoui_controls", .root_module = controls });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.step("docs", "Build the API docs into zig-out/docs").dependOn(&install_docs.step);

    // The example: `zig build` builds it, `zig build example` runs it.
    const example = b.addExecutable(.{
        .name = "grid-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/grid/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nanoui", .module = nanoui },
                .{ .name = "nanoui_controls", .module = controls },
            },
        }),
    });
    b.installArtifact(example);
    b.step("example", "Run the grid example").dependOn(&b.addRunArtifact(example).step);
}
