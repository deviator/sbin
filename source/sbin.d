/// Simple binary [de]serialization
module sbin;

import std.array : appender;
import std.bitmanip : nativeToLittleEndian, littleEndianToNative;
import std.exception : enforce, assertThrown;
import std.range;
import std.string : format;
import std.traits;

///
alias length_t = ulong;

private alias pack = nativeToLittleEndian;

private auto unpack(T, size_t N)(ubyte[N] arr)
    if (N == T.sizeof)
{
    static if (T.sizeof == 1) return cast(T)arr[0];
    else return littleEndianToNative!T(arr);
}

///
class SBinException : Exception
{
    ///
    @safe @nogc pure nothrow
    this(string msg, string file=__FILE__, size_t line=__LINE__)
    { super(msg, file, line); }
}

///
class SBinDeserializeException : SBinException
{
    ///
    @safe @nogc pure nothrow
    this(string msg, string file=__FILE__, size_t line=__LINE__)
    { super(msg, file, line); }
}

///
class SBinDeserializeEmptyRangeException : SBinDeserializeException
{
    ///
    string mainType, fieldName, fieldType;
    ///
    size_t readed, expected, fullReaded;
    ///
    this(string mainType, string fieldName, string fieldType,
         size_t readed, size_t expected, size_t fullReaded) @safe pure
    {
        this.mainType = mainType;
        this.fieldName = fieldName;
        this.fieldType = fieldType;
        this.readed = readed;
        this.expected = expected;
        this.fullReaded = fullReaded;
        super(format("empty input range while "~
                "deserialize '%s' element %s:%s %d/%d (readed/expected), "~
                "readed message %d bytes", mainType, fieldName,
                fieldType, readed, expected, fullReaded));
    }
}

private template EnumNumType(T) if (is(T == enum))
{
    enum EMC = [EnumMembers!T].length;
    static if (EMC <= ubyte.max) alias Type = ubyte;
    else static if (EMC <= ushort.max) alias Type = ushort;
    else static if (EMC <= uint.max) alias Type = uint;
    else alias Type = ulong;
    alias EnumNumType = Type;
}

// only for serialize enums based on strings
private auto getEnumNum(T)(T val) @safe @nogc pure nothrow
    if (is(T == enum))
{
    alias Ret = EnumNumType!T;
    static foreach (Ret i; 0 .. [EnumMembers!T].length)
        if ((EnumMembers!T)[i] == val) return i;
    return Ret.max;
}

/++ Serialize to output ubyte range

    Params:
        val - serializible value
        r - output range
+/
void sbinSerialize(R, Ts...)(ref R r, auto ref const Ts vals)
    if (isOutputRange!(R, ubyte) && Ts.length)
{
    static if (Ts.length == 1)
    {
        alias T = Unqual!(Ts[0]);
        alias val = vals[0];
        static if (is(T : double) || is(T : long))
        {
            put(r, val.pack[]);
        }
        else static if (is(T == enum))
        {
            put(r, getEnumNum(val).pack[]);
        }
        else static if (isStaticArray!T)
        {
            foreach (ref v; val)
                sbinSerialize(r, v);
        }
        else static if (isSomeString!T)
        {
            put(r, (cast(length_t)val.length).pack[]);
            put(r, cast(ubyte[])val);
        }
        else static if (isDynamicArray!T)
        {
            put(r, (cast(length_t)val.length).pack[]);
            foreach (ref v; val) sbinSerialize(r, v);
        }
        else static if (isAssociativeArray!T)
        {
            put(r, (cast(length_t)val.length).pack[]);
            foreach (k, ref v; val)
            {
                sbinSerialize(r, k);
                sbinSerialize(r, v);
            }
        }
        else static if (isTypeTuple!T || is(T == struct))
        {
            foreach (ref v; val.tupleof)
                sbinSerialize(r, v);
        }
        else static assert(0, "unsupported type: " ~ T.stringof);
    }
    else foreach (ref v; vals) sbinSerialize(r, v);
}

/++ Serialize to ubyte[]

    using `appender!(ubyte[])` as output range

    Params:
        val = serializible value

    Returns:
        serialized data
