# Simple binary [de]serialize

[![Build Status](https://travis-ci.org/deviator/sbin.svg?branch=master)](https://travis-ci.org/deviator/sbin)
[![codecov](https://codecov.io/gh/deviator/sbin/branch/master/graph/badge.svg)](https://codecov.io/gh/deviator/sbin)

## Usage

Library provides functions for simple serialize and deserialize data:

You can serialize/deserialize numbers, arrays, enums, structs and combinations of those.

### Functions

#### `void sbinSerialize(R, Ts...)(ref R r, auto ref const Ts vals) if (isOutputRange!(R, ubyte) && Ts.length)`

Call `put(r, <data>)` for all fields in vals recursively.

Do not allocate memory if you use range with `@nogc` `put`.

#### `ubyte[] sbinSerialize(T)(auto ref const T val)`

Uses inner `appender!(ubyte[])`.

#### `void sbinDeserialize(R, Target...)(R range, ref Target target) if (isInputRange!R && is(Unqual!(ElementType!R) == ubyte))`

Fills `target` from `range` bytes

Can throw:

* `SBinDeserializeEmptyRangeException` then try read empty range
* `SBinDeserializeException` then after deserialize input range is not empty

Exception messages builds with gc (`~` is used for concatenate).

Allocate memory if deserialize:

* strings
* associative arrays
* dynamic array if target length is not equal length from input bytes

#### `Target sbinDeserialize(Target, R)(R range)`

Creates `Unqual!Target ret`, fill it and return.

### Key points

* all struct fields are serialized and deserialized by default
* only dynamic arrays has variable length, all other types has fixed size

### Example

```d
// All enums serialize as numbers
enum Color
{
    black = "#000000",
    red = "#ff0000",
    green = "#00ff00",
    blue = "#0000ff",
    white = "#ffffff"
}

struct Foo
{
    ulong a;
    float b, c;
    ushort d;
    string str;
    Color color;
}

const foo1 = Foo(10, 3.14, 2.17, 8, "s1", Color.red);

//                 a              b            c       d
const foo1Size = ulong.sizeof + float.sizeof * 2 + ushort.sizeof +
//                      str                      color
        (length_t.sizeof + foo1.str.length) + ubyte.sizeof;

// color is ubyte because [EnumMembers!Color].length < ubyte.max

const foo1Data = foo1.sbinSerialize; // used inner appender

assert(foo1Data.length == foo1Size);

// deserialization return instance of Foo
assert(foo1Data.sbinDeserialize!Foo == foo1);

const foo2 = Foo(2, 2.22, 2.22, 2, "str2", Color.green);

const foo2Size = ulong.sizeof + float.sizeof * 2 + ushort.sizeof +
        (length_t.sizeof + foo2.str.length) + ubyte.sizeof;

enum Level { low, medium, high }

struct Bar
{
    ulong a;
    float b;
    Level level;
    Foo[] foos;
}

auto bar = Bar(123, 3.14, Level.high, [ foo1, foo2 ]);

//                   a               b          level
const barSize = ulong.sizeof + float.sizeof + ubyte.sizeof +
//                                 foos
                (length_t.sizeof + foo1Size + foo2Size);

assert(bar.sbinSerialize.length == barSize);
```

### Custom [de]serialization algorithm

Add to your type:

* `void sbinCustomSerialize(R)(ref R r) const` where `R` is output range
* `static void sbinCustomDeserialize(R)(ref R r, ref Foo foo)` where `R`
  is input range, `Foo foo` is new instance for deserialization

## Limitations

### Max dynamic array length

By default uses `uint` as `length_t`, for using `ulong` use library cofiguration `ulong_length`.

### Code versions

If you want use sbin for message passing between applications you
must use strictly identical types (one source code), because struct fields are not marked 
(deserialization relies solely on information from type) and any change in code
(swap fields, change fields type, change enum values list) must be accompanied by
recompilation of all applications.

### Immutable and const

Deserialize works after initialization of object and const or immutable
fields are can't be setted.

### Inderect fields

If struct have two arrays

```d
struct Foo
{
    ubyte[] a, b;
}
```

and these arrays point to one memory

```d
auto arr = cast(ubyte[])[1,2,3,4,5,6];
auto foo = Foo(arr, arr[0,2]);
assert (foo.a.ptr == foo.b.ptr);
```

then they will be serialized separated and after deserialize will be
point to different memory parts

```d
auto foo2 = foo.sbinSerialize.sbinDeserialize!Foo;
assert (foo2.a.ptr != foo.b.ptr);
```

### Classes

Classes must have custom serialize methods, otherwise they can't be serialized.

```d
class Foo
{
    ulong id;
    this(ulong v) { id = v; }

    void sbinCustomSerialize(R)(ref R r) const
    {
        r.put(cast(ubyte)id);
    }

    // must be static
    static void sbinCustomDeserialize(R)(ref R r, ref Foo foo)
    {
        // must create new class instance
        foo = new Foo(r.front());
        // must pop range as default deserialize algorithm
        r.popFront();
    }
}
```