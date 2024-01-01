///
module sbin.serialize;

import std.array : appender;

import sbin.type;
import sbin.vluint;
import sbin.zigzag;
import sbin.repr;

/++ Serialize to output ubyte range

    Params:
        vals = serializible values
        r = output range
+/
void sbinSerialize(RH=EmptyReprHandler, R, string file=__FILE__, size_t line=__LINE__, Ts...)
    (auto ref R r, auto ref const Ts vals) if (isOutputRange!(R, ubyte) && Ts.length && isReprHandler!RH)
{
    void impl(T)(auto ref R r, auto ref const T val)
    {
        static if (hasRepr!(RH, T))
        {
            impl(r, RH.repr(val));
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
                impl(r, v);
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
                impl(r, v);
        }
        else static if (isAssociativeArray!T)
        {
            dumpVLUInt(r, val.length);
            foreach (k, ref v; val)
            {
                impl(r, k);
                impl(r, v);
            }
        }
        else static if (isTagged!(T).any)
        {
            impl(r, getTaggedTag(val));
            val.taggedMatch!(
                (v) {
                    static if (!is(Unqual!(typeof(v)) == typeof(null)))
                        impl(r, v);
                }
            );
        }
        else static if (hasCustomRepr!(T, RH))
        {
            // for @safe sbinSerialize sbinCustomRepr must be @trusted or @safe
            impl(r, val.sbinCustomRepr());
        }
        else static if (is(T == struct))
        {
            version (allowRawUnions)
            {
                import std : Nullable;
                static if (is(T == Nullable!A, A))
                    pragma(msg, file, "(", cast(int)line, "): ", "\033[33mWarning:\033[0m ",
                        T, " serialize as union, use NullableAsSumTypeRH for proper serialize!");
            }

            import std.traits : hasUDA;
            foreach (i, ref v; val.tupleof)
                static if (!hasUDA!(T.tupleof[i], sbinSkip))
                    impl(r, v);
        }
        else static if (is(T == union))
        {
            version (allowRawUnions)
                impl(r, (() @trusted => cast(void[T.sizeof])((cast(void*)&val)[0..T.sizeof]))());
            else
                static assert(0, "raw unions are not allowed, for allow build "~
                                    "with configuration 'allow-raw-unions'");
        }
        else static assert(0, "unsupported type: " ~ T.stringof);
    }

    static if (vals.length == 1) impl(r, vals[0]);
    else foreach (ref v; vals) impl(r, v);
}

/++ Serialize to ubyte[]

    using `appender!(ubyte[])` as output range

    Params:
        val = serializible value

    Returns:
        serialized data
+/
ubyte[] sbinSerialize(RH=EmptyReprHandler, T, string file=__FILE__, size_t line=__LINE__)
    (auto ref const T val) if (isReprHandler!RH)
{
    auto buf = appender!(ubyte[]);
    sbinSerialize!(RH, typeof(buf), file, line)(buf, val);
    return buf.data;
}
