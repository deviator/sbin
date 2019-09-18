module sbin.exception;

import std.format : format;

package import std.exception : enforce, assertThrown;

///
class SBinException : Exception
{
    ///
    @safe @nogc pure nothrow
    this(string msg, string file=__FILE__, size_t line=__LINE__)
    { super(msg, file, line); }
}

///
class SBinDeserializeException : SBinException
{
    ///
    @safe @nogc pure nothrow
    this(string msg, string file=__FILE__, size_t line=__LINE__)
    { super(msg, file, line); }
}

///
class SBinDeserializeEmptyRangeException : SBinDeserializeException
{
    ///
    string mainType, fieldName, fieldType;
    ///
    size_t readed, expected, fullReaded;
    ///
    this(string mainType, string fieldName, string fieldType,
         size_t readed, size_t expected, size_t fullReaded,
         string file=__FILE__, size_t line=__LINE__) @safe pure
    {
        this.mainType = mainType;
        this.fieldName = fieldName;
        this.fieldType = fieldType;
        this.readed = readed;
        this.expected = expected;
        this.fullReaded = fullReaded;
        super(format!("empty input range while "~
                "deserialize '%s' element %s:%s %d/%d (readed/expected), "~
                "readed message %d bytes")(mainType, fieldName,
                fieldType, readed, expected, fullReaded), file, line);
    }
}