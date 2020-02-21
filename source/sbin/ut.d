module sbin.ut;

import std.array : appender;

import sbin.type;
import sbin.exception;
import sbin.serialize;
import sbin.deserialize;

version (unittest) import std.algorithm : equal;

@safe unittest
{
    const a = 123;
    assert(a.sbinSerialize.sbinDeserialize!int == a);
}

@safe unittest
{
    enum V { v }
    const a = V.v;
    static assert(is(V == enum));
    static assert(is(EnumNumType!V == ubyte));
    const s = a.sbinSerialize;
    assert (s.length == 1);
    assert(s.sbinDeserialize!V == a);
}

@safe unittest
{
    const a = 123;
    auto as = a.sbinSerialize;
    int x;
    sbinDeserialize(as, x);
    assert(a == x);
}

@safe unittest
{
    auto s = "hello world";
    assert(equal(s.sbinSerialize.sbinDeserialize!string, s));
}

@safe unittest
{
    immutable(int[]) a = [1,2,3,2,3,2,1];
    assert(a.sbinSerialize.sbinDeserialize!(int[]) == a);
}

@safe unittest
{
    const int[5] a = [1,2,3,2,3];
    assert(a.sbinSerialize.sbinDeserialize!(typeof(a)) == a);
}

@safe unittest
{
    enum Color
    {
        black = "#000000",
        red = "#ff0000",
        green = "#00ff00",
        blue = "#0000ff",
        white = "#ffffff"
    }

    enum Level { low, medium, high }

    struct Foo
    {
        ulong a;
        float b, c;
        ushort d;
        string str;
        Color color;
    }
    
    const foo1 = Foo(10, 3.14, 2.17, 8, "s1", Color.red);

    //                  a              b         c       d
    const foo1Size = ulong.sizeof + float.sizeof * 2 + ushort.sizeof +
    //                            str                      color
            (1 /+length_t.sizeof+/ + foo1.str.length) + ubyte.sizeof; // 1 is length data because length < 127 (vluint pack)

    // color is ubyte because [EnumMembers!Color].length < ubyte.max

    const foo1Data = foo1.sbinSerialize;

    assert(foo1Data.length == foo1Size);
    assert(foo1Data.sbinDeserialize!Foo == foo1);
    
    const foo2 = Foo(2, 2.22, 2.22, 2, "str2", Color.green);

    const foo2Size = ulong.sizeof + float.sizeof * 2 + ushort.sizeof +
            (1 + foo2.str.length) + ubyte.sizeof;

    const foo2Data = foo2.sbinSerialize;

    assert(foo2Data.length == foo2Size);
    assert(foo2Data.sbinDeserialize!Foo == foo2);

    struct Bar
    {
        ulong a;
        float b;
        Level level;
        Foo[] foos;
    }

    auto bar = Bar(123, 3.14, Level.high, [ foo1, foo2 ]);
    
    //                   a               b          level
    const barSize = ulong.sizeof + float.sizeof + ubyte.sizeof +
    //                                 foos
                    (1 + foo1Size + foo2Size);
    
    assert(bar.sbinSerialize.length == barSize);

    auto data = [
        bar,
        Bar(23,
            31.4, Level.high,
            [
                Foo(10, .11, .22, 50, "1one1"),
                Foo(20, .13, .25, 70, "2two2", Color.black),
                Foo(30, .15, .28, 30, "3three3", Color.white),
            ]
        ),
    ];

    auto sdata = data.sbinSerialize;
    assert( equal(sdata.sbinDeserialize!(Bar[]), data));
    data[0].foos[1].d = 12_345;
    assert(!equal(sdata.sbinDeserialize!(Bar[]), data));
}

@safe unittest
{
    static void foo(int a=123, string b="hello")
    { assert(a==123); assert(b=="hello"); }

    auto a = ParameterDefaults!foo;

    import std.typecons : tuple;
    const sa = tuple(a).sbinSerialize;

    Parameters!foo b;
    b = sa.sbinDeserialize!(typeof(tuple(b)));
    assert(a == b);
    foo(b);

    a[0] = 234;
    a[1] = "okda";
    auto sn = tuple(a).sbinSerialize;

    sn.sbinDeserialize(b);

    assert(b[0] == 234);
    assert(b[1] == "okda");
}

@safe unittest
{
    auto a = [1,2,3,4];
    auto as = a.sbinSerialize;
    auto as_tr = as[0..$-3];
    assertThrown!SBinDeserializeEmptyRangeException(as_tr.sbinDeserialize!(typeof(a)));
}

@safe unittest
{
    auto a = [1,2,3,4];
    auto as = a.sbinSerialize;
    auto as_tr = as ~ as;
    assertThrown!SBinDeserializeException(as_tr.sbinDeserialize!(typeof(a)));
}

