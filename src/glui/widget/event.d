// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: Widget events. This mirrors the system in glui.event for
* platform events (Key, Mouse and Window events).
*/

module glui.widget.event;

import
    std.variant;

public import
    glui.event,
    glui.widget.base;


/**
* Every widget event must be represented in this enum.
*/
enum WidgetEventType
{
    // Global events fired by root
    GLOBALFOCUSCHANGE,

    // Widget
    DRAG,
    RESIZE,
    GAINEDFOCUS,
    LOSTFOCUS,
    GAINEDHOVER,
    LOSTHOVER,

    // WidgetText
    TEXTINSERT,
    TEXTREMOVE,
    TEXTRETURN,

    // WidgetScroll
    SCROLL
}


/**
* WidgetRoot fires this whenever the focus changes.
*/
struct GlobalFocusChange
{
    public:

        this(Widget newFocus, Widget oldFocus)
        {
            m_newFocus = newFocus;
            m_oldFocus = oldFocus;
        }

        @property Widget newFocus() { return m_newFocus; }
        @property Widget oldFocus() { return m_oldFocus; }
        @property WidgetEventType type() { return WidgetEventType.GAINEDFOCUS; }

    private:
        Widget m_newFocus;
        Widget m_oldFocus;
}


/**
* Events fired by all widgets.
*/
struct GainedFocus
{
    @property WidgetEventType type() { return WidgetEventType.GAINEDFOCUS; }
}

struct LostFocus
{
    @property WidgetEventType type() { return WidgetEventType.LOSTFOCUS; }
}

struct GainedHover
{
    @property WidgetEventType type() { return WidgetEventType.GAINEDHOVER; }
}

struct LostHover
{
    @property WidgetEventType type() { return WidgetEventType.LOSTHOVER; }
}

struct Drag
{
    public:

        /**
        * params:
        * pos = current position of the mouse pointer
        * delta = change in mouse position
        */
        this(int[2] pos, int[2] delta)
        {
            m_pos = pos;
            m_delta = delta;
        }

        @property int[2] pos() const { return m_pos; }
        @property int[2] delta() const { return m_delta; }
        @property WidgetEventType type() { return WidgetEventType.DRAG; }

    private:
        int[2] m_pos;
        int[2] m_delta;
}

struct Resize
{
    public:

        /**
        * params:
        * oldPos = previous pos (new pos can be retrieved manually)
        * oldDim = previous dim (new dim can be retrieved manually)
        */
        this(int[2] oldDos, int[2] oldDim)
        {
            m_oldPos = oldPos;
            m_oldDim = oldDim;
        }

        @property int[2] oldPos() const { return m_oldPos; }
        @property int[2] oldDim() const { return m_oldDim; }
        @property WidgetEventType type() { return WidgetEventType.RESIZE; }

    private:
        int[2] m_oldPos;
        int[2] m_oldDim;
}


/**
* WidgetText events
*/
struct TextInsert
{
    public:

        this(string s)
        {
            m_text = s;
        }

        @property string text() const { return m_text; }
        @property WidgetEventType type() { return WidgetEventType.TEXTINSERT; }

    private:
        string m_text;
}

struct TextRemove
{
    public:

        this(string s)
        {
            m_text = s;
        }

        @property string text() const { return m_text; }
        @property WidgetEventType type() { return WidgetEventType.TEXTREMOVE; }

    private:
        string m_text;
}

// Return key was pressed
struct TextReturn
{
    @property WidgetEventType type() { return WidgetEventType.TEXTRETURN; }
}



/**
* WidgetScroll events
*/
struct Scroll
{
    public:

        this(int current)
        {
            m_current = current;
        }

        @property int current() const { return m_current; }
        @property WidgetEventType type() { return WidgetEventType.SCROLL; }

    private:
        int m_current;
}


struct WidgetEvent
{
    this(T)(T t)
    if ( __traits(isSame, WidgetEventType, typeof(t.type)) )
    {
        type = t.type;
        event = t;
    }

    WidgetEventType type;
    Variant event;
    alias event this;

    bool consumed = false;
    @property void consume() { consumed = true; }
}



