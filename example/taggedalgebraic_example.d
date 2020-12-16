/+ dub.sdl:
    dependency "taggedalgebraic" version="~>0.11.18"
    dependency "sbin" path=".."
+/

import taggedalgebraic;
import sbin;

struct Foo { string name; }

union Base
{
    int count;
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
    auto sdbar_data = bar.sbinSerialize;
    assert (sdbar_data.length == int.sizeof + 1 /+ length packed to 1 byte +/ +
        byte.sizeof + int.sizeof + // count 
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 5 + // str
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 3 // Foo
    );
    auto sdbar = sdbar_data.sbinDeserialize!Bar;

    assert (sdbar.someInt == 4);
    assert (sdbar.data.length == 3);
    assert (sdbar.data[0].isCount);
    assert (sdbar.data[0].kind == TUnion.Kind.count);
    assert (sdbar.data[0].value!(TUnion.Kind.count) == 42);

    // deserialize to new memory
    assert (bar.data[1].value!(TUnion.Kind.str).ptr !=
          sdbar.data[1].value!(TUnion.Kind.str).ptr);

    assert (sdbar.data[1].isStr);
    assert (sdbar.data[1].kind == TUnion.Kind.str);
    assert (sdbar.data[1].value!(TUnion.Kind.str) == "Hello");

    assert (sdbar.data[2].isFoo);
    assert (sdbar.data[2].kind == TUnion.Kind.foo);
    assert (sdbar.data[2].value!(TUnion.Kind.foo) == Foo("ABC"));
    assert (sdbar.data[2].value!(TUnion.Kind.foo).name.ptr !=
              bar.data[2].value!(TUnion.Kind.foo).name.ptr);
}

alias TAlg = TaggedAlgebraic!Base;

struct Bar2 { TAlg[] data; }

void bar2Test()
{
    TAlg t_count = 42;
    TAlg t_str = "Hello";
    TAlg t_foo = Foo("ABC");
    auto bar = Bar2([t_count, t_str, t_foo]);
    auto sdbar_data = bar.sbinSerialize;
    assert (sdbar_data.length == 1 /+ length packed to 1 byte +/ +
        byte.sizeof + int.sizeof + // count 
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 5 + // str
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 3 // Foo
    );
    auto sdbar = sdbar_data.sbinDeserialize!Bar2;

    assert (sdbar.data.length == 3);
    assert (sdbar.data[0].kind == TAlg.Kind.count);
    assert (sdbar.data[0] == 42);

    // deserialize to new memory
    assert (bar.data[1].ptr != sdbar.data[1].ptr);

    assert (sdbar.data[1].kind == TAlg.Kind.str);
    assert (sdbar.data[1] == "Hello");

    assert (sdbar.data[2].kind == TAlg.Kind.foo);
    assert (sdbar.data[2] == Foo("ABC"));
    assert (sdbar.data[2].name.ptr != bar.data[2].name.ptr);
}

void main()
{
    barTest();
    bar2Test();
}