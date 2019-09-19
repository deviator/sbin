module sbin.util.stack;

struct Stack(T, size_t N=0)
{
    //private
    public
    {
    ptrdiff_t topI = 0;

    static if (N) T[N] sdata;
    T[] data;
    }

    private void pushDynamic(T val)
    {
        if (cast(ptrdiff_t)data.length < topI-N) data ~= val;
        else top = val;
    }

    void push(T val)
    {
        topI++;
        static if (N)
        {
            if (topI <= cast(ptrdiff_t)N) top = val;
            else pushDynamic(val);
        }
        else pushDynamic(val);
    }

    const(T[]) getData() const
    {
        static if (N)
        {
            if (topI <= cast(ptrdiff_t)N) return sdata[0..topI];
            else return (sdata[] ~ data)[0..topI-N];
        }
        else return data[0..topI];
    }

    void reserve(ptrdiff_t k)
    {
        k -= N;
        if ((cast(ptrdiff_t)data.length) < k) data.length = k;
    }

    ref inout(T) top() inout @property
    {
        static if (N)
            return (topI <= (cast(ptrdiff_t)N)) ? sdata[topI-1] : data[topI-N-1];
        else
            return data[topI-1];
    }
    T pop()
    {
        if (empty) assert(0, "stack empty");
        T ret = top;
        topI--;
        return ret;
    }
    bool empty() const @property { return topI == 0; }
    void clear() { data.length = 0; topI = 0; }
}

version (unittest) void testStack(size_t N)()
{
    Stack!(int, N) s;
    assert (s.empty);
    s.reserve(5);
    assert (s.empty);
    s.push(1);
    assert (!s.empty);
    s.push(2);
    assert (!s.empty);
    assert (s.top == 2);
    s.pop();
    assert (s.top == 1);
    s.pop();
    assert (s.empty);

    import std.exception : assertThrown;
    import core.exception : RangeError, AssertError;

    assertThrown!RangeError(s.top);
    assertThrown!AssertError(s.pop());

    foreach (i; 1..10) s.push(i*10);
    foreach_reverse (i; 1..10) assert (s.pop() == i*10);

    foreach (i; 1..100) s.push(i*3);
    assert(s.pop() == 99*3);
    foreach (i; 1..10) s.push(i*2);
    foreach_reverse (i; 1..10) assert (s.pop() == i*2);
    foreach_reverse (i; 1..99) assert (s.pop() == i*3);

    assert (s.empty);
    s.push(100);
    assert (!s.empty);
    s.clear();
    assert (s.empty);
}

unittest
{
    testStack!0;
    testStack!1;
    testStack!5;
    testStack!8;
    testStack!9;
    testStack!10;
    testStack!11;
    testStack!12;
    testStack!99;
    testStack!100;
    testStack!101;
}