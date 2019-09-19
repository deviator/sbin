module sbin.type;

package import std.traits;
package import std.range;

import std.bitmanip : nativeToLittleEndian, littleEndianToNative;

alias length_t = uint;

package alias pack = nativeToLittleEndian;

package auto unpack(T, size_t N)(ubyte[N] arr)
    if (N == T.sizeof)
{
    static if (T.sizeof == 1) return cast(T)arr[0];
    else return littleEndianToNative!T(arr);
}

version (Have_taggedalgebraic) package import taggedalgebraic;

template isTagged(T)
{
    version (Have_taggedalgebraic)
    {
        enum tUnion = is(T == TaggedUnion!X, X);
        enum tAlgebraic = is(T == TaggedAlgebraic!X, X);
        enum any = tUnion || tAlgebraic;
    }
    else
    {
        enum any = false;
        enum tUnion = false;
        enum tAlgebraic = false;
    }
}

template isVoidArray(T)
{
    static if( (is(T U == U[]) || is(T U == U[N], size_t N)) &&
                is(Unqual!U == void)) enum isVoidArray = true;
    else enum isVoidArray = false;
}

unittest
{
    assert (isVoidArray!(void[]));
    assert (isVoidArray!(void[2]));
    assert (isVoidArray!(const(void)[]));
    assert (isVoidArray!(const(void[])));
    assert (isVoidArray!(const(void)[2]));
    assert (isVoidArray!(const(void[2])));
    assert (isVoidArray!(immutable(void)[]));
    assert (isVoidArray!(immutable(void[])));
    assert (isVoidArray!(immutable(void)[2]));
    assert (isVoidArray!(immutable(void[2])));

    assert (!isVoidArray!(long[]));
    assert (!isVoidArray!(long[2]));
    assert (!isVoidArray!(byte[]));
    assert (!isVoidArray!(byte[2]));
}

template EnumNumType(T) if (is(T == enum))
{
    enum C = [EnumMembers!T].length;
         static if (C <= ubyte.max)  alias EnumNumType = ubyte;
    else static if (C <= ushort.max) alias EnumNumType = ushort;
    else static if (C <= uint.max)   alias EnumNumType = uint;
    else                             alias EnumNumType = ulong;
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
        import std.array : appender;
        import std.range : put;

        auto buf = appender!(char[]);
        formattedWrite(buf, "enum Big { ");
        foreach (i; 0 .. 300)
            formattedWrite(buf, "e%d,", i);
        buf.put(" }");
        return buf.data.idup;
    }

    mixin(bigElems());

    static assert(is(EnumNumType!Big == ushort));
    assert(is(EnumNumType!Big == ushort));
}

///
auto getEnumNum(T)(T val) @safe @nogc pure nothrow
    if (is(T == enum))
{
    alias Ret = EnumNumType!T;
    static foreach (Ret i; 0 .. [EnumMembers!T].length)
        if ((EnumMembers!T)[i] == val) return i;
    return Ret.max;
}

unittest
{
    enum Foo { one, two }
    assert (getEnumNum(Foo.two) == 1);
    static assert(is(typeof(getEnumNum(Foo.two)) == ubyte));
    assert(is(typeof(getEnumNum(Foo.two)) == ubyte));
}

///
template hasCustomRepr(T)
{
    static if (hasMember!(T, "sbinCustomRepr") && hasMember!(T, "sbinFromCustomRepr"))
    {
        import sbin.serialize : sbinSerialize;

        alias Repr = ReturnType!(() => T.init.sbinCustomRepr);

        enum hasCustomRepr = is(typeof(sbinSerialize(Repr.init))) && 
                is(typeof(((){ return T.sbinFromCustomRepr(Repr.init); })()) == Unqual!T);
    }
    else enum hasCustomRepr = false;
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
    assert (hasCustomRepr!Foo == false);
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
    assert (hasCustomRepr!Foo == true);
    auto foo = new Foo(12);
    assert (foo.sbinCustomRepr == 12);
    auto foo2 = Foo.sbinFromCustomRepr(foo.sbinCustomRepr);
    assert (foo.id == foo2.id);
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
        static Foo sbinFromCustomRepr()(auto ref const Bar v) { return new Foo(v.id); }
    }
    import sbin.serialize : sbinSerialize;
    static assert (is(typeof(sbinSerialize(Bar.init))));
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