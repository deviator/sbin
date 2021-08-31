module sbin.repr;

import std.traits : Unqual;
import std.meta : allSatisfy;

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

enum hasSerializeRepr(RH, T) = is(typeof(sbinSerialize!RH(RH.repr(T.init))));

enum hasDeserializeRepr(RH, T, Repr) =
    is( typeof(
            RH.fromRepr(sbinDeserialize!(RH, Repr)((ubyte[]).init))
        ) == Unqual!T);

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

struct CombineReprHandler(RHS...)
    if (allSatisfy!(isReprHandler, RHS))
{
    enum sbinReprHandler;

    static foreach (RH; RHS)
    {
        alias repr = RH.repr;
        alias fromRepr = RH.fromRepr;
    }
}

@safe unittest
{
    import std : SysTime, Duration, dur;

    static struct SysTimeAsLongRH
    {
        enum sbinReprHandler;
    static:
        struct R { long value; }
        R repr(in SysTime v) { return R(v.stdTime); }
        SysTime fromRepr(in R r) { return SysTime(r.value); }
    }

    static struct DurationAsLongRH
    {
        enum sbinReprHandler;
    static:
        struct R { long value; }
        R repr(in Duration v) { return R(v.total!"hnsecs"); }
        Duration fromRepr(in R r) { return dur!"hnsecs"(r.value); }
    }

    alias RH = CombineReprHandler!(SysTimeAsLongRH, DurationAsLongRH);

    static assert (isReprHandler!RH);

    static assert (hasSerializeRepr!(RH, SysTime));
    static assert (hasDeserializeRepr!(RH, SysTime, SysTimeAsLongRH.R));
    static assert (is(serializeRepr!(RH, SysTime) == SysTimeAsLongRH.R));
    static assert (hasRepr!(RH, SysTime));

    static assert (hasSerializeRepr!(RH, Duration));
    static assert (hasDeserializeRepr!(RH, Duration, DurationAsLongRH.R));
    static assert (is(serializeRepr!(RH, Duration) == DurationAsLongRH.R));
    static assert (hasRepr!(RH, Duration));
}
