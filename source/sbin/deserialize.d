///
module sbin.deserialize;

import std.format;

import sbin.type;
import sbin.vluint;
import sbin.zigzag;
import sbin.exception;
import sbin.repr;

/++ Deserialize part of input ragne to `Target` value

    Params:
        range = input range with serialized data (not saved before work)
        target = reference to result object
 +/
void sbinDeserializePart(RH=EmptyReprHandler, R, string file=__FILE__, size_t line=__LINE__, Target...)
    (scope ref R range, ref Target target) if (isInputRange!R && is(Unqual!(ElementType!R) == ubyte) && isReprHandler!RH)
{
    import sbin.util.stack : Stack;

    static struct FieldName
    {
        string name;
        ptrdiff_t index = -1;

        string toString() const
        {
            if (index != -1) return format!"%s[%d]"(name, index);
            else return name;
        }
    }

    alias FNStack = Stack!(FieldName, 8);

    FNStack fNameStack;

    static struct WrapRng
    {
        R* rng;
        size_t* count;
        FNStack* fstack;

        string field() const
        {
            import std.algorithm: map, joiner;
            import std.array : array;
            import std.conv : to;
            return fstack.getData().map!(a=>a.toString()).joiner(".").array.to!string;
        }

        string type;
        size_t vcnt;
        size_t vexp;

        ubyte front() @property
        {
            enforce (!(*rng).empty, new SBinDeserializeEmptyRangeException(
                        Target.stringof, field(), type, vcnt, vexp, *count));
            return (*rng).front;
        }

        void popFront()
        {
            (*rng).popFront();
            (*count)++;
        }

        bool empty() @property { return (*rng).empty; }
    }

    void setRngFields(ref WrapRng rng, string type, size_t vcnt, size_t vexp)
    { rng.type = type; rng.vcnt = vcnt; rng.vexp = vexp; }

    struct StackHolder
    {
        this(string name, ptrdiff_t idx=-1)
        { fNameStack.push(FieldName(name, idx)); }
        ~this() { fNameStack.pop(); }
    }

    ubyte pop(ref WrapRng rng, string field, size_t idx, string type, size_t vcnt, size_t vexp)
    {
        const _ = StackHolder(field, idx);
        setRngFields(rng, type, vcnt, vexp);
        auto ret = rng.front();
        rng.popFront();
        return ret;
    }

    void impl(T)(ref WrapRng r, ref T trg, string field, ptrdiff_t idx=-1)
    {
        const __ = StackHolder(field, idx);

        static if (hasRepr!(RH, T))
        {
            serializeRepr!(RH, T) repr;
            impl(r, repr, "repr");
            trg = RH.fromRepr(repr);
        }
        else static if (is(T == enum))
        {
            immutable EM = [EnumMembers!T];
            alias ENT = EnumNumType!T;
            ubyte[ENT.sizeof] tmp;
            foreach (i, ref v; tmp)
                v = pop(r, "byte", i, T.stringof, i, ENT.sizeof);
            trg = EM[tmp.unpack!ENT];
        }
        else static if (is(T == vluint))
        {
            setRngFields(r, "vluint", 0, 10);
            trg = vluint(readVLUInt(r));
        }
        else static if (is(T == vlint))
        {
            setRngFields(r, "vlint", 0, 10);
            trg = vlint(zzDecode(readVLUInt(r)));
        }
        else static if (is(T : double) || is(T : long))
        {
            ubyte[T.sizeof] tmp;
            foreach (i, ref v; tmp)
                v = pop(r, "byte", i, T.stringof, i, T.sizeof);
            trg = tmp.unpack!T;
        }
        else static if (isVoidArray!T)
        {
            static if (isDynamicArray!T)
            {
                auto _ = StackHolder("length");
                setRngFields(r, "vluint", 0, 10);
                const l = cast(size_t)readVLUInt(r);
                if (trg.length != l) trg.length = l;
            }

            auto tmp = (() @trusted => cast(ubyte[])trg[])();
            foreach (i, ref v; tmp) impl(r, v, "elem", i);
        }
        else static if (isStaticArray!T)
        {
            foreach (i, ref v; trg) impl(r, v, "elem", i);
        }
        else static if (isSomeString!T)
        {
            const len = (() {
                auto _ = StackHolder("length");
                setRngFields(r, "vluint", 0, 10);
                return cast(size_t)readVLUInt(r);
            })();
            auto tmp = new ubyte[](len);
            foreach (i, ref v; tmp)
                v = pop(r, "elem", i, T.stringof, i, len);
            trg = (() @trusted => cast(T)tmp)();
        }
        else static if (isDynamicArray!T)
        {
            const len = (()
            {
                auto _ = StackHolder("length");
                setRngFields(r, "vluint", 0, 10);
                return cast(size_t)readVLUInt(r);
            })();
            if (trg.length != len) trg.length = len;
            foreach (i, ref v; trg) impl(r, v, "elem", i);
        }
        else static if (isAssociativeArray!T)
        {
            const len = ((){
                auto _ = StackHolder("length");
                setRngFields(r, "vluint", 0, 10);
                return cast(size_t)readVLUInt(r);
            })();

            (() @trusted => trg.clear())();

            foreach (i; 0 .. len)
            {
                KeyType!T k;
                ValueType!T v;
                impl(r, k, "key", i);
                impl(r, v, "value", i);
                trg[k] = v;
            }

            (() @trusted => trg.rehash())();
        }
        else static if (isTagged!(T).any)
        {
            import std.algorithm.mutation : move;

            TaggedTagType!T tag;
            impl(r, tag, "tag");

            FS: final switch (tag)
            {
                static foreach (t; getTaggedAllTags!T)
                {
                    case t:
                        TaggedTypeByTag!(T, t) tmp;

                        // do not try deserialize null for nullable type
                        static if (!is(typeof(tmp) == typeof(null)))
                            impl(r, tmp, "value");

                        static if (__traits(compiles, trg = tmp)) trg = tmp;
                        else
                        {
                            static if (isTagged!(T).isSumType)
                                trg = T(move(tmp));
                            else
                                trg.set!t(move(tmp));
                        }

                        break FS;
                }
            }
        }
        else static if (hasCustomRepr!(T, RH))
        {
            ReturnType!(trg.sbinCustomRepr) tmp;
            impl(r, tmp, "customRepr");
            // for @safe sbinDeserialize sbinFromCustomRepr must be @trusted or @safe
            trg = T.sbinFromCustomRepr(tmp);
        }
        else static if (is(T == struct))
        {
            version (allowRawUnions)
            {
                import std : Nullable;
                static if (is(T == Nullable!A, A))
                    pragma(msg, file, "(", cast(int)line, "): ", "\033[33mWarning:\033[0m ",
                        T, " deserialize as union, use NullableAsSumTypeRH for proper deserialize!");
            }

            import std.traits : hasUDA;
            foreach (i, ref v; trg.tupleof)
                static if (!hasUDA!(T.tupleof[i], sbinSkip))
                    impl(r, v, __traits(identifier, trg.tupleof[i]));
        }
        else static if (is(T == union))
        {
            version (allowRawUnions)
            {
                auto tmp = (() @trusted => cast(ubyte[])((cast(void*)&trg)[0..T.sizeof]))();
                foreach (i, ref v; tmp)
                    v = pop(r, "byte", i, T.stringof, i, T.sizeof);
            }
            else
                static assert(0, "raw unions are not allowed, for allow build "~
                                    "with configuration 'allow-raw-unions'");
        }
        else static assert(0, "unsupported type: " ~ T.stringof);
    }

    size_t cnt;

    auto wr = (() @trusted => WrapRng(&range, &cnt, &fNameStack))();

    static if (Target.length == 1)
        impl(wr, target[0], "root");
    else foreach (i, ref v; target)
        impl(wr, v, "root", i);
}

