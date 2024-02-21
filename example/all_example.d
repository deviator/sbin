/+ dub.sdl:
    dependency "mir-core" version="~>1.1"
    dependency "sumtype" version="~>1.1"
    dependency "taggedalgebraic" version="~>0.11"
    dependency "sbin" path=".."
+/

import mir.algebraic;
import sumtype;
import taggedalgebraic;

import sbin;

struct Foo { string name; }

static union U
{
    typeof(null) nil;
    int count;
    string str;
    Foo foo;
}
alias MA = Algebraic!U;

static assert (isTagged!(MA).any);
static assert (isTagged!(MA).isMirAlgebraic);

union TABase
{
    int count;
    string str;
    Foo foo;
}

alias TA = TaggedUnion!TABase;

static assert (isTagged!(TA).any);
static assert (isTagged!(TA).isTaggedAlgebraic);

alias ST = SumType!( typeof(null), int, string, Foo );

static assert (isTagged!(ST).any);
static assert (isTagged!(ST).isSumType);

struct Bar
{
    int someInt;
    MA[] madata;
    TA[] tadata;
    ST[] stdata;
}

void barTest()
{
    auto bar = Bar(123,
        [MA(42), MA("one"), MA(Foo("A")), MA(null)],
        [TA(43), TA("two"), TA(Foo("B"))],
        [ST(44), ST("tre"), ST(Foo("C")), ST(null)],
    );

    auto sdbar_data = bar.sbinSerialize;
    assert (sdbar_data.length == int.sizeof +

        1 /+ length packed to 1 byte +/ +
        byte.sizeof + int.sizeof + // count 
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 3 + // str
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 1 + // Foo
        byte.sizeof + /+ length packed to 1 byte +/ // null

        1 /+ length packed to 1 byte +/ +
        byte.sizeof + int.sizeof + // count 
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 3 + // str
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 1 + // Foo

        1 /+ length packed to 1 byte +/ +
        byte.sizeof + int.sizeof + // count 
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 3 + // str
        byte.sizeof + 1 /+ length packed to 1 byte +/ + 1 + // Foo
        byte.sizeof /+ length packed to 1 byte +/ // null
    );
    assert (sdbar_data == [123, 0, 0, 0, 4, 1, 42, 0, 0, 0, 2, 3, 111, 110, 101, 3, 1, 65,
                           0, 3, 0, 43, 0, 0, 0, 1, 3, 116, 119, 111, 2, 1, 66, 4, 1, 44,
                           0, 0, 0, 2, 3, 116, 114, 101, 3, 1, 67, 0]);

    auto sdbar = sdbar_data.sbinDeserialize!Bar;

    assert (sdbar.someInt == 123);
    assert (sdbar.madata.length == 4);
    assert (sdbar.madata[0].kind == MA.Kind.count);
    assert (sdbar.madata[0].get!int == 42);

    // deserialize to new memory
    assert (bar.madata[1].get!string.ptr !=
          sdbar.madata[1].get!string.ptr);

    assert (sdbar.madata[1].kind == MA.Kind.str);
    assert (sdbar.madata[1].get!string == "one");
    assert (sdbar.tadata[1].value!(TA.Kind.str) == "two");

    assert (sdbar.madata[2].kind == MA.Kind.foo);
    assert (sdbar.madata[2].get!Foo == Foo("A"));
    assert (sdbar.madata[2].get!Foo.name.ptr !=
              bar.madata[2].get!Foo.name.ptr);
    assert (sdbar.tadata[2].value!(TA.Kind.foo) == Foo("B"));
    assert (sumtype.match!((Foo v) => v, _ => Foo.init)(sdbar.stdata[2]) == Foo("C"));

    assert (sdbar.madata[3].isNull);
    assert (sumtype.match!((typeof(null) _) => true, _ => false)(sdbar.stdata[3]));
}

void main()
{
    barTest();
}
