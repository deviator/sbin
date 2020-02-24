module sbin.repr;

import std : Unqual;

import sbin.serialize;
import sbin.deserialize;

struct EmptyReprHandler { enum sbinReprHandler; }

template isReprHandler(RH)
{
    enum isReprHandler = is(RH == struct) && __traits(hasMember, RH, "sbinReprHandler");
}

unittest
{
    static struct Foo { }

    static assert(isReprHandler!EmptyReprHandler);
    static assert(!isReprHandler!Foo);
}

template hasRepr(RH, T) if (isReprHandler!RH)
{
    static if (hasSerializeRepr!(RH, T))
        enum hasRepr = hasDeserializeRepr!(RH, T, serializeRepr!(RH, T));
    else
        enum hasRepr = false;
}

template hasSerializeRepr(RH, T)
{ enum hasSerializeRepr = is(typeof(sbinSerialize!RH(RH.repr(T.init)))); }

template hasDeserializeRepr(RH, T, Repr)
{ enum hasDeserializeRepr = is(typeof(RH.fromRepr((ubyte[]).init.sbinDeserialize!(RH, Repr)())) == Unqual!T); }

template serializeRepr(RH, T) if (hasSerializeRepr!(RH, T))
{ alias serializeRepr = typeof(RH.repr(T.init)); }

unittest
{
    static class Foo {}
    static struct Bar {}
    static assert (!hasRepr!(EmptyReprHandler, int));
    static assert (!hasRepr!(EmptyReprHandler, Foo));
    static assert (!hasRepr!(EmptyReprHandler, Bar));
}

unittest
{
    import std.datetime : SysTime;

    static struct CRH
    {
        enum sbinReprHandler;

    static:

        long repr()(auto ref const SysTime st) { return st.stdTime; }
        SysTime fromRepr()(auto ref const long v) { return SysTime(v); }
    }

    static assert (isReprHandler!CRH);
    static assert (!hasRepr!(EmptyReprHandler, SysTime));
    static assert (hasSerializeRepr!(CRH, SysTime));
    static assert (is(serializeRepr!(CRH, SysTime) == long));
    static assert (hasDeserializeRepr!(CRH, SysTime, long));
    static assert (hasRepr!(CRH, SysTime));
}