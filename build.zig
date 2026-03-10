const std = @import("std");

pub fn build(b: *std.Build) void {
    const pic = b.option(bool, "pie", "Produce Position Independent Code");
    const prefix = b.option([]const u8, "prefix", "Prefix to use for symbols. Defaults to \"zng_\".") orelse "zng_";
    const lib_optimizations = b.option(bool, "enable_optimizations", "Enable architecture specific optimizations. Defaults to true.") orelse true;
    const upstream = b.dependency("zlib_ng", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var zlib_lib = b.addLibrary(.{
        .name = "zng",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = pic,
        }),
    });
    const base_flags: []const []const u8 = &.{
        "-Wno-implicit-function-declaration",
        if (optimize == .Debug) "-DZLIB_DEBUG" else "-DNDEBUG",
        "-DHAVE_SYMVER",
        "-D_LARGEFILE64_SOURCE=1",
        "-DHAVE_CPUID_GNU",
        "-DHAVE_SYS_AUXV_H",
        "-DHAVE_LINUX_AUXVEC_H",
        "-DHAVE_VISIBILITY_HIDDEN",
        "-DHAVE_VISIBILITY_INTERNAL",
        "-DHAVE_ATTRIBUTE_ALIGNED",
        "-DHAVE_BUILTIN_ASSUME_ALIGNED",
        "-DWITH_ALL_FALLBACKS",
        "-DWITH_OPTIM",
        "-DWITH_GZFILEOP=OFF", // This causes some issues if enabled ATM.
        "-DX86_FEATURES",
        "-DX86_HAVE_XSAVE_INTRIN",
    };

    const flags = if (lib_optimizations) {
        switch (target.result.cpu.arch) {
            .x86, .x86_64 => blk: {
                var flags = base_flags;
                if (pic == true) flags = flags ++ &.{"-fPIC"};

                break :blk flags;
            },
            .loongarch32, .loongarch64 => blk: {},

            else => base_flags,
        }
    } else if (pic == true) base_flags ++ &.{"-fPIC"} else base_flags;
    zlib_lib.root_module.addCSourceFiles(.{
        .flags = flags,
        .root = upstream.path(""),
        .files = &.{
            "adler32.c",
            "compress.c",
            "cpu_features.c",
            "crc32_braid_comb.c",
            "crc32.c",
            "deflate.c",
            "deflate_fast.c",
            "deflate_huff.c",
            "deflate_medium.c",
            "deflate_quick.c",
            "deflate_rle.c",
            "deflate_slow.c",
            "deflate_stored.c",
            "functable.c",
            "gzlib.c",
            "gzread.c",
            "gzwrite.c",
            "infback.c",
            "inflate.c",
            "inftrees.c",
            "insert_string.c",
            "insert_string_roll.c",
            "trees.c",
            "uncompr.c",
            "zutil.c",
        },
    });
    zlib_lib.installHeadersDirectory(upstream.path(""), "", .{});
    const autoconf_headers: []const []const u8 = &.{
        "gzread_mangle.h.in",
        "zlib.h.in",
        "zlib_name_mangling.h.in",
        "zlib_name_mangling-ng.h.in",
        "zlib-ng.h.in",
    };
    for (autoconf_headers) |path| {
        zlib_lib.root_module.addConfigHeader(b.addConfigHeader(.{
            .include_path = path[0 .. path.len - 3],
            .style = .{ .autoconf_at = upstream.path(path) },
        }, .{
            .ZLIB_SYMBOL_PREFIX = prefix,
        }));
    }
    zlib_lib.root_module.addConfigHeader(b.addConfigHeader(.{
        .include_path = "zconf.h",
        .style = .{ .autoconf_at = upstream.path("zconf.h.in") },
    }, .{}));
    zlib_lib.root_module.addConfigHeader(b.addConfigHeader(.{
        .include_path = "zconf-ng.h",
        .style = .{ .autoconf_at = upstream.path("zconf-ng.h.in") },
    }, .{}));
    zlib_lib.root_module.addCSourceFiles(.{
        .flags = flags,
        .root = upstream.path("arch/generic/"),
        .files = &.{
            "adler32_c.c",
            "adler32_fold_c.c",
            "chunkset_c.c",
            "compare256_c.c",
            "crc32_braid_c.c",
            "crc32_chorba_c.c",
            "crc32_fold_c.c",
            "slide_hash_c.c",
        },
    });
    // Some /arch files use header files from root path.
    zlib_lib.root_module.addIncludePath(upstream.path(""));
    zlib_lib.installHeadersDirectory(upstream.path("arch/generic/"), "", .{});
    zlib_lib.root_module.addCSourceFiles(.{
        .flags = flags,
        .root = b.path("extern/zlib-ng/arch/x86/"),
        .files = &.{
            "adler32_avx2.c",
            "adler32_avx512.c",
            "adler32_avx512_vnni.c",
            "adler32_sse42.c",
            "adler32_ssse3.c",
            "chorba_sse2.c",
            "chorba_sse41.c",
            "chunkset_avx2.c",
            "chunkset_avx512.c",
            "chunkset_sse2.c",
            "chunkset_ssse3.c",
            "compare256_avx2.c",
            "compare256_avx512.c",
            "compare256_sse2.c",
            "crc32_pclmulqdq.c",
            "crc32_vpclmulqdq.c",
            "slide_hash_avx2.c",
            "slide_hash_sse2.c",
            "x86_features.c",
        },
    });
    zlib_lib.installHeadersDirectory(b.path("extern/zlib-ng/arch/x86/"), "", .{});
    return zlib_lib;
}
