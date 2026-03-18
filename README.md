# zlib-ng

[zlib-ng](https://github.com/zlib-ng/zlib-ng) packaged for [zig](https://ziglang.org).

## How to use it

First, update your `build.zig.zon`:

```
zig fetch --save https://github.com/CalebQ42/zig-zlib-ng/archive/refs/tags/2.3.3.tar.gz
```

Next, add this snippet to your `build.zig` script:

```zig
const zlib_ng_dep = b.dependency("zlib_ng", .{
    .target = target,
    .optimize = optimize,
});
your_compilation.linkLibrary(zlib_ng_dep.artifact("zng"));
```

This will provide zlib-ng as a static library to `your_compilation`.

## Current State

Currently *most* optimization flags have been ported over, but some may be improperly added, needs to have more restrictions on when they are added, or be tested on if they *can* be added properly. Additionally, I only have limited hardware to actually test everything on (Linux x86_64) so flags for other platforms/architectures are untested.
