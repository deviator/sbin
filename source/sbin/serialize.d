///
module sbin.serialize;

import std.array : appender;

import sbin.type;
import sbin.vluint;
import sbin.zigzag;
import sbin.repr;

/++ Serialize to output ubyte range

    Params:
        val - serializible value
        r - output range
+/
void sbinSerialize(RH=EmptyReprHandler, R, Ts...)(auto ref R r, auto ref const Ts vals)
    if (isOutputRange!(R, ubyte) && Ts.length && isReprHandler!RH)
{
    static if (Ts.length == 1)
    {
        alias T = Unqual!(Ts[0]);
        alias val = vals[0];

        static if (hasRepr!(RH, T))
        {
            sbinSerialize!RH(r, RH.repr(val));
        }
        else static if (is(T == enum))
        {
            put(r, getEnumNum(val).pack[]);
        }
        else static if (is(T == vluint))
        {
            dumpVLUInt(r, val.value);
        }
        else static if (is(T == vlint))
        {
            dumpVLUInt(r, zzEncode(val.value));
        }
        else static if (is(T : double) || is(T : long))
        {
            put(r, val.pack[]);
        }
        else static if (isVoidArray!T)
        {
            static if (isDynamicArray!T)
                dumpVLUInt(r, val.length);
            put(r, (() @trusted => cast(ubyte[])val[])());
        }
        else static if (isStaticArray!T)
        {
            foreach (ref v; val)
                sbinSerialize!RH(r, v);
        }
        else static if (isSomeString!T)
        {
            dumpVLUInt(r, val.length);
            put(r, (() @trusted => cast(ubyte[])val)());
        }
        else static if (isDynamicArray!T)
        {
            dumpVLUInt(r, val.length);
            foreach (ref v; val)
                sbinSerialize!RH(r, v);
        }
        else static if (isAssociativeArray!T)
        {
            dumpVLUInt(r, val.length);
            foreach (k, ref v; val)
            {
                sbinSerialize!RH(r, k);
                sbinSerialize!RH(r, v);
            }
        }
        else static if (isTagged!(T).any)
        {
            sbinSerialize!RH(r, val.kind);
            FS: final switch (val.kind)
            {
                static foreach (k; EnumMembers!(T.Kind))
                {
                    case k:
                        sbinSerialize!RH(r, cast(const(TypeOf!k))val);
                        break FS;
                }
            }
        }
        else static if (hasCustomRepr!(T, RH))
        {
            // for @safe sbinSerialize sbinCustomRepr must be @trusted or @safe
            sbinSerialize!RH(r, val.sbinCustomRepr());
        }
        else static if (is(T == struct))
        {
            foreach (ref v; val.tupleof)
                sbinSerialize!RH(r, v);
        }
        else static if (is(T == union))
        {
            sbinSerialize!RH(r, (() @trusted => cast(void[T.sizeof])((cast(void*)&val)[0..T.sizeof]))());
        }
        else static assert(0, "unsupported type: " ~ T.stringof);
    }
    else foreach (ref v; vals) sbinSerialize!RH(r, v);
}

/++ Serialize to ubyte[]

    using `appender!(ubyte[])` as output range

    Params:
        val = serializible value

    Returns:
        serialized data
+/
ubyte[] sbinSerialize(RH=EmptyReprHandler, T)(auto ref const T val) if (isReprHandler!RH)
{
    auto buf = appender!(ubyte[]);
    sbinSerialize!RH(buf, val);
    return buf.data;
}