@safe unittest
{
    auto a = ["hello" : 123, "ok" : 43];
    auto as = a.sbinSerialize;

    auto b = as.sbinDeserialize!(typeof(a));
    assert(b["hello"] == 123);
    assert(b["ok"] == 43);
}

unittest
{
    static struct X
    {
        string[int] one;
        int[string] two;
    }

    auto a = X([3: "hello", 8: "abc"], ["ok": 1, "no": 2]);
    auto b = X([8: "abc", 15: "ololo"], ["zb": 10]);

    const as = a.sbinSerialize;
    const bs = b.sbinSerialize;

    auto c = as.sbinDeserialize!X;

    import std.algorithm : sort;
    assert(equal(sort(a.one.keys.dup), sort(c.one.keys.dup)));
    assert(equal(sort(a.one.values.dup), sort(c.one.values.dup)));

    bs.sbinDeserialize(c);

    assert(equal(sort(b.one.keys.dup), sort(c.one.keys.dup)));
    assert(equal(sort(b.one.values.dup), sort(c.one.values.dup)));
}

@safe unittest
{
    enum T { one, two, three }
    T[] a;
    with(T) a = [one, two, three, two, three, two, one];
    const as = a.sbinSerialize;

    auto b = as.sbinDeserialize!(typeof(a));
    assert(equal(a, b));
}

@safe unittest
{
    enum T { one="one", two="2", three="III" }
    T[] a;
    with(T) a = [one, two, three, two, three, two, one];
    const as = a.sbinSerialize;

    assert(as.length == 7 + 1);

    auto b = as.sbinDeserialize!(typeof(a));
    assert(equal(a, b));
}

@safe unittest
{
    const int ai = 543;
    auto as = "hello";

    import std.typecons : tuple;
    auto buf = sbinSerialize(tuple(ai, as));

    int bi;
    string bs;
    sbinDeserialize(buf, bi, bs);

    assert(ai == bi);
    assert(bs == as);
}

@safe unittest
{
    const int ai = 543;
    auto as = "hello";

    auto buf = appender!(ubyte[]);
    sbinSerialize(buf, ai, as);

    int bi;
    string bs;
    sbinDeserialize(buf.data, bi, bs);

    assert(ai == bi);
    assert(bs == as);
}

@safe unittest
{
    static struct ImplaceAppender(Arr)
    {
        Arr _data;
        size_t cur;

        this(Arr arr) { _data = arr; }

        @safe @nogc pure nothrow
        {
            void put(E)(E e)
                if (is(typeof(_data[0] = e)))
            {
                _data[cur] = e;
                cur++;
            }

            bool filled() const @property
            { return cur == data.length; }

            inout(Arr) data() inout { return _data[0..cur]; }

            void clear() { cur = 0; }
        }
    }

    alias Buffer = ImplaceAppender!(ubyte[]);

    static assert(isOutputRange!(Buffer, ubyte));

    enum State
    {
        one   = "ONE",
        two   = "TWO",
        three = "THREE",
    }

    struct Cell
    {
        ulong id;
        float volt, temp;
        ushort soc, soh;
        string strData;
        State state;
    }

    struct Line
    {
        ulong id;
        float volt, curr;
        Cell[] cells;
    }

    auto lines = [
        Line(123,
            3.14, 2.17,
            [
                Cell(1, 1.1, 2.2, 5, 8, "one", State.one),
                Cell(2, 1.3, 2.5, 7, 9, "two", State.two),
                Cell(3, 1.5, 2.8, 3, 7, "three", State.three),
            ]
        ),
        Line(23,
            31.4, 21.7,
            [
                Cell(10, .11, .22, 50, 80, "1one1", State.two),
                Cell(20, .13, .25, 70, 90, "2two2", State.three),
                Cell(30, .15, .28, 30, 70, "3three3", State.one),
            ]
        ),
    ];

    ubyte[300] bdata;
    auto buffer = Buffer(bdata[]);

    () @nogc { buffer.sbinSerialize(lines); }();

    assert(equal(buffer.data.sbinDeserialize!(typeof(lines)), lines));
}

@safe unittest
{
    static bool ser, deser;
    static struct Foo
    {
        ulong id;
        ulong sbinCustomRepr() const @property
        {
            ser = true;
            return id;
        }
        static Foo sbinFromCustomRepr(ulong v)
        {
            deser = true;
            return Foo(v);
        }
    }

    auto foo = Foo(12);

    assert(foo.sbinSerialize.sbinDeserialize!Foo == foo);
    assert(ser);
    assert(deser);
}

