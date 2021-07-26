/+ dub.sdl:
    dependency "mir-core" version="~>1.1.54"
    dependency "sbin" path=".."
+/

import mir.algebraic;
import sbin;

struct Foo { string name; }

alias TUnion = Algebraic!(
    TaggedType!(typeof(null), "nil"),
    TaggedType!(int, "count"),
    TaggedType!(string, "str"),
    TaggedType!(Foo, "foo"),
);

static assert (isTagged!(TUnion).any);
static assert (isTagged!(TUnion).isMirAlgebraic);

struct Bar
{
    int someInt;
    TUnion[] data;
}

void barTest()
{
    auto bar = Bar(77, [TUnion(42), TUnion("Hello"), TUnion(Foo("ABC")), TUnion(null)]);
    auto sdbar_data = bar.sbinSerialize;
    assert (sdbar_data.length == int.sizeof + 1 /+ length packed to 1 byte +/ +
        byte.sizeof + int.sizeof + // count 
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 5 + // str
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 3 + // Foo
        byte.sizeof /+ length packed to 1 byte +/ // null
    );
    assert (sdbar_data == [77, 0, 0, 0, 4, 1, 42, 0, 0, 0, 2, 5, 72,
                           101, 108, 108, 111, 3, 3, 65, 66, 67, 0]);
    auto sdbar = sdbar_data.sbinDeserialize!Bar;

    assert (sdbar.someInt == 77);
    assert (sdbar.data.length == 4);
    assert (sdbar.data[0].kind == TUnion.Kind.count);
    assert (sdbar.data[0].get!int == 42);
    //assert (sdbar.data[0].count == 42);

    // deserialize to new memory
    assert (bar.data[1].get!string.ptr !=
          sdbar.data[1].get!string.ptr);

    assert (sdbar.data[1].kind == TUnion.Kind.str);
    assert (sdbar.data[1].get!string == "Hello");
    //assert (sdbar.data[1].str == "Hello");

    assert (sdbar.data[2].kind == TUnion.Kind.foo);
    assert (sdbar.data[2].get!Foo == Foo("ABC"));
    //assert (sdbar.data[2].foo == Foo("ABC"));
    assert (sdbar.data[2].get!Foo.name.ptr !=
              bar.data[2].get!Foo.name.ptr);

    assert (sdbar.data[3].isNull);
}

void main()
{
    barTest();
}
