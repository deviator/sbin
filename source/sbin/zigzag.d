module sbin.zigzag;

@safe pure nothrow @nogc
{
ulong zzEncode(long i) { return (i >> (long.sizeof*8-1)) ^ (i << 1); }
long zzDecode(ulong i) { return (i >> 1) ^ -(i & 1); }
}

@safe
unittest
{
    import std.range : iota, chain;
    import std.format : format;

    foreach (i; chain(iota(-300,300),
                      [short.min, short.max],
                      [int.min, int.max],
                      [long.min, long.max]))
        assert(i == zzDecode(zzEncode(i)), format!"wrong zz %d"(i));
}