/++ Deserialize part of input range to `Target` value

    Params:
        range = input range with serialized data (not saved before work)

    Returns:
        deserialized value
 +/
Target sbinDeserializePart(RH=EmptyReprHandler, Target, R, string file=__FILE__, size_t line=__LINE__)
    (scope ref R range) if (isReprHandler!RH)
{
    Unqual!Target ret;
    sbinDeserializePart!(RH, R, file, line, Target)(range, ret);
    return ret;
}

/// ditto
Target sbinDeserializePart(Target, R, string file=__FILE__, size_t line=__LINE__)(scope ref R range)
{
    Unqual!Target ret;
    sbinDeserializePart!(EmptyReprHandler, R, file, line, Target)(range, ret);
    return ret;
}

/++ Deserialize `Target` value

    Params:
        range = input range with serialized data (not saved before work)

    Returns:
        deserialized value
 +/
Target sbinDeserialize(RH=EmptyReprHandler, Target, R, string file=__FILE__, size_t line=__LINE__)
    (scope R range) if (isReprHandler!RH)
{
    Unqual!Target ret;
    sbinDeserialize!(RH)(range, ret);
    return ret;
}

/// ditto
Target sbinDeserialize(Target, R, string file=__FILE__, size_t line=__LINE__)(scope R range)
{
    Unqual!Target ret;
    sbinDeserialize!(EmptyReprHandler, R, file, line)(range, ret);
    return ret;
}

/++ Deserialize `Target` value

    Params:
        range = input range with serialized data (not saved before work)
        target = reference to result object

    Throws:
        SBinDeserializeException if range isn't empty after deseriazlie
 +/
void sbinDeserialize(RH=EmptyReprHandler, R, string file=__FILE__, size_t line=__LINE__, Target...)
    (scope R range, ref Target target) if (isReprHandler!RH)
{
    sbinDeserializePart!(RH, R, file, line)(range, target);

    enforce(range.empty, new SBinDeserializeException(
        format("input range not empty after full '%s' deserialize", Target.stringof)));
}
