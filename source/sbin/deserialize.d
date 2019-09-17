module sbin.deserialize;

import std.format;

import sbin.type;
import sbin.vluint;
import sbin.exception;

/++ Deserialize part of input ragne to `Target` value

    Params:
        range = input range with serialized data (not saved before work)
        target = reference to result object
 +/
void sbinDeserializePart(R, Target...)(ref R range, ref Target target)
    if (isInputRange!R && is(Unqual!(ElementType!R) == ubyte))
{
    static struct WrapRng
    {
        R* rng;
        size_t* count;

        string delegate() field;
        string delegate() type;
        size_t delegate() vcnt;
        size_t delegate() vexp;

        ubyte front() @property
        {
            enforce (!(*rng).empty, new SBinDeserializeEmptyRangeException(
                        Target.stringof, field(), type(), vcnt(), vexp(), *count));
            return (*rng).front;
        }

        void popFront()
        {
            (*rng).popFront();
            (*count)++;
        }

        bool empty() @property { return (*rng).empty; }
    }

    void setRngFields(ref WrapRng rng, lazy string field, lazy string type,
                lazy size_t vcnt, lazy size_t vexp)
    {
        rng.field = (){ return field; };
        rng.type = (){ return type; };
        rng.vcnt = (){ return vcnt; };
        rng.vexp = (){ return vexp; };
    }

    ubyte pop(ref WrapRng rng, lazy string field, lazy string type,
                lazy size_t vcnt, lazy size_t vexp)
    {
        setRngFields(rng, field, type, vcnt, vexp);

        auto ret = rng.front();
        rng.popFront();
        return ret;
    }

    auto impl(T)(ref WrapRng r, ref T trg, lazy string field)
    {
        string ff(lazy string n) { return field ~ "." ~ n; }
        string fi(size_t i) { return field ~ format("[%d]", i); }

        static if (is(T == enum))
        {
            alias ENT = EnumNumType!T;
            ubyte[ENT.sizeof] tmp;
            foreach (i, ref v; tmp)
                v = pop(r, field, T.stringof, i, T.sizeof);
            trg = [EnumMembers!T][tmp.unpack!ENT];
        }
        else static if (is(T : double) || is(T : long))
        {
            ubyte[T.sizeof] tmp;
            foreach (i, ref v; tmp)
                v = pop(r, field, T.stringof, i, T.sizeof);
            trg = tmp.unpack!T;
        }
        else static if (isVoidArray!T)
        {
            static if (isDynamicArray!T)
            {
                setRngFields(r, ff("length"), "vluint", 0, 10);
                const l = cast(size_t)readVLUInt(r);
                if (trg.length != l) trg.length = l;
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
            setRngFields(r, ff("length"), "vluint", 0, 10);
            const l = cast(size_t)readVLUInt(r);
            auto tmp = new ubyte[](l);
            foreach (i, ref v; tmp)
                v = pop(r, fi(i), T.stringof, i, l);
            trg = cast(T)tmp;
        }
        else static if (isDynamicArray!T)
        {
            setRngFields(r, ff("length"), "vluint", 0, 10);
            const l = cast(size_t)readVLUInt(r);
            if (trg.length != l) trg.length = l;
            foreach (i, ref v; trg)
                impl(r, v, fi(i));
        }
        else static if (isAssociativeArray!T)
        {
            setRngFields(r, ff("length"), "vluint", 0, 10);
            const length = cast(size_t)readVLUInt(r);

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
        else static if (isTagged!(T).any)
        {
            import std.algorithm.mutation : move;

            T.Kind kind;
            impl(r, kind, ff("kind"));
            FS: final switch (kind)
            {
                static foreach (k; EnumMembers!(T.Kind))
                {
                    case k:
                        TypeOf!k tmp;
                        impl(r, tmp, ff("value"));
                        static if (isTagged!(T).tUnion)
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

    size_t cnt;

    auto wr = WrapRng(&range, &cnt);

    static if (Target.length == 1)
        impl(wr, target[0], typeof(target[0]).stringof);
    else foreach (ref v; target)
        impl(wr, v, typeof(v).stringof);
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

    Throws:
        SBinDeserializeException if range isn't empty after deseriazlie
 +/
void sbinDeserialize(R, Target...)(R range, ref Target target)
{
    sbinDeserializePart(range, target);

    enforce(range.empty, new SBinDeserializeException(
        format("input range not empty after full '%s' deserialize", Target.stringof)));
}
