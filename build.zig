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

    const docs = b.addObject(.{ .name = "nanoui_controls", .root_module = controls });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.step("docs", "Build the API docs into zig-out/docs").dependOn(&install_docs.step);
}
