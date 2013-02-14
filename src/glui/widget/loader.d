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
    glui.widget.base;



void parseUI(WidgetRoot root, string text)
{

}


Widget[] parseObject(WidgetRoot root, Widget parent, string name, JSONValue[string] obj)
{
    writeln(name);
    Widget newObj;
    Widget[] allObjs;

    if ("type" !in obj)
        assert(false);

    final switch (name)
    {
        case "WidgetWindow":
            //newObj = root.create!WidgetWindow(parent);
            break;
        case "Widget":
            //newObj = new C;
            break;
    }

    foreach(key, val; obj)
    {
        if (val.type == JSON_TYPE.OBJECT)
            allObjs ~= parseObject(root, newObj, key, val.object);
        else {}
            //newObj.set(key, getVal(val));
    }

    allObjs ~= newObj;
    return allObjs;
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

        case OBJECT:
        case ARRAY:
        case TRUE:
        case FALSE:
        case NULL:
            assert(false);
    }
}

