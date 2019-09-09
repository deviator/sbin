/// Simple binary [de]serialization
module sbin;

import std.array : appender;
import std.bitmanip : nativeToLittleEndian, littleEndianToNative;
import std.exception : enforce, assertThrown;
import std.range;
import std.string : format;
import std.traits;
import std.algorithm.mutation : move;

version (Have_taggedalgebraic)
{
    import taggedalgebraic;

    template isTaggedUnion(T) {
        enum isTaggedUnion = is(T == TaggedUnion!X, X);
    }

    template isTaggedAlgebraic(T) {
        enum isTaggedAlgebraic = is(T == TaggedAlgebraic!X, X);
    }
}
else
{
    template isTaggedUnion(T) {
        enum isTaggedUnion = false;
    }
    template isTaggedAlgebraic(T) {
        enum isTaggedAlgebraic = false;
    }
}

version (sbin_ulong_length) alias length_t = ulong; ///
else alias length_t = uint; ///

version (unittest)
    pragma(msg, "sbin type of serialized length: ", length_t);

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

private bool isVoidArray(T)()
{
    static if( (is(T U == U[]) || is(T U == U[N], size_t N)) &&
                is(Unqual!U == void)) return true;
    else return false;
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

unittest
{
    enum Color
    {
        black = "#000000",
        red = "#ff0000",
        green = "#00ff00",
        blue = "#0000ff",
        white = "#ffffff"
    }

    static assert(is(EnumNumType!Color == ubyte));

    enum Level { low, medium, high }

    static assert(is(EnumNumType!Level == ubyte));

    static string bigElems() pure
    {
        import std.format : formattedWrite;
        auto buf = appender!(char[]);
        formattedWrite(buf, "enum Big { ");
        foreach (i; 0 .. 300)
            formattedWrite(buf, "e%d,", i);
        buf.put(" }");
        return buf.data.idup;
    }

    mixin(bigElems());

    static assert(is(EnumNumType!Big == ushort));
}

private auto getEnumNum(T)(T val) @safe @nogc pure nothrow
    if (is(T == enum))
{
    alias Ret = EnumNumType!T;
    static foreach (Ret i; 0 .. [EnumMembers!T].length)
        if ((EnumMembers!T)[i] == val) return i;
    return Ret.max;
}

private bool hasCustomRepr(T)()
{
    static if (hasMember!(T, "sbinCustomRepr") && hasMember!(T, "sbinFromCustomRepr"))
    {
        static if (isFunction!(T.init.sbinCustomRepr) &&
                   is(typeof(sbinSerialize(ReturnType!(T.init.sbinCustomRepr).init))))
        {
            ReturnType!(T.init.sbinCustomRepr) tmp;
            return isFunction!(T.sbinFromCustomRepr) &&
                   is(ReturnType!(T.sbinFromCustomRepr) == Unqual!T) &&
                   is(typeof(T.sbinFromCustomRepr(tmp)));

        }
        else return false;
    }
    else return false;
}

unittest
{
    static class Foo { ulong id; }
    static assert (hasCustomRepr!Foo == false);
}

unittest
{
    static class Foo
    {
        ulong id;
        ulong sbinCustomRepr() const @property { return id; }
    }
    static assert (hasCustomRepr!Foo == false);
}

unittest
{
    static class Foo
    {
        ulong id;
        this(ulong v) { id = v; }
        ulong sbinCustomRepr() const @property { return id; }
        static Foo sbinFromCustomRepr(ulong v) { return new Foo(v); }
    }
    static assert (hasCustomRepr!Foo == true);
}

unittest
{
    static class Bar { ulong id; this(ulong v) { id = v; } }
    static class Foo
    {
        ulong id;
        this(ulong v) { id = v; }
        Bar sbinCustomRepr() const @property { return new Bar(id); }
        static Foo sbinFromCustomRepr(Bar v) { return new Foo(v.id); }
    }
    static assert (hasCustomRepr!Foo == false);
}

unittest
{
    static struct Bar { ulong id; }
    static class Foo
    {
        ulong id;
        this(ulong v) { id = v; }
        Bar sbinCustomRepr() const @property { return Bar(id); }
        static Foo sbinFromCustomRepr(ref const Bar v) { return new Foo(v.id); }
    }
    static assert (hasCustomRepr!Foo == true);
}

unittest
{
    static class Foo
    {
        ulong id;
        this(ulong v) { id = v; }
        ulong sbinCustomRepr() const @property { return id; }
        static Foo sbinFromCustomRepr(ulong v, int add) { return new Foo(v+add); }
    }
    static assert (hasCustomRepr!Foo == false);
}

unittest
{
    static class Foo
    {
        ulong id;
        this(ulong v) { id = v; }
        ulong sbinCustomRepr() const @property { return id; }
        static Foo sbinFromCustomRepr(ulong v, int add=1) { return new Foo(v+add); }
    }
    static assert (hasCustomRepr!Foo == true);
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
        static if (is(T == enum))
        {
            put(r, getEnumNum(val).pack[]);
        }
        else static if (is(T : double) || is(T : long))
        {
            put(r, val.pack[]);
        }
        else static if (isVoidArray!T)
        {
            static if (isDynamicArray!T)
                put(r, (cast(length_t)val.length).pack[]);
            put(r, cast(ubyte[])val[]);
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
            foreach (ref v; val)
                sbinSerialize(r, v);
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
        else static if (isTaggedUnion!T || isTaggedAlgebraic!T)
        {
            sbinSerialize(r, val.kind);
            FS: final switch (val.kind)
            {
                static foreach (k; EnumMembers!(T.Kind))
                {
                    case k:
                        sbinSerialize(r, cast(TypeOf!k)val);
                        break FS;
                }
            }
        }
        else static if (hasCustomRepr!T)
        {
            sbinSerialize(r, val.sbinCustomRepr());
        }
        else static if (hasMember!(T, "sbinCustomSerialize"))
        {
            static assert(0, "sbinCustomSerialize is deprecated, use sbinCustomRepr instead");
        }
        else static if (is(T == struct))
        {
            foreach (ref v; val.tupleof)
                sbinSerialize(r, v);
        }
        else static if (is(T == union))
        {
            sbinSerialize(r, cast(void[T.sizeof])((cast(void*)&val)[0..T.sizeof]));
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
    return buf.data;
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

/++ Deserialize part of input range to `Target` value

    Params:
        range = input range with serialized data (not saved before work)

    Returns:
        deserialized value
 +/
Target sbinDeserializePart(Target, R)(ref R range)
{
    Unqual!Target ret;
    sbinDeserializePart(range, ret);
    return ret;
}

/++ Deserialize `Target` value

    Params:
        range = input range with serialized data (not saved before work)
        target = reference to result object
 +/
void sbinDeserializePart(R, Target...)(ref R range, ref Target target)
    if (isInputRange!R && is(Unqual!(ElementType!R) == ubyte))
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

        static if (is(T == enum))
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
        else static if (is(T : double) || is(T : long))
        {
            ubyte[T.sizeof] tmp;
            version (LDC) auto _field = "<LDC-1.4.0 workaround>";
            else alias _field = field;
            foreach (i, ref v; tmp)
                v = pop(r, _field, T.stringof, i, T.sizeof);
            trg = tmp.unpack!T;
        }
        else static if (isVoidArray!T)
        {
            static if (isDynamicArray!T)
            {
                length_t l;
                impl(r, l, ff("length"));
                if (trg.length != l)
                    trg.length = l;
            }

            auto tmp = cast(ubyte[])trg[];
            foreach (i, ref v; tmp)
                impl(r, v, fi(i));
        }
        else static if (isStaticArray!T)
        {
            foreach (i, ref v; trg)
                impl(r, v, fi(i));
        }
        else static if (isSomeString!T)
        {
            length_t l;
            impl(r, l, ff("length"));
            auto tmp = new ubyte[](cast(size_t)l);
            foreach (i, ref v; tmp)
                v = pop(r, fi(i), T.stringof, i, l);
            trg = cast(T)tmp;
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
        else static if (isTaggedUnion!T || isTaggedAlgebraic!T)
        {
            T.Kind kind;
            impl(r, kind, ff("kind"));
            FS: final switch (kind)
            {
                static foreach (k; EnumMembers!(T.Kind))
                {
                    case k:
                        TypeOf!k tmp;
                        impl(r, tmp, ff("value"));
                        static if (isTaggedUnion!T)
                            trg.set!k(move(tmp));
                        else
                            trg = tmp;
                        break FS;
                }
            }
        }
        else static if (hasCustomRepr!T)
        {
            ReturnType!(trg.sbinCustomRepr) tmp;
            impl(r, tmp, ff("customRepr"));
            trg = T.sbinFromCustomRepr(tmp);
        }
        else static if (hasMember!(T, "sbinCustomDeserialize"))
        {
            static assert(0, "sbinCustomDeserialize is deprecated: use sbinFromCustomRepr");
        }
        else static if (is(T == struct))
        {
            foreach (i, ref v; trg.tupleof)
                impl(r, v, ff(__traits(identifier, trg.tupleof[i])));
        }
        else static if (is(T == union))
        {
            auto tmp = cast(ubyte[])((cast(void*)&trg)[0..T.sizeof]);
            foreach (i, ref v; tmp) impl(r, v, fi(i));
        }
        else static assert(0, "unsupported type: " ~ T.stringof);
    }

    static if (Target.length == 1)
        impl(range, target[0], typeof(target[0]).stringof);
    else foreach (ref v; target)
        impl(range, v, typeof(v).stringof);
}

/++ Deserialize `Target` value

    Params:
        range = input range with serialized data (not saved before work)
        target = reference to result object

    Throws:
        SBinDeserializeException if range isn't empty after deseriazlie
 +/
void sbinDeserialize(R, Target...)(R range, ref Target target)
{
    sbinDeserializePart(range, target);

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
    //                      str                      color
            (length_t.sizeof + foo1.str.length) + ubyte.sizeof;

    // color is ubyte because [EnumMembers!Color].length < ubyte.max

    const foo1Data = foo1.sbinSerialize;

    assert(foo1Data.length == foo1Size);
    assert(foo1Data.sbinDeserialize!Foo == foo1);
    
    const foo2 = Foo(2, 2.22, 2.22, 2, "str2", Color.green);

    const foo2Size = ulong.sizeof + float.sizeof * 2 + ushort.sizeof +
            (length_t.sizeof + foo2.str.length) + ubyte.sizeof;

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
                    (length_t.sizeof + foo1Size + foo2Size);
    
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
    data[0].foos[1].d = 12345;
    assert(!equal(sdata.sbinDeserialize!(Bar[]), data));
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

    ubyte[300] bdata;
    auto buffer = Buffer(bdata[]);

    ubyte[] sdata;

    () @nogc { buffer.sbinSerialize(lines); }();

    assert(equal(buffer.data.sbinDeserialize!(typeof(lines)), lines));
}

unittest
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

unittest
{
    static bool ser, deser;
    static class Foo
    {
        ulong id;
        this(ulong v) { id = v; }
        ulong sbinCustomRepr() const
        {
            ser = true;
            return id;
        }
        static Foo sbinFromCustomRepr(ref const ulong v)
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

unittest
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

unittest
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

unittest
{
    struct Foo
    {
        ubyte[] a, b;
    }

    auto arr = cast(ubyte[])[1,2,3,4,5,6];
    auto foo = Foo(arr, arr[0..2]);
    assert (foo.a.ptr == foo.b.ptr);
    
    auto foo2 = foo.sbinSerialize.sbinDeserialize!Foo;
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
    import std.variant;

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

unittest
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

    auto su = u.sbinSerialize.sbinDeserialize!Union;
    assert (u.ival == 114);
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
    auto dsfoo2 = sbinDeserializePart!Foo2(data);

    assert (data.empty);

    assert(equal(cast(ubyte[])foo1.a, cast(ubyte[])dsfoo1.a));
    assert(equal(cast(ubyte[])foo1.b, cast(ubyte[])dsfoo1.b));
    assert(dsfoo2.a);
    assert(dsfoo2.b == false);
    assert(dsfoo2.c == 9);
    assert(dsfoo2.d == 3);
    
}