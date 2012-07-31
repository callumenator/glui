// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: UI events.
*/

module glui.widget.event;

public import
    glui.event;

enum WidgetEventType
{
    // Widget
    DRAG,
    GAINEDFOCUS,
    LOSTFOCUS,
    GAINEDHOVER,
    LOSTHOVER,

    // WidgetText
    TEXTINSERT,
    TEXTREMOVE,
    TEXTRETURN
}

struct GainedFocus
{
    @property EventType type() { return WidgetEventType.GAINEDFOCUS; }
}

struct LostFocus
{
    @property EventType type() { return WidgetEventType.LOSTFOCUS; }
}

struct GainedHover
{
    @property EventType type() { return WidgetEventType.GAINEDHOVER; }
}

struct LostHover
{
    @property EventType type() { return WidgetEventType.LOSTHOVER; }
}

struct Drag
{
    public:

        this(int[2] pos, int delta)
        {
            m_pos = pos;
            m_delta = delta;
        }

        @property int[2] pos() const { return m_pos; }
        @property int[2] delta() const { return m_delta; }
        @property EventType type() { return WidgetEventType.DRAG; }

    private:
        int[2] m_pos;
        int[2] m_delta;
}


/**
* WidgetText
*/

struct TextInsert
{
    public:

        this(string s)
        {
            m_text = s;
        }

        @property string text() const { return m_text; }
        @property EventType type() { return WidgetEventType.TEXTINSERT; }

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
        @property EventType type() { return WidgetEventType.TEXTREMOVE; }

    private:
        string m_text;
}

// Return key was pressed
struct TextReturn
{
    @property EventType type() { return WidgetEventType.TEXTRETURN; }
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



