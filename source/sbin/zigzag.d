module sbin.zigzag;

import std.range;
import std.traits : isUnsigned;

///
void dumpZigZag(R)(ref R r, ulong val) if (isOutputRange!(R, ubyte))
{
    immutable mask = cast(ubyte)0b0111_1111;
    immutable flag = cast(ubyte)0b1000_0000;
    do
    {
        r.put(cast(ubyte)((val & mask) + (val >= flag ? flag : 0)));
        val >>= 7;
    }
    while (val > 0);
}

version (unittest)
{
    import std.array : appender;
    import std.exception : enforce;
}

unittest
{
    auto buf = appender!(ubyte[]);
    foreach (i; 0 .. 128)
    {
        buf.clear();
        dumpZigZag(buf, i);
        assert (buf.data.length == 1);
        assert (buf.data[0] == i);
    }

    foreach (i; 128 .. 256)
    {
        buf.clear();
        dumpZigZag(buf, i);
        assert (buf.data.length == 2);
        assert (buf.data[0] == (i & 0b0111_1111) + 0b1000_0000);
        assert (buf.data[1] == 1);
    }

    void test(ulong val, ubyte[] need, string file=__FILE__, size_t line=__LINE__)
    {
        buf.clear();
        dumpZigZag(buf, val);
        enforce(buf.data == need, "fail", file, line);
    }

    test(127, [0b0111_1111]);
    test(128, [0b1000_0000, 1]);
    test(129, [0b1000_0001, 1]);
    test(130, [0b1000_0010, 1]);

    test(255, [0b1111_1111, 1]);
    test(256, [0b1000_0000, 0b10]);
    test(257, [0b1000_0001, 0b10]);

    test(16_382, [0b1111_1110, 0b0111_1111]);
    test(16_383, [0b1111_1111, 0b0111_1111]);
    test(16_384, [0b1000_0000, 0b1000_0000, 1]);
    test(16_385, [0b1000_0001, 0b1000_0000, 1]);

    enum b = ubyte.max;
    test(ulong.max-3, [b-3,b,b, b,b,b, b,b,b, 1]);
    test(ulong.max-2, [b-2,b,b, b,b,b, b,b,b, 1]);
    test(ulong.max-1, [b-1,b,b, b,b,b, b,b,b, 1]);
    test(ulong.max, [b,b,b, b,b,b, b,b,b, 1]);
}

///
ulong readZigZag(R)(auto ref R r, int* count=null) //if (isInputRange!(R, ubyte))
    if (is(typeof(r.front()) == ubyte) && is(typeof(r.popFront())))
{
    immutable mask = 0b0111_1111uL;
    immutable flag = 0b1000_0000uL;

    ubyte b = 0;

    ulong ret;

    while (true)
    {
        const v = r.front(); r.popFront();
        ret += (v & mask) << (b++ * 7);
        if (!(v & flag))
        {
            if (count !is null) *count = b;
            return ret;
        }
        if (b > 10) throw new Exception("so many data for one ulong value");
    }
}

unittest
{
    foreach (ubyte i; 0 .. 128)
    {
        ubyte[] buf = [i];
        assert(readZigZag(buf) == i);
    }

    void test(ulong val, ubyte[] need, string file=__FILE__, size_t line=__LINE__)
    {
        int cnt;
        auto readed = readZigZag(need.dup, &cnt);
        //import std.stdio;
        //stderr.writeln(cnt, " ", need.length);
        //stderr.writeln(val, " ", readed, " ", val-readed);
        assert (cnt == need.length);
        enforce(readed == val, "op", file, line);
    }

    test(127, [0b0111_1111]);
    test(128, [0b1000_0000, 1]);
    test(129, [0b1000_0001, 1]);
    test(130, [0b1000_0010, 1]);

    test(255, [0b1111_1111, 1]);
    test(256, [0b1000_0000, 0b10]);
    test(257, [0b1000_0001, 0b10]);

    test(16_382, [0b1111_1110, 0b0111_1111]);
    test(16_383, [0b1111_1111, 0b0111_1111]);
    test(16_384, [0b1000_0000, 0b1000_0000, 1]);
    test(16_385, [0b1000_0001, 0b1000_0000, 1]);

    enum b = ubyte.max;

    test(ulong.max, [b,b,b, b,b,b, b,b,b, 1]);
    test(ulong.max-1, [b-1,b,b, b,b,b, b,b,b, 1]);
    test(ulong.max-2, [b-2,b,b, b,b,b, b,b,b, 1]);
}

unittest
{
    static struct StaticBuffer(size_t N)
    {
        ubyte[N] data;
        size_t c;

        void put(ubyte v) { data[c++] = v; }

        ubyte front() { return data[c]; }
        void popFront() { c++; }
        bool empty() { return data.length == c; }
    }

    StaticBuffer!10 buf;

    import std.range : chain, iota, repeat, take;
    import std.random : uniform, Random;

    auto rnd = Random(12);

    auto values = chain(iota(ubyte.max),
            [ushort.max/2, ushort.max-1, ushort.max, ushort.max+1, ushort.max+2, ushort.max * 2],
            [uint.max/2, uint.max-1, uint.max, uint.max+1, uint.max+2, uint.max * 2],
            [ulong.max/2, ulong.max-1, ulong.max],
            uniform(0, ulong.max, rnd).repeat.take(10_000_000)
            );

    import std.datetime.stopwatch;

    StopWatch sw1, sw2;

    foreach (i; values)
    {
        buf.c = 0;

        sw1.start();
        dumpZigZag(buf, i);
        sw1.stop();

        buf.c = 0;

        sw2.start();
        const v = readZigZag(buf);
        sw2.stop();
        assert(i == v);
    }

    //import std.stdio;
    //stderr.writeln("dump: ", sw1.peek());
    //stderr.writeln("read: ", sw2.peek());
}