// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Summary: Load a UI from a JSON text format
*/

module glui.widget.loader;

import
    std.stdio,
    std.conv,
    std.variant,
    std.json;

import
    glui.widget.base,
    glui.widget.text,
    glui.widget.tree;



void parseUI(WidgetRoot root, string text)
{
    foreach(name, member; parseJSON(text).object)
        parseObject(root, null, name, member.object);
}


Widget[] parseObject(WidgetRoot root, Widget parent, string name, JSONValue[string] obj)
{
    writeln(name);
    Widget newObj;
    Widget[] allObjs;
    Args args;

    if ("settings" in obj)
    {
        assert(obj["settings"].type == JSON_TYPE.OBJECT);
        args = toArgs(obj["settings"].object);
    }

    /** CTFE **/ string makeCase(string[] types)
    {
        string s = "final switch(name)\n{\n";
        foreach(t; types)
            s ~= "case `" ~ t ~ "`: newObj = root.create!" ~ t ~ "(parent, args); break;\n";
        return s ~ "\n}\n";
    }

    mixin(makeCase(["WidgetWindow",
                    "WidgetText",
                    "WidgetMenu"]));

    foreach(key, val; obj)
        if (key != "settings" && val.type == JSON_TYPE.OBJECT)
                allObjs ~= parseObject(root, newObj, key, val.object);

    allObjs ~= newObj;
    return allObjs;
}

Args toArgs(JSONValue[string] obj)
{
    Args args;
    foreach(k, v; obj)
    {
        args.keys ~= k;
        args.vals ~= getVal(v);
    }
    return args;
}

/**
* Return a variant containing the inner type of the JSONValue.
*/
Variant getVal(JSONValue val)
{
    final switch (val.type) with(JSON_TYPE)
    {
        case OBJECT:    assert(false);
        case STRING:    return Variant(val.str); break;
        case INTEGER:   return Variant(val.integer.to!int); break;
        case UINTEGER:  return Variant(val.uinteger.to!uint); break;
        case FLOAT:     return Variant(val.floating); break;
        case TRUE:      return Variant(true); break;
        case FALSE:     return Variant(false); break;
        case NULL:      return Variant(null); break;
        case ARRAY:     return getArr(val.array); break;
    }
}

/**
* Make an array of the inner type of the JSONValue[], assuming the
* type is the same for all elements.
*/
Variant getArr(JSONValue[] arr)
{
    /** CTFE **/ string makeCase(string name, string type, string getType)
    {
        string s = "case " ~ name ~ ":";
        s ~= type ~ "[] outArr; outArr.length = arr.length;";
        s ~= "foreach(i, e; arr) outArr[i] = e." ~ getType ~ ";";
        s ~= "return Variant(outArr);";
        return s;
    }

    final switch (arr[0].type) with(JSON_TYPE)
    {
        mixin(makeCase("STRING", "string", "str"));
        mixin(makeCase("INTEGER", "int", "integer.to!int"));
        mixin(makeCase("UINTEGER", "uint", "uinteger.to!uint"));
        mixin(makeCase("FLOAT", "float", "floating"));
        mixin(makeCase("OBJECT", "JSONValue[string]", "object"));
        case ARRAY:
        case TRUE:
        case FALSE:
        case NULL:
            assert(false);
    }
}

