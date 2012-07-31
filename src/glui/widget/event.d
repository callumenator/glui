// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: UI events.
*/

module glui.widget.event;

import
    std.variant;

public import
    glui.event,
    glui.widget.base;


enum WidgetEventType
{
    // Global events fired by root
    GLOBALFOCUSCHANGE,

    // Widget
    DRAG,
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
* Root fires this whenever the focus changes.
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



