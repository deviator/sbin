/+ dub.sdl:
    dependency "sumtype" version="~>1.1.0"
    dependency "sbin" path=".."
+/

import sumtype;
import sbin;

struct Foo { string name; }

alias TUnion = SumType!( typeof(null), int, string, Foo );

static assert (isTagged!(TUnion).any);
static assert (isTagged!(TUnion).isSumType);

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
    assert (sdbar_data == [77, 0, 0, 0, 4, 1, 42, 0, 0, 0, 2, 5, 72, 101, 108, 108, 111, 3, 3, 65, 66, 67, 0]);
    auto sdbar = sdbar_data.sbinDeserialize!Bar;

    assert (sdbar.someInt == 77);
    assert (sdbar.data.length == 4);
    assert (sdbar.data[0].typeIndex == 1);
    assert (sdbar.data[0].match!((int v) => v, _ => 0 ) == 42);

    // deserialize to new memory
    assert (bar.data[1].match!((string v) => v.ptr, _ => null) !=
          sdbar.data[1].match!((string v) => v.ptr, _ => null));

    assert (sdbar.data[1].typeIndex == 2);
    assert (sdbar.data[1].match!((string v) => v, _ => "") == "Hello");

    assert (sdbar.data[2].typeIndex == 3);
    assert (sdbar.data[2].match!((Foo v) => v, _ => Foo.init) == Foo("ABC"));

    assert (bar.data[2].match!((Foo v) => v.name.ptr, _ => null) !=
          sdbar.data[2].match!((Foo v) => v.name.ptr, _ => null));

    assert (sdbar.data[3].typeIndex == 0);
}

void main()
{
    barTest();
}