@safe unittest
{
    static bool ser, deser;
    static class Foo
    {
        ulong id;
        this(ulong v) @safe { id = v; }
        ulong sbinCustomRepr() const @safe
        {
            ser = true;
            return id;
        }
        static Foo sbinFromCustomRepr()(auto ref const ulong v) @safe
        {
            deser = true;
            return new Foo(v);
        }
    }

    auto foo = new Foo(12);

    assert(foo.sbinSerialize.sbinDeserialize!Foo.id == 12);
    assert(ser);
    assert(deser);

    Foo[] fooArr;
    foreach (i; 0 .. 10)
        fooArr ~= new Foo(i);

    import std.algorithm : map;

    auto fooArr2 = fooArr.sbinSerialize.sbinDeserialize!(Foo[]);
    assert(equal(fooArr.map!"a.id", fooArr2.map!"a.id"));
}

@safe unittest
{
    // for classes need
    // T sbinCustomRepr() const
    // static Foo sbinCustomDeserialize(T repr)
    static class Foo
    {
        ulong id;
        this(ulong v) { id = v; }
    }

    auto foo = new Foo(12);

    static assert(!is(typeof(foo.sbinSerialize)));
    static assert(!is(typeof(foo.sbinSerialize.sbinDeserialize!Foo.id)));
}

@safe unittest
{
    import std.bitmanip : bitfields;

    static struct Foo
    {
        mixin(bitfields!(
            bool, "a", 1,
            bool, "b", 1,
            ubyte, "c", 4,
            ubyte, "d", 2
        ));
    }

    static assert(Foo.sizeof == 1);

    Foo foo;
    foo.a = true;
    foo.b = false;
    foo.c = 9;
    foo.d = 3;

    assert(foo.a);
    assert(foo.b == false);
    assert(foo.c == 9);
    assert(foo.d == 3);

    auto sfoo = foo.sbinSerialize;

    assert(sfoo.length == 1);

    auto bar = sfoo.sbinDeserialize!Foo;

    assert(bar.a);
    assert(bar.b == false);
    assert(bar.c == 9);
    assert(bar.d == 3);

    assert(foo == bar);
}

@safe unittest
{
    struct Foo
    {
        ubyte[] a, b;
    }

    auto arr = cast(ubyte[])[1,2,3,4,5,6];
    const foo = Foo(arr, arr[0..2]);
    assert (foo.a.ptr == foo.b.ptr);
    
    const foo2 = foo.sbinSerialize.sbinDeserialize!Foo;
    assert(foo == foo2);
    assert(foo.a.ptr != foo2.a.ptr);
    assert(foo.b.ptr != foo2.b.ptr);
    assert(foo2.a.ptr != foo2.b.ptr);
}

unittest
{
    struct Foo { void[] a; }
    auto foo = Foo("hello".dup);
    auto foo2 = foo.sbinSerialize.sbinDeserialize!Foo;
    assert(equal(cast(ubyte[])foo.a, cast(ubyte[])foo2.a));
}

unittest
{
    struct Foo { void[5] a; }
    auto foo = Foo(cast(void[5])"hello");
    auto foo2 = foo.sbinSerialize.sbinDeserialize!Foo;
    assert(equal(cast(ubyte[])foo.a, cast(ubyte[])foo2.a));
}

unittest
{
    struct Foo { void[] a; void[5] b; }
    auto foo = Foo("hello".dup, cast(void[5])"world");
    auto foo2 = foo.sbinSerialize.sbinDeserialize!Foo;
    assert(equal(cast(ubyte[])foo.a, cast(ubyte[])foo2.a));
    assert(equal(cast(ubyte[])foo.b, cast(ubyte[])foo2.b));
}

unittest
{
    import std.variant : Algebraic;

    struct Foo
    {
        Algebraic!(int, float, string) data;
        this(int a) { data = a; }
        this(float a) { data = a; }
        this(string a) { data = a; }
    }

    auto foo = Foo(12);
    static assert(!__traits(compiles, foo.sbinSerialize.sbinDeserialize!Foo));
}

@safe unittest
{
    import std.algorithm : max;

    union Union
    {
        float fval;
        byte ival;
    }

    static assert(Union.init.sizeof == max(float.sizeof, byte.sizeof));

    Union u;
    u.ival = 114;
    assert (u.ival == 114);

    const su = u.sbinSerialize.sbinDeserialize!Union;
    assert (su.ival == 114);
}

