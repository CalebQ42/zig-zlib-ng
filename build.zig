const std = @import("std");

pub fn build(b: *std.Build) !void {
    const pic = b.option(bool, "pic", "Produce Position Independent Code");
    const prefix = b.option([]const u8, "prefix", "Prefix to use for symbols. Defaults to \"zng_\".") orelse "zng_";
    const disable_optimizations = b.option(bool, "disable_optimizations", "Disable architecture specific optimizations.") orelse false;
    const reduce_memory = b.option(bool, "reduce_memory", "Compile for a reduced memory footprint at the cost of performance") orelse false;
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

    var flags: std.ArrayList([]const u8) = try .initCapacity(b.allocator, 15);
    defer flags.deinit(b.allocator);
    flags.appendSliceAssumeCapacity(&.{
        "-std=c11",
        "-Wno-implicit-function-declaration",
        if (optimize == .Debug) "-DZLIB_DEBUG" else "-DNDEBUG",
        "-DWITH_ALL_FALLBACKS", // TODO: check if needed.
        "-DWITH_GZFILEOP=OFF", // This causes some issues if enabled ATM.
        // TODO: Double check all of the below are fully supported.
        "-DHAVE_BUILTIN_CTZ",
        "-DHAVE_VISIBILITY_HIDDEN",
        "-DHAVE_VISIBILITY_INTERNAL",
        "-DHAVE_ATTRIBUTE_ALIGNED",
        "-DHAVE_BUILTIN_ASSUME_ALIGNED",
        "-DHAVE_BUILTIN_CTZLL",
    });
    if (target.result.os.tag != .macos) try flags.append(b.allocator, "-DHAVE_SYMVER");
    if (pic != false) try flags.append(b.allocator, "-fPIC");
    if (reduce_memory) try flags.appendSlice(b.allocator, &.{ "-DHASH_SIZE=32768u", "-DGZBUFSIZE=8192", "-DNO_LIT_MEM" });

    if (!disable_optimizations) {
        try flags.append(b.allocator, "-DWITH_OPTIM");
        switch (target.result.cpu.arch) {
            .x86, .x86_64 => {
                try flags.append(b.allocator, "-DX86_FEATURES");
                const feature_set = std.Target.x86.Feature;
                const features = target.result.cpu.features;
                if (features.isEnabled(@intFromEnum(feature_set.xsave)))
                    try flags.append(b.allocator, "-DX86_HAVE_XSAVE_INTRIN");
                if (features.isEnabled(@intFromEnum(feature_set.sse2)))
                    try flags.append(b.allocator, "-DX86_SSE2");
                if (features.isEnabled(@intFromEnum(feature_set.ssse3)))
                    try flags.append(b.allocator, "-DX86_SSSE3");
                if (features.isEnabled(@intFromEnum(feature_set.sse4_1)))
                    try flags.append(b.allocator, "-DX86_SSE41");
                if (features.isEnabled(@intFromEnum(feature_set.sse4_2)))
                    try flags.append(b.allocator, "-DX86_SSE42");
                if (features.isEnabled(@intFromEnum(feature_set.pclmul)))
                    try flags.append(b.allocator, "-DX86_PCLMULQDQ_CRC");
                if (features.isEnabled(@intFromEnum(feature_set.avx2)))
                    try flags.append(b.allocator, "-DX86_AVX2");
                if (features.isEnabled(@intFromEnum(feature_set.avx2)))
                    try flags.append(b.allocator, "-DX86_AVX2");
                // This may not be the correct feature flag.
                if (features.isEnabled(@intFromEnum(feature_set.avx512f)))
                    try flags.append(b.allocator, "-DX86_AVX512");
                if (features.isEnabled(@intFromEnum(feature_set.avx512vnni)))
                    try flags.append(b.allocator, "-DX86_AVX512VNNI");
                if (features.isEnabled(@intFromEnum(feature_set.vpclmulqdq))) {
                    if (features.isEnabled(@intFromEnum(feature_set.avx2)))
                        try flags.append(b.allocator, "-DX86_VPCLMULQDQ_AVX2");
                    if (features.isEnabled(@intFromEnum(feature_set.avx512f)))
                        try flags.append(b.allocator, "-DX86_VPCLMULQDQ_AVX512");
                }
            },
            // In general, I'm not sure about basically any of these flags.
            .arm, .aarch64 => {
                try flags.append(b.allocator, "-DARM_FEATURES");
                const feature_set = std.Target.arm.Feature;
                const features = target.result.cpu.features;
                // TODO: Check if arm_acle.h is present.
                // try flags.append(b.allocator,"-DHAVE_ARM_ACLE_H");
                if (features.isEnabled(@intFromEnum(feature_set.neon))) {
                    try flags.append(b.allocator, "-DARM_NEON");
                    // TODO: Check for NEON LD4 support.
                    try flags.append(b.allocator, "-DARM_NEON_HASLD4");
                }
                if (features.isEnabled(@intFromEnum(feature_set.v6)) or features.isEnabled(@intFromEnum(feature_set.has_v6))) {
                    try flags.append(b.allocator, "-DARM_SIMD");
                    if (features.isEnabled(@intFromEnum(feature_set.v6)))
                        try flags.append(b.allocator, "-DARM_SIMD_INTRIN");
                }
                // I'm not sure if this is the correct flags
                if (features.isEnabled(@intFromEnum(feature_set.has_v8))) {
                    try flags.append(b.allocator, "-DARM_CRC32");
                    if (features.isEnabled(@intFromEnum(feature_set.crc)))
                        try flags.append(b.allocator, "-DARM_CRC32_INTRIN");
                    // I'm not sure if this is the correct flag for this feature.
                    if (features.isEnabled(@intFromEnum(feature_set.neon)))
                        try flags.append(b.allocator, "-DARM_PMULL_EOR3");
                }
            },
            .powerpc, .powerpc64, .powerpcle, .powerpc64le => {
                try flags.append(b.allocator, "-DPPC_FEATURES");
                const feature_set = std.Target.powerpc.Feature;
                const features = target.result.cpu.features;
                if (features.isEnabled(@intFromEnum(feature_set.altivec)))
                    try flags.append(b.allocator, "-DPPC_VMX");
                if (features.isEnabled(@intFromEnum(feature_set.power8_altivec)))
                    try flags.appendSlice(b.allocator, &.{ "-DPOWER8_VSX", "-DPOWER_FEATURES" });
                if (features.isEnabled(@intFromEnum(feature_set.power9_altivec)))
                    try flags.appendSlice(b.allocator, &.{ "-DPOWER9", "-DPOWER_FEATURES" });
            },
            .riscv64 => {
                try flags.append(b.allocator, "-DRISCV_FEATURES");
                const feature_set = std.Target.riscv.Feature;
                const features = target.result.cpu.features;
                // TODO: Check if asm/hwprobe.h is present.
                // try flags.append(b.allocator,"-DHAVE_ASM_HWPROBE_H");
                // TODO: Check for rvv features
                // try flags.append(b.allocator,"-DRIScV_RVV");
                if (features.isEnabled(@intFromEnum(feature_set.zbc)))
                    try flags.append(b.allocator, "-DRISCV_CRC32_ZBC");
            },
            .s390x => {
                try flags.append(b.allocator, "-DS390_FEATURES");
                const feature_set = std.Target.s390x.Feature;
                const features = target.result.cpu.features;
                if (features.isEnabled(@intFromEnum(feature_set.deflate_conversion)))
                    try flags.append(b.allocator, "-DS390_DFLTCC_DEFLATE");
                // TODO: Check for DFLTCC_INFLATE support
                // try flags.append(b.allocator,"-DS390_DFLTCC_INFLATE");
                // TODO: Check for vgfma support
                // try flags.append(b.allocator,"-DS390_CRC32_VX");
            },
            .loongarch64 => {
                try flags.append(b.allocator, "-DLOONGARCH_FEATURES");
                const feature_set = std.Target.loongarch.Feature;
                const features = target.result.cpu.features;
                // TODO: Check for la64 support
                // try flags.append(b.allocator,"-DLOONGARCH_CRC");
                if (features.isEnabled(@intFromEnum(feature_set.lsx)))
                    try flags.append(b.allocator, "-DLOONGARCH_LSX");
                if (features.isEnabled(@intFromEnum(feature_set.lasx)))
                    try flags.append(b.allocator, "-DLOONGARCH_LASX");
            },
            else => {},
        }
    }
    zlib_lib.root_module.addCSourceFiles(.{
        .flags = flags.items,
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

    // Some /arch files use header files from root path.
    zlib_lib.root_module.addIncludePath(upstream.path(""));
    zlib_lib.root_module.addCSourceFiles(.{
        .flags = flags.items,
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
    switch (target.result.cpu.arch) {
        .x86, .x86_64 => {
            zlib_lib.root_module.addCSourceFiles(.{
                .flags = flags.items,
                .root = upstream.path("arch/x86/"),
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
        },
        .arm, .aarch64 => {
            zlib_lib.root_module.addCSourceFiles(.{
                .flags = flags.items,
                .root = upstream.path("arch/arm/"),
                .files = &.{
                    "adler32_neon.c",
                    "arm_features.c",
                    "chunkset_neon.c",
                    "compare256_neon.c",
                    "crc32_armv8.c",
                    "crc32_armv8_pmull_eor3.c",
                    "slide_hash_armv6.c",
                    "slide_hash_neon.c",
                },
            });
        },
        .loongarch64 => {
            zlib_lib.root_module.addCSourceFiles(.{
                .flags = flags.items,
                .root = upstream.path("arch/loongarch/"),
                .files = &.{
                    "adler32_lasx.c",
                    "adler32_lsx.c",
                    "chunkset_lasx.c",
                    "chunkset_lsx.c",
                    "compare256_lasx.c",
                    "compare256_lsx.c",
                    "crc32_la.c",
                    "loongarch_features.c",
                    "slide_hash_lasx.c",
                    "slide_hash_lsx.c",
                },
            });
        },
        .powerpc, .powerpc64, .powerpcle, .powerpc64le => {
            zlib_lib.root_module.addCSourceFiles(.{
                .flags = flags.items,
                .root = upstream.path("arch/power/"),
                .files = &.{
                    "adler32_power8.c",
                    "adler32_vmx.c",
                    "chunkset_power8.c",
                    "compare256_power9.c",
                    "crc32_power8.c",
                    "power_features.c",
                    "slide_hash_power8.c",
                    "slide_hash_vmx.c",
                },
            });
        },
        .riscv64 => {
            zlib_lib.root_module.addCSourceFiles(.{
                .flags = flags.items,
                .root = upstream.path("arch/riscv/"),
                .files = &.{
                    "adler32_rvv.c",
                    "chunkset_rvv.c",
                    "compare256_rvv.c",
                    "crc32_zbc.c",
                    "riscv_features.c",
                    "slide_hash_rvv.c",
                },
            });
        },
        .s390x => {
            zlib_lib.root_module.addCSourceFiles(.{
                .flags = flags.items,
                .root = upstream.path("arch/s390/"),
                .files = &.{
                    "crc32-vx.c",
                    "dfltcc_deflate.c",
                    "dfltcc_inflate.c",
                    "s390_features.c",
                },
            });
        },
        else => {},
    }
    b.installArtifact(zlib_lib);
}
