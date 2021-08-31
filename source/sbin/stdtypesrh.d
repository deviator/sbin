module sbin.stdtypesrh;

import sbin.repr;
import sbin.type;

public import sbin.repr : CombineReprHandler;

import std.datetime : SysTime, UTC;
import std.bitmanip : BitArray;

struct SysTimeAsHNSecsRH(bool asUTC=false)
{
    enum sbinReprHandler;
static:
    struct R { long value; }

    R repr(in SysTime v)
    {
        static if (asUTC) return R(v.toUTC.stdTime);
        else return R(v.stdTime);
    }

    SysTime fromRepr(in R r)
    {
        static if (asUTC) return SysTime(r.value, UTC());
        else return SysTime(r.value);
    }
}

struct SysTimeAsUnixTimeRH(bool asUTC=false, bool use32bit=false)
{
    enum sbinReprHandler;
static:
    static if (use32bit) alias T = int;
    else alias T = long;

    struct R { T value; }

    R repr(in SysTime v)
    {
        static if (asUTC) return R(v.toUTC.toUnixTime!T);
        else return R(v.toUnixTime!T);
    }

    SysTime fromRepr(in R r)
    {
        static if (asUTC) return SysTime.fromUnixTime(r.value, UTC());
        else return SysTime.fromUnixTime(r.value);
    }
}

struct BitArrayRH
{
    enum sbinReprHandler;
static:
    struct R
    {
        vluint bits;
        const(void)[] data;
    }

    R repr(in BitArray v) { return R(vluint(v.length), cast(const(void)[])v); }

    BitArray fromRepr(in R r) { return BitArray(r.data.dup, r.bits); }
}

static if (__VERSION__ >= 2097)
{
    import std.typecons : Nullable;
    static import std.sumtype;

    struct NullableAsSumTypeRH
    {
        enum sbinReprHandler;
    static:
        alias ST = std.sumtype.SumType;

        auto repr(N)(in N n)
            if (is(N == Nullable!X, X))
        {
            alias R = ST!(typeof(null), typeof(N.init.get));
            return n.isNull ? R(null) : R(n.get);
        }

        auto fromRepr(N)(in N n)
            if (is(N == ST!X, X...) && X.length == 2 && is(X[0] == typeof(null)))
        {
            alias R = Nullable!(N.Types[1]);
            return n.match!(
                (typeof(null) v) => R.init,
                v => R(v)
            );
        }
    }
}
