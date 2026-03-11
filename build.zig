const std = @import("std");

pub fn build(b: *std.Build) void {
    const pic = b.option(bool, "pie", "Produce Position Independent Code");
    const prefix = b.option([]const u8, "prefix", "Prefix to use for symbols. Defaults to \"zng_\".") orelse "zng_";
    const disable_optimizations = b.option(bool, "disable_optimizations", "Disable architecture specific optimizations.") orelse false;
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
    var flags: []const []const u8 = &.{
        // "-Wno-implicit-function-declaration",
        if (optimize == .Debug) "-DZLIB_DEBUG" else "-DNDEBUG",
        "-DWITH_ALL_FALLBACKS", // TODO: check if needed.
        "-DWITH_GZFILEOP=OFF", // This causes some issues if enabled ATM.
    };
    if (target.result.os.tag != .macos) flags = flags ++ &.{"-DHAVE_SYMVER"};
    if (pic) flags = flags ++ &.{"-fPIC"};

    if (!disable_optimizations) {
        flags = flags ++ &.{"-DWITH_OPTIM"};
        switch (target.result.cpu.arch) {
            .x86, .x86_64 => flags = flags ++ blk: {
                var optim_flags: []const []const u8 = &.{"-DX86_FEATURES"};
                const feature_set = std.Target.x86.Feature;
                const features = target.result.cpu.features;
                if (features.isEnabled(feature_set.xsave))
                    optim_flags = optim_flags ++ &.{"-DX86_HAVE_XSAVE_INTRIN"};
                if (features.isEnabled(feature_set.sse2))
                    optim_flags = optim_flags ++ &.{"-DX86_SSE2"};
                if (features.isEnabled(feature_set.ssse3))
                    optim_flags = optim_flags ++ &.{"-DX86_SSSE3"};
                if (features.isEnabled(feature_set.sse4_1))
                    optim_flags = optim_flags ++ &.{"-DX86_SSE41"};
                if (features.isEnabled(feature_set.sse4_2))
                    optim_flags = optim_flags ++ &.{"-DX86_SSE42"};
                if (features.isEnabled(feature_set.pclmul))
                    optim_flags = optim_flags ++ &.{"-DX86_PCLMULQDQ_CRC"};
                if (features.isEnabled(feature_set.avx2))
                    optim_flags = optim_flags ++ &.{"-DX86_AVX2"};
                if (features.isEnabled(feature_set.avx2))
                    optim_flags = optim_flags ++ &.{"-DX86_AVX2"};
                if (features.isEnabled(feature_set.avx512f))
                    optim_flags = optim_flags ++ &.{"-DX86_AVX512"};
                if (features.isEnabled(feature_set.avx512vnni))
                    optim_flags = optim_flags ++ &.{"-DX86_AVX512VNNI"};
                if (features.isEnabled(feature_set.vpclmulqdq)) {
                    if (features.isEnabled(feature_set.avx2))
                        optim_flags = optim_flags ++ &.{"-DX86_VPCLMULQDQ_AVX2"};
                    if (features.isEnabled(feature_set.avx512f))
                        optim_flags = optim_flags ++ &.{"-DX86_VPCLMULQDQ_AVX512"};
                }
                break :blk optim_flags;
            },
            .arm, .aarch64 => blk: {
                var optim_flags: []const []const u8 = &.{"-DARM_FEATURES"};
                const feature_set = std.Target.arm.Feature;
                const features = target.result.cpu.features;
                // TODO: Properly check if arm_acle.h is present.
                optim_flags = optim_flags ++ &.{"-DHAVE_ARM_ACLE_H"};
                if (features.isEnabled(feature_set.neon)) {
                    optim_flags = optim_flags ++ &.{"-DARM_NEON"};
                    // TODO: Properly check for NEON LD4 support.
                    optim_flags = optim_flags ++ &.{"-DARM_NEON_HASLD4"};
                }
                // I'm not sure if this is the correct flags
                if (features.isEnabled(feature_set.v6) or features.isEnabled(feature_set.has_v6)) {
                    optim_flags = optim_flags ++ &.{"-DARM_SIMD"};
                    if (features.isEnabled(feature_set.v6))
                        optim_flags = optim_flags ++ &.{"-DARM_SIMD_INTRIN"};
                }
                // I'm not sure if this is the correct flags
                if (features.isEnabled(feature_set.has_v8)) {
                    optim_flags = optim_flags ++ &.{"-DARM_CRC32"};
                    if (features.isEnabled(feature_set.crc))
                        optim_flags = optim_flags ++ &.{"-DARM_CRC32_INTRIN"};
                    // I'm not sure if this is the correct flags
                    if (features.isEnabled(feature_set.neon))
                        optim_flags = optim_flags ++ &.{"-DARM_PMULL_EOR3"};
                }
                break :blk optim_flags;
            },
            .powerpc, .powerpc64, .powerpcle, .powerpc64le => blk: {
                var optim_flags: []const []const u8 = &.{"-DPPC_FEATURES"};
                const feature_set = std.Target.powerpc.Feature;
                const features = target.result.cpu.features;
                if (features.isEnabled(feature_set.altivec))
                    optim_flags = optim_flags ++ &.{"-DPPC_VMX"};
                if (features.isEnabled(feature_set.power8_altivec))
                    optim_flags = optim_flags ++ &.{ "-DPOWER8_VSX", "-DPOWER_FEATURES" };
                if (features.isEnabled(feature_set.power9_altivec))
                    optim_flags = optim_flags ++ &.{ "-DPOWER9", "-DPOWER_FEATURES" };
                break :blk optim_flags;
            },
            .riscv64 => blk: {
                var optim_flags: []const []const u8 = &.{"-DRISCV_FEATURES"};
                const feature_set = std.Target.powerpc.Feature;
                const features = target.result.cpu.features;
            },

            else => flags,
        }
    } else if (pic == true) flags ++ &.{"-fPIC"} else flags;
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
