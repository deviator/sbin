import taggedalgebraic;
import sbin;

struct Foo {
    string name;
    void bar() {}
}

union Base {
    int count;
    int offset;
    string str;
    Foo foo;
}

alias TUnion = TaggedUnion!Base;

struct Bar
{
    int someInt;
    TUnion[] data;
}

void barTest()
{
    auto bar = Bar(4, [TUnion.count(42), TUnion.str("Hello"), TUnion.foo(Foo("ABC"))]);
    auto sdbar = bar.sbinSerialize.sbinDeserialize!Bar;

    assert (sdbar.data.length == 3);
    assert (sdbar.data[0].isCount);
    assert (sdbar.data[0].kind == TUnion.Kind.count);
    assert (sdbar.data[0].value!(TUnion.Kind.count) == 42);

    // be careful
    assert (bar.data[1].value!(TUnion.Kind.str).ptr ==
          sdbar.data[1].value!(TUnion.Kind.str).ptr);

    assert (sdbar.data[1].isStr);
    assert (sdbar.data[1].kind == TUnion.Kind.str);
    assert (sdbar.data[1].value!(TUnion.Kind.str) == "Hello");

    assert (sdbar.data[2].isFoo);
    assert (sdbar.data[2].kind == TUnion.Kind.foo);
    assert (sdbar.data[2].value!(TUnion.Kind.foo) == Foo("ABC"));
}

struct SBinTaggedUnionWrap(TU)
{
    import std.traits : EnumMembers;
    import std.algorithm.mutation : move;

    TU __tu;
    alias __tu this;

    void sbinCustomSerialize(R)(ref R r) const
    {
        sbinSerialize(r, __tu.kind);
        F: final switch (__tu.kind)
        {
            static foreach (k; EnumMembers!(TU.Kind))
            {
                case k:
                    sbinSerialize(r, __tu.value!k);
                    break F;
            }
        }
    }

    static void sbinCustomDeserialize(R)(ref R r, ref typeof(this) foo)
    {
        TU.Kind kind;
        sbinDeserializePart(r, kind);
        F: final switch (kind)
        {
            static foreach (k; EnumMembers!(TU.Kind))
            {
                case k:
                    TypeOf!k tmp;
                    sbinDeserializePart(r, tmp);
                    foo.__tu.set!k(move(tmp));
                    break F;
            }
        }
    }
}

alias TU2 = SBinTaggedUnionWrap!TUnion;

void tu2Test()
{
    {
        auto tu2 = TU2(TUnion.count(42));
        auto stu2 = tu2.sbinSerialize.sbinDeserialize!TU2;
        assert (stu2.kind == TUnion.Kind.count);
        assert (stu2.value!(TUnion.Kind.count) == 42);
    }
    {
        auto tu2 = TU2(TUnion.str("hello"));
        auto stu2 = tu2.sbinSerialize.sbinDeserialize!TU2;
        assert (stu2.kind == TUnion.Kind.str);
        assert (stu2.value!(TUnion.Kind.str) == "hello");
    }
    {
        auto tu2 = TU2(TUnion.offset(2));
        auto stu2 = tu2.sbinSerialize.sbinDeserialize!TU2;
        assert (stu2.kind != TUnion.Kind.count);
        assert (stu2.kind == TUnion.Kind.offset);
        assert (stu2.value!(TUnion.Kind.offset) == 2);
    }
}

struct Bar2
{
    int someInt;
    TU2[] data;
}

void bar2Test()
{
    auto bar = Bar2(4, [TU2(TUnion.count(42)), TU2(TUnion.str("Hello")), TU2(TUnion.foo(Foo("ABC")))]);
    auto sdbar = bar.sbinSerialize.sbinDeserialize!Bar2;

    assert (sdbar.data.length == 3);
    assert (sdbar.data[0].isCount);
    assert (sdbar.data[0].kind == TUnion.Kind.count);
    assert (sdbar.data[0].value!(TUnion.Kind.count) == 42);

    // be careful
    assert (bar.data[1].value!(TUnion.Kind.str).ptr !=
          sdbar.data[1].value!(TUnion.Kind.str).ptr);

    assert (sdbar.data[1].isStr);
    assert (sdbar.data[1].kind == TUnion.Kind.str);
    assert (sdbar.data[1].value!(TUnion.Kind.str) == "Hello");

    assert (sdbar.data[2].isFoo);
    assert (sdbar.data[2].kind == TUnion.Kind.foo);
    assert (sdbar.data[2].value!(TUnion.Kind.foo) == Foo("ABC"));
}

void main()
{
    tu2Test();
    barTest();
    bar2Test();
}