unittest
{
    auto buf = appender!(ubyte[]);

    struct Foo1 { void[] a; void[5] b; }
    auto foo1 = Foo1("hello".dup, cast(void[5])"world");

    sbinSerialize(buf, foo1);

    static struct Foo2
    {
        import std.bitmanip : bitfields;
        mixin(bitfields!(
            bool, "a", 1,
            bool, "b", 1,
            ubyte, "c", 4,
            ubyte, "d", 2
        ));
    }

    Foo2 foo2;
    foo2.a = true;
    foo2.b = false;
    foo2.c = 9;
    foo2.d = 3;

    sbinSerialize(buf, foo2);

    auto data = buf.data;

    auto dsfoo1 = sbinDeserializePart!Foo1(data);
    const dsfoo2 = sbinDeserializePart!Foo2(data);

    assert (data.empty);

    assert(equal(cast(ubyte[])foo1.a, cast(ubyte[])dsfoo1.a));
    assert(equal(cast(ubyte[])foo1.b, cast(ubyte[])dsfoo1.b));
    assert(dsfoo2.a);
    assert(dsfoo2.b == false);
    assert(dsfoo2.c == 9);
    assert(dsfoo2.d == 3);
}

@safe unittest
{
    enum Label { good, bad }
    static struct Pos { int x, y; }
    static struct Point { Pos position; Label label; }

    Point[2] val = [
        Point(Pos(3,7), Label.good),
        Point(Pos(9,5), Label.bad),
    ];
    auto data = sbinSerialize(val);

    assert(data.length == 18);

    import std.algorithm : canFind;

    {
        bool throws;
        try auto dsv = sbinDeserialize!(Point[2])(data[0..$-3]);
        catch (SBinDeserializeEmptyRangeException e)
        {
            throws = true;
            assert (e.msg.canFind("root.elem[1].position.y.byte[2]:int 2/4"), e.msg);
        }
        assert (throws);
    }
    {
        bool throws;
        try const dsv = sbinDeserialize!(Point[2])(data[0..$-1]);
        catch (SBinDeserializeEmptyRangeException e)
        {
            throws = true;
            assert (e.msg.canFind("root.elem[1].label.byte[0]:Label 0/1"), e.msg);
        }
        assert (throws);
    }
    {
        bool throws;
        try const dsv = sbinDeserialize!(Point[2])(data[0..$/2+1]);
        catch (SBinDeserializeEmptyRangeException e)
        {
            throws = true;
            assert (e.msg.canFind("root.elem[1].position.x.byte[1]:int 1/4"), e.msg);
        }
        assert (throws);
    }
    {
        bool throws;
        try const dsv = sbinDeserialize!(Point[2])(data[0..$/2-1]);
        catch (SBinDeserializeEmptyRangeException e)
        {
            throws = true;
            assert (e.msg.canFind("root.elem[0].label.byte[0]:Label 0/1"), e.msg);
        }
        assert (throws);
    }
}

@safe unittest
{
    ushort[] val = [10,12,14,15];

    auto data = sbinSerialize(val);

    assert(data.length == 9);

    import std.algorithm : canFind;

    {
        bool throws;
        try const dsv = sbinDeserialize!(ushort[])(data[0..$-3]);
        catch (SBinDeserializeEmptyRangeException e)
        {
            throws = true;
            assert (e.msg.canFind("root.elem[2].byte[1]:ushort 1/2"), e.msg);
        }
        assert (throws);
    }

    {
        bool throws;
        try const dsv = sbinDeserialize!(ushort[])(data[0..0]);
        catch (SBinDeserializeEmptyRangeException e)
        {
            throws = true;
            assert (e.msg.canFind("root.length:vluint 0/10"), e.msg);
        }
        assert (throws);
    }
}

@safe unittest
{
    short[] value;
    auto rng = sbinSerialize(value);
    assert (rng.length == 1);
    assert (rng[0] == 0);

    assert (sbinDeserialize!(short[])(rng).length == 0);
}

@safe unittest
{
    vlint[] value = [vlint(1),vlint(2),vlint(3)];
    auto rng = sbinSerialize(value);
    assert (rng.length == 4);
    assert (rng[0] == 3);
    assert (rng[1] == 2);
    assert (rng[2] == 4);
    assert (rng[3] == 6);

    assert (value ==  sbinDeserialize!(typeof(value))(rng));
}

@safe unittest
{
    vlint[] value = [vlint(1),vlint(-130),vlint(3)];
    auto rng = sbinSerialize(value);
    assert (rng.length == 5);
    assert (rng[0] == 3);
    assert (rng[1] == 2);
    //assert (rng[2] == 4);
    assert (rng[4] == 6);

    assert (value ==  sbinDeserialize!(typeof(value))(rng));
}

@safe unittest
{
    vluint[] value = [vluint(1),vluint(2),vluint(3)];
    auto rng = sbinSerialize(value);
    assert (rng.length == 4);
    assert (rng[0] == 3);
    assert (rng[1] == 1);
    assert (rng[2] == 2);
    assert (rng[3] == 3);

    assert (value == sbinDeserialize!(typeof(value))(rng));
}