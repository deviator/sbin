# Simple binary [de]serialize

[![GitHub Workflow Status](https://img.shields.io/github/workflow/status/deviator/sbin/base)](https://github.com/deviator/sbin/actions)
[![codecov](https://codecov.io/gh/deviator/sbin/branch/master/graph/badge.svg)](https://codecov.io/gh/deviator/sbin)
[![Dub](https://img.shields.io/dub/v/sbin.svg)](http://code.dlang.org/packages/sbin)
[![License](https://img.shields.io/dub/l/sbin.svg)](http://code.dlang.org/packages/sbin)

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

* dynamic arrays (associative arrays too) and algebraic types (serialized only
current value, not full storage) has variable length, all other types has fixed size

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
    @sbinSkip int local = 42;
}

const foo1 = Foo(10, 3.14, 2.17, 8, "s1", Color.red);

//                 a              b            c       d
const foo1Size = ulong.sizeof + float.sizeof * 2 + ushort.sizeof +
//         str                      color
        (1 + foo1.str.length) + ubyte.sizeof;
// length of dynamic arrays packed to variable length uint

// color is ubyte because [EnumMembers!Color].length < ubyte.max

const foo1Data = foo1.sbinSerialize; // used inner appender

assert(foo1Data.length == foo1Size);

// deserialization return instance of Foo
assert(foo1Data.sbinDeserialize!Foo == foo1);

const foo2 = Foo(2, 2.22, 2.22, 2, "str2", Color.green);

const foo2Size = ulong.sizeof + float.sizeof * 2 + ushort.sizeof +
                    (1 + foo2.str.length) + ubyte.sizeof;

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
//                           foos
                (ubyte.sizeof + foo1Size + foo2Size);

assert(bar.sbinSerialize.length == barSize);
```

### Stable binary format across minor releases

If you use sbin to serialize data to and from file, you will be interested
to maintain stability in the binary serialization format, so that files saved
with older versions of your softare can be opened in newer versions. Sbin has
been using the same format since release 0.5.0, and will continue doing so at
least until the major version number is bumped. It is therefore safe to allow
dub to do minor version upgrades with a version specification like `~>0.8`,
equivalent to ">=0.8.0 <1.0.0".

If, in the future, changes to the format are made, then sbin will provide a 
variant of `sbinDeserialize` that supports the older format(s). This will be
mentioned in the release notes.

However, it will be up to the application programmer (you) to call the correct
variant of `sbinDeserialize`. You are therefore advised to **save your files
with a file header** from which you will always be able to derive the format
version with which the succeeding bytes should be deserialized.

(Of course the major version number *may* be bumped without changing the format.)

### Skipping fields

If a field in a struct has the `@sbinSkip` attribute, the field will
not be serialized. Upon deserialization the field will have the value of
the static initializer if there is one, or `.init` otherwise.

### Variable length integers

You can use `vlint` and `vluint`. They are `long` and `ulong` under the
hood. Minimal count of bytes that they need is 1: for `vlint` it will be
for values `[-63, 64]`, for `vluint` for `[0, 127]`. Maximum count of
bytes is 10 for values near the limit of `long` and `ulong`.

### Custom [de]serialization algorithm

Add to your type `Foo`:

* `T sbinCustomRepr() @property const` where `T` is serializable representation
  of `Foo`, what can be used for full restore data
* `static Foo sbinFromCustomRepr()(auto ref const T repr)` what returns is new
  instance for your deserialization type

### Tagged algebraics

See
* [`taggedalgebraic` example](example/taggedalgebraic_example.d)
* [`mir.algebraic` example](example/mir_algebraic_example.d)
* [`sumtype` example](example/sumtype_example.d)

Phobos 2.097 include `std.sumtype`, it supports too. 

### Types that can't be changed

For example `std.bitmanip.BitArray` has pointer, `std.datetime.SysTime` has 
class field `TimeZone`. They can't be serialized automaticaly.
For solving this problem you can use representation handlers.

Representation handler is simple struct with `sbinReprHandler` enum field and
static methods, two methods for one wrapped type: `repr` for get
representation, `fromRepr` for get original type.

Example:
```d
struct RH
{
    // need for detecting representation handlers
    enum sbinReprHandler;

static:

    // representation must can be [de]serialized
    static struct BAW { vluint bc; void[] data; }

    // this method must get const original value
    BAW repr(const BitArray ba) { return BAW(vluint(ba.length), cast(void[])ba.dup); }
    BitArray fromRepr(BAW w) { return BitArray(w.data.dup, w.bc); }

    long repr(const SysTime t) { return t.toUTC.stdTime; }
    SysTime fromRepr(long r) { return SysTime(r, UTC()); }
}

struct Foo
{
    string name;
    BitArray bits;
    SysTime tm;
}

auto foo = Foo("bar", BitArray([1,0,1]), Clock.currTime);

const foo_bytes = sbinSerialize!RH(foo);

auto foo2 = sbinDeserialize!(RH, Foo)(foo_bytes);

assert (foo == foo2);
```

## Limitations

### Unions

Unions serializes/deserializes as static byte array without analyze elements
(size of union is size of max element).

**If you want use arrays or strings in unions you must implement custom [de]serialize methods or use tagged algebraic**

### std.variant

Not supported. See [Tagged algebraics](#tagged-algebraics) if you need variablic types.

### Pointers

Can't automatic [de]serialize pointers data. For arrays use builtin arrays.
For struct and class types see custom serialization.

### Code versions

If you want use sbin for message passing between applications you
must use strictly identical types (one source code), because struct fields
are not marked (deserialization relies solely on information from type)
and any change in code (swap fields, change fields type, change enum values
list) must be accompanied by recompilation of all applications.

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

    ulong sbinCustomRepr() const @property
    {
        return id;
    }

    // must be static
    static Foo sbinFromCustomRepr(ulong v)
    {
        return new Foo(v);
    }
}
```
