module sbin.serialize;

import std.array : appender;

import sbin.type;
import sbin.vluint;
import sbin.zigzag;

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
            put(r, cast(ubyte[])val[]);
        }
        else static if (isStaticArray!T)
        {
            foreach (ref v; val)
                sbinSerialize(r, v);
        }
        else static if (isSomeString!T)
        {
            dumpVLUInt(r, val.length);
            put(r, cast(ubyte[])val);
        }
        else static if (isDynamicArray!T)
        {
            dumpVLUInt(r, val.length);
            foreach (ref v; val)
                sbinSerialize(r, v);
        }
        else static if (isAssociativeArray!T)
        {
            dumpVLUInt(r, val.length);
            foreach (k, ref v; val)
            {
                sbinSerialize(r, k);
                sbinSerialize(r, v);
            }
        }
        else static if (isTagged!(T).any)
        {
            sbinSerialize(r, val.kind);
            FS: final switch (val.kind)
            {
                static foreach (k; EnumMembers!(T.Kind))
                {
                    case k:
                        sbinSerialize(r, cast(const(TypeOf!k))val);
                        break FS;
                }
            }
        }
        else static if (hasCustomRepr!T)
        {
            sbinSerialize(r, val.sbinCustomRepr());
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