+/
ubyte[] sbinSerialize(T)(auto ref const T val)
{
    auto buf = appender!(ubyte[]);
    sbinSerialize(buf, val);
    return buf.data.dup;
}

/++ Deserialize `Target` value

    Params:
        range = input range with serialized data (not saved before work)

    Returns:
        deserialized value
 +/
Target sbinDeserialize(Target, R)(R range)
{
    Unqual!Target ret;
    sbinDeserialize(range, ret);
    return ret;
}

/++ Deserialize `Target` value

    Params:
        range = input range with serialized data (not saved before work)
        target = reference to result object

    Returns:
        deserialized value
 +/
void sbinDeserialize(R, Target...)(R range, ref Target target)
{
    size_t cnt;

    ubyte pop(ref R rng, lazy string field, lazy string type,
                lazy size_t vcnt, lazy size_t vexp)
    {
        enforce (!rng.empty, new SBinDeserializeEmptyRangeException(
                    Target.stringof, field, type, vcnt, vexp, cnt));
        auto ret = rng.front;
        rng.popFront();
        cnt++;
        return ret;
    }

    auto impl(T)(ref R r, ref T trg, lazy string field)
    {
        string ff(lazy string n) { return field ~ "." ~ n; }
        string fi(size_t i) { return field ~ format("[%d]", i); }

        static if (is(T : double) || is(T : long))
        {
            ubyte[T.sizeof] tmp;
            version (LDC) auto _field = "<LDC-1.4.0 workaround>";
            else alias _field = field;
            foreach (i, ref v; tmp)
                v = pop(r, _field, T.stringof, i, T.sizeof);
            trg = tmp.unpack!T;
        }
        else static if (is(T == enum))
        {
            alias ENT = EnumNumType!T;
            enum EM = [EnumMembers!T];
            ubyte[ENT.sizeof] tmp;
            version (LDC) auto _field = "<LDC-1.4.0 workaround>";
            else alias _field = field;
            foreach (i, ref v; tmp)
                v = pop(r, _field, T.stringof, i, T.sizeof);
            trg = EM[tmp.unpack!ENT];
        }
        else static if (isSomeString!T)
        {
            length_t l;
            impl(r, l, ff("length"));
            auto length = cast(size_t)l;
            auto tmp = new ubyte[](length);
            foreach (i, ref v; tmp)
                v = pop(r, fi(i), T.stringof, i, length);
            trg = cast(T)tmp;
        }
        else static if (isStaticArray!T)
        {
            foreach (i, ref v; trg)
                impl(r, v, fi(i));
        }
        else static if (isDynamicArray!T)
        {
            length_t l;
            impl(r, l, ff("length"));
            if (trg.length != l)
                trg.length = cast(size_t)l;
            foreach (i, ref v; trg)
                impl(r, v, fi(i));
        }
        else static if (isAssociativeArray!T)
        {
            length_t l;
            impl(r, l, ff("length"));
            auto length = cast(size_t)l;

            trg.clear();

            foreach (i; 0 .. length)
            {
                KeyType!T k;
                ValueType!T v;
                impl(r, k, fi(i)~".key");
                impl(r, v, fi(i)~".val");
                trg[k] = v;
            }

            trg.rehash();
        }
        else static if (isTypeTuple!T || is(T == struct))
        {
            foreach (i, ref v; trg.tupleof)
                impl(r, v, ff(__traits(identifier, trg.tupleof[i])));
        }
        else static assert(0, "unsupported type: " ~ T.stringof);
    }

    static if (Target.length == 1)
        impl(range, target[0], typeof(target[0]).stringof);
    else foreach (ref v; target)
        impl(range, v, typeof(v).stringof);

    enforce(range.empty, new SBinDeserializeException(
        format("input range not empty after full '%s' deserialize", Target.stringof)));
}

version (unittest) import std.algorithm : equal;

unittest
{
    auto a = 123;
    assert(a.sbinSerialize.sbinDeserialize!int == a);
}

unittest
{
    auto a = 123;
    auto as = a.sbinSerialize;
    int x;
    sbinDeserialize(as, x);
    assert(a == x);
}

unittest
{
    auto s = "hello world";
    assert(equal(s.sbinSerialize.sbinDeserialize!string, s));
}

unittest
{
    immutable(int[]) a = [1,2,3,2,3,2,1];
    assert(a.sbinSerialize.sbinDeserialize!(int[]) == a);
}

unittest
{
    int[5] a = [1,2,3,2,3];
    assert(a.sbinSerialize.sbinDeserialize!(typeof(a)) == a);
}

unittest
{
    auto ap = appender!(ubyte[]);

    struct Cell
    {
        ulong id;
        float volt, temp;
        ushort soc, soh;
        string strData;
        bool tr;
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
                Cell(1, 1.1, 2.2, 5, 8, "one", true),
                Cell(2, 1.3, 2.5, 7, 9, "two"),
                Cell(3, 1.5, 2.8, 3, 7, "three"),
            ]
        ),
        Line(23,
            31.4, 21.7,
            [
                Cell(10, .11, .22, 50, 80, "1one1"),
                Cell(20, .13, .25, 70, 90, "2two2", true),
                Cell(30, .15, .28, 30, 70, "3three3"),
            ]
        ),
    ];

    auto sdata = lines.sbinSerialize;
    assert( equal(sdata.sbinDeserialize!(Line[]), lines));
    lines[0].cells[1].soh = 123;
    assert(!equal(sdata.sbinDeserialize!(Line[]), lines));
}

unittest
{
    static void foo(int a=123, string b="hello")
    { assert(a==123); assert(b=="hello"); }

    auto a = ParameterDefaults!foo;

    import std.typecons;
    auto sa = tuple(a).sbinSerialize;

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

unittest
{
    auto a = [1,2,3,4];
    auto as = a.sbinSerialize;
    auto as_tr = as[0..17];
    assertThrown!SBinDeserializeEmptyRangeException(as_tr.sbinDeserialize!(typeof(a)));
}

unittest
{
    auto a = [1,2,3,4];
    auto as = a.sbinSerialize;
    auto as_tr = as ~ as;
    assertThrown!SBinDeserializeException(as_tr.sbinDeserialize!(typeof(a)));
}

unittest
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

    auto as = a.sbinSerialize;
    auto bs = b.sbinSerialize;

    auto c = as.sbinDeserialize!X;

    import std.algorithm;
    assert(equal(sort(a.one.keys.dup), sort(c.one.keys.dup)));
    assert(equal(sort(a.one.values.dup), sort(c.one.values.dup)));

    bs.sbinDeserialize(c);

    assert(equal(sort(b.one.keys.dup), sort(c.one.keys.dup)));
    assert(equal(sort(b.one.values.dup), sort(c.one.values.dup)));
}

unittest
{
    enum T { one, two, three }
    T[] a;
    with(T) a = [one, two, three, two, three, two, one];
    auto as = a.sbinSerialize;

    auto b = as.sbinDeserialize!(typeof(a));
    assert(equal(a, b));
}

unittest
{
    enum T { one="one", two="2", three="III" }
    T[] a;
    with(T) a = [one, two, three, two, three, two, one];
    auto as = a.sbinSerialize;

    assert(as.length == 7 + length_t.sizeof);

    auto b = as.sbinDeserialize!(typeof(a));
    assert(equal(a, b));
}

unittest
{
    int ai = 543;
    auto as = "hello";

    import std.typecons;
    auto buf = sbinSerialize(tuple(ai, as));

    int bi;
    string bs;
    sbinDeserialize(buf, bi, bs);

    assert(ai == bi);
    assert(bs == as);
}

unittest
{
    int ai = 543;
    auto as = "hello";

    auto buf = appender!(ubyte[]);
    sbinSerialize(buf, ai, as);

    int bi;
    string bs;
    sbinDeserialize(buf.data, bi, bs);

    assert(ai == bi);
    assert(bs == as);
}

unittest
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

    auto bdata = new ubyte[](1024);
    auto buffer = Buffer(bdata);

    ubyte[] sdata;

    () @nogc { buffer.sbinSerialize(lines); }();

    assert(equal(buffer.data.sbinDeserialize!(typeof(lines)), lines));
}