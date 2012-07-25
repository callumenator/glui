// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: Module for processing window events (keyboard, mouse, etc.)
*/
module glui.event;

import
    std.signals,
    std.algorithm,
    std.stdio,
    std.variant,
    std.conv;



/** Structure to contain the current state of all keys. **/
struct KeyState
{
    enum STATE
    { RELEASED = 0, PRESSED = 1 }

    ushort keysDown = 0;
    STATE[] keys;
}


/** Structure to hold the current state of the mouse. **/
struct MouseState
{
    enum STATE
    { RELEASED = 0, PRESSED = 1 }

    int xpos, ypos;
    int xrel, yrel;

    byte buttonsDown = 0;

    align(1) union
    {
        struct
        {
            STATE left;
            STATE middle;
            STATE right;
        }
        STATE[3] button;
    }
}

enum EventType
{
    KEYPRESS,
    KEYRELEASE,
    KEYHOLD,
    MOUSEMOVE,
    MOUSECLICK,
    MOUSERELEASE,
    MOUSEWHEEL,
    WINDOWPAINT,
    WINDOWMOVE,
    WINDOWRESIZE,
    WINDOWFOCUSLOST
}

struct KeyPress
{
    public:
        this(KEY key)
        {
            m_key = key;
        }

        @property KEY key() { return m_key; }
        @property char ascii() { return cast(char)m_key; }
        @property EventType type() { return EventType.KEYPRESS; }

    private:
        KEY  m_key;
}

struct KeyRelease
{
    public:
        this(KEY key)
        {
            m_key = key;
        }

        @property KEY key() { return m_key; }
        @property char ascii() { return cast(char)m_key; }
        @property EventType type() { return EventType.KEYRELEASE; }

    private:
        KEY m_key;
}

struct KeyHold
{
    public:
        this(KEY key)
        {
            m_key = key;
        }

        @property KEY key() { return m_key; }
        @property char ascii() { return cast(char)m_key; }
        @property EventType type() { return EventType.KEYHOLD; }

    private:
        KEY m_key;
}

struct MouseMove
{
    public:
        this(int x, int y, int dx, int dy)
        {
            m_pos[0] = x;
            m_pos[1] = y;
            m_delta[0] = dx;
            m_delta[1] = dy;
        }

        this(int[2] pos, int[2] delta)
        {
            m_pos = pos;
            m_delta = delta;
        }

        @property int x() { return m_pos[0]; }
        @property int y() { return m_pos[1]; }
        @property int dx() { return m_delta[0]; }
        @property int dy() { return m_delta[1]; }
        @property int[2] pos() { return m_pos; }
        @property int[2] delta() { return m_delta; }
        @property EventType type() { return EventType.MOUSEMOVE; }

    private:
        int[2] m_pos;
        int[2] m_delta;
}

struct MouseClick
{
    public:
        enum Button {LEFT, RIGHT, MIDDLE}

        this(int x, int y, Button button)
        {
            m_pos[0] = x;
            m_pos[1] = y;
            m_button = button;
        }

        this(int[2] pos, Button button)
        {
            m_pos = pos;
            m_button = button;
        }

        @property int x() { return m_pos[0]; }
        @property int y() { return m_pos[1]; }
        @property int[2] pos() { return m_pos; }
        @property Button button() { return m_button; }
        @property EventType type() { return EventType.MOUSECLICK; }

    private:
        Button m_button;
        int[2] m_pos;
}

struct MouseRelease
{
    public:
        enum Button {LEFT, RIGHT, MIDDLE}

        this(int x, int y, Button button)
        {
            m_pos[0] = x;
            m_pos[1] = y;
            m_button = button;
        }

        this(int[2] pos, Button button)
        {
            m_pos = pos;
            m_button = button;
        }

        @property int x() { return m_pos[0]; }
        @property int y() { return m_pos[1]; }
        @property int[2] pos() { return m_pos; }
        @property Button button() { return m_button; }
        @property EventType type() { return EventType.MOUSERELEASE; }

    private:
        Button m_button;
        int[2] m_pos;
}


struct MouseWheel
{
    public:

        this(int x, int y, int delta)
        {
            m_pos[0] = x;
            m_pos[1] = y;
            m_delta = delta;
        }

        this(int[2] pos, int delta)
        {
            m_pos = pos;
            m_delta = delta;
        }

        @property int x() const { return m_pos[0]; }
        @property int y() const { return m_pos[1]; }
        @property int[2] pos() const { return m_pos; }
        @property int delta() const { return m_delta; }
        @property EventType type() { return EventType.MOUSEWHEEL; }

    private:
        int[2] m_pos;
        int m_delta;
}


struct WindowMove
{
    @property EventType type() { return EventType.WINDOWMOVE; }
}

struct WindowPaint
{
    @property EventType type() { return EventType.WINDOWPAINT; }
}

struct WindowResize
{
    this(int x, int y)
    {
        m_x = x;
        m_y = y;
    }

    @property EventType type() { return EventType.WINDOWRESIZE; }

    private:
        int m_x, m_y;
}

struct WindowFocusLost
{
    @property EventType type() { return EventType.WINDOWFOCUSLOST; }
}

struct Event
{

    this(T)(T t)
    if ( __traits(isSame, EventType, typeof(t.type)) )
    {
        type = t.type;
        event = t;
    }

    EventType type;
    Variant event;
    alias event this;

    bool consumed = false;
    @property void consume() { consumed = true; }
}



/** Enum for event listener (slot) priorities. **/
enum PRIORITY
{
    LOWEST = 1,
    LOW = 2,
    NORMAL = 3,
    HIGH = 4,
    HIGHEST = 5
}


/**
* This is a modified version of the std.signals signal. It allows associating
* a priority with a slot, and also for slots to return a non-zero integer to stop
* further event processing (i.e. stop the signal being sent to the rest of the
* slots in the list).
*/
template PrioritySignal(T1...)
{
    /// Delegates must return an integer: 0 to continue event signalling, -1 to stop.
    alias int delegate(T1) slot_t;

    /// Each slot consists of a delegate and a priority. Slots are called in order of priority.
    struct Slot
    {
        slot_t dgt = null; /// The delegate.
        PRIORITY priority = PRIORITY.LOWEST;  /// Slot event queue priority.

        /// Comparison function for sorting by priority (HIGHEST to LOWEST).
        int opCmp(ref const Slot rhs) const
        {
            return (rhs.priority - priority);
        }
    }

    /** Emit event signal. **/
    void emit( T1 i )
    {
        /// Send signal to all slots, unless the event is consumed (a slot returns -1).
        foreach (slot; slots)
        {
            if (slot.dgt !is null)
            {
                if (slot.dgt(i) == -1)
                    break;
            }
        }
    }

    /** Connect a given delegate, with the given priority. **/
    void connect(slot_t slot, PRIORITY p = PRIORITY.NORMAL)
    {
        Slot newSlot = {slot, p};
        slots ~= newSlot;

        /// Sort them by priority.
        slots.sort;

        /// Hook in to be alerted when the delegate's object is deleted.
        Object o = _d_toObject(slot.ptr);
        rt_attachDisposeEvent(o, &unhook);
    }

    /** Disconnect a delegate. **/
    void disconnect(slot_t slot)
    {
        foreach(index, s; slots)
        {
            size_t len = slots.length;
            if (s.dgt == slot)
            {
                if (index == 0)
                    slots = slots[1..len];
                else if (index == len-1)
                    slots = slots[0..len-1];
                else
                    slots = slots[0..index-1] ~ slots[index+1..len];
            }
        }
    }

    /** Disconnect a delegate when it is deleted. **/
    void unhook(Object o)
    {
        foreach (slot; slots)
        {
            if (_d_toObject(slot.dgt.ptr) is o)
                disconnect(slot.dgt);
        }
    }

    /** On destruction, remove the hooks on each delegate. **/
    ~this()
    {
        if (slots.length > 0)
        {
            foreach (slot; slots)
            {
                if (slot.dgt)
                {
                    Object o = _d_toObject(slot.dgt.ptr);
                    rt_detachDisposeEvent(o, &unhook);
                }
            }
            slots.length = 0;
        }
    }

private:
    Slot[] slots;   /// List of slots.
}



version(Windows)
{
    import win32.winuser;

    immutable nonAsciiOffset = 0x007F;

    enum KEY : uint
    {
        KC_NULL                          = 0x0000,
        KC_BACKSPACE                     = 0x0008,  /* BACK SPACE, BACK CHAR */
        KC_TAB                           = 0x0009,
        KC_RETURN                        = 0x000D,  /* RETURN, ENTER */
        KC_PAUSE                         = 0x0013,  /* PAUSE, HOLD */
        KC_SCROLL_LOCK                   = 0x0014,
        KC_SYS_REQ                       = 0x0015,
        KC_ESCAPE                        = 0x001B,
        KC_SPACE                         = 0x0020,  /* U+0020 SPACE */
        KC_EXCLAM                        = 0x0021,  /* U+0021 EXCLAMATION MARK */
        KC_QUOTEDBL                      = 0x0022,  /* U+0022 QUOTATION MARK */
        KC_NUMBERSIGN                    = 0x0023,  /* U+0023 NUMBER SIGN */
        KC_DOLLAR                        = 0x0024,  /* U+0024 DOLLAR SIGN */
        KC_PERCENT                       = 0x0025,  /* U+0025 PERCENT SIGN */
        KC_AMPERSAND                     = 0x0026,  /* U+0026 AMPERSAND */
        KC_APOSTROPHE                    = 0x0027,  /* U+0027 APOSTROPHE */
        KC_QUOTERIGHT                    = 0x0027,  /* DEPRECATED */
        KC_PARENLEFT                     = 0x0028,  /* U+0028 LEFT PARENTHESIS */
        KC_PARENRIGHT                    = 0x0029,  /* U+0029 RIGHT PARENTHESIS */
        KC_ASTERISK                      = 0x002A,  /* U+002A ASTERISK */
        KC_PLUS                          = 0x002B,  /* U+002B PLUS SIGN */
        KC_COMMA                         = 0x002C,  /* U+002C COMMA */
        KC_MINUS                         = 0x002D,  /* U+002D HYPHEN-MINUS */
        KC_PERIOD                        = 0x002E,  /* U+002E FULL STOP */
        KC_SLASH                         = 0x002F,  /* U+002F SOLIDUS */
        KC_0                             = 0x0030,  /* U+0030 DIGIT ZERO */
        KC_1                             = 0x0031,  /* U+0031 DIGIT ONE */
        KC_2                             = 0x0032,  /* U+0032 DIGIT TWO */
        KC_3                             = 0x0033,  /* U+0033 DIGIT THREE */
        KC_4                             = 0x0034,  /* U+0034 DIGIT FOUR */
        KC_5                             = 0x0035,  /* U+0035 DIGIT FIVE */
        KC_6                             = 0x0036,  /* U+0036 DIGIT SIX */
        KC_7                             = 0x0037,  /* U+0037 DIGIT SEVEN */
        KC_8                             = 0x0038,  /* U+0038 DIGIT EIGHT */
        KC_9                             = 0x0039,  /* U+0039 DIGIT NINE */
        KC_COLON                         = 0x003A,  /* U+003A COLON */
        KC_SEMICOLON                     = 0x003B,  /* U+003B SEMICOLON */
        KC_LESS                          = 0x003C,  /* U+003C LESS-THAN SIGN */
        KC_EQUAL                         = 0x003D,  /* U+003D EQUALS SIGN */
        KC_GREATER                       = 0x003E,  /* U+003E GREATER-THAN SIGN */
        KC_QUESTION                      = 0x003F,  /* U+003F QUESTION MARK */
        KC_AT                            = 0x0040,  /* U+0040 COMMERCIAL AT */
        KC_A                             = 0x0041,  /* U+0041 LATIN CAPITAL LETTER A */
        KC_B                             = 0x0042,  /* U+0042 LATIN CAPITAL LETTER B */
        KC_C                             = 0x0043,  /* U+0043 LATIN CAPITAL LETTER C */
        KC_D                             = 0x0044,  /* U+0044 LATIN CAPITAL LETTER D */
        KC_E                             = 0x0045,  /* U+0045 LATIN CAPITAL LETTER E */
        KC_F                             = 0x0046,  /* U+0046 LATIN CAPITAL LETTER F */
        KC_G                             = 0x0047,  /* U+0047 LATIN CAPITAL LETTER G */
        KC_H                             = 0x0048,  /* U+0048 LATIN CAPITAL LETTER H */
        KC_I                             = 0x0049,  /* U+0049 LATIN CAPITAL LETTER I */
        KC_J                             = 0x004a,  /* U+004A LATIN CAPITAL LETTER J */
        KC_K                             = 0x004b,  /* U+004B LATIN CAPITAL LETTER K */
        KC_L                             = 0x004c,  /* U+004C LATIN CAPITAL LETTER L */
        KC_M                             = 0x004d,  /* U+004D LATIN CAPITAL LETTER M */
        KC_N                             = 0x004e,  /* U+004E LATIN CAPITAL LETTER N */
        KC_O                             = 0x004f,  /* U+004F LATIN CAPITAL LETTER O */
        KC_P                             = 0x0050,  /* U+0050 LATIN CAPITAL LETTER P */
        KC_Q                             = 0x0051,  /* U+0051 LATIN CAPITAL LETTER Q */
        KC_R                             = 0x0052,  /* U+0052 LATIN CAPITAL LETTER R */
        KC_S                             = 0x0053,  /* U+0053 LATIN CAPITAL LETTER S */
        KC_T                             = 0x0054,  /* U+0054 LATIN CAPITAL LETTER T */
        KC_U                             = 0x0055,  /* U+0055 LATIN CAPITAL LETTER U */
        KC_V                             = 0x0056,  /* U+0056 LATIN CAPITAL LETTER V */
        KC_W                             = 0x0057,  /* U+0057 LATIN CAPITAL LETTER W */
        KC_X                             = 0x0058,  /* U+0058 LATIN CAPITAL LETTER X */
        KC_Y                             = 0x0059,  /* U+0059 LATIN CAPITAL LETTER Y */
        KC_Z                             = 0x005a,  /* U+005A LATIN CAPITAL LETTER Z */
        KC_BRACKETLEFT                   = 0x005B,  /* U+005B LEFT SQUARE BRACKET */
        KC_BACKSLASH                     = 0x005C,  /* U+005C REVERSE SOLIDUS */
        KC_BRACKETRIGHT                  = 0x005D,  /* U+005D RIGHT SQUARE BRACKET */
        KC_ASCIICIRCUM                   = 0x005E,  /* U+005E CIRCUMFLEX ACCENT */
        KC_UNDERSCORE                    = 0x005F,  /* U+005F LOW LINE */
        KC_GRAVE                         = 0x0060,  /* U+0060 GRAVE ACCENT */
        KC_QUOTELEFT                     = 0x0060,  /* DEPRECATED */
        KC_a                             = 0x0061,  /* U+0061 LATIN SMALL LETTER A */
        KC_b                             = 0x0062,  /* U+0062 LATIN SMALL LETTER B */
        KC_c                             = 0x0063,  /* U+0063 LATIN SMALL LETTER C */
        KC_d                             = 0x0064,  /* U+0064 LATIN SMALL LETTER D */
        KC_e                             = 0x0065,  /* U+0065 LATIN SMALL LETTER E */
        KC_f                             = 0x0066,  /* U+0066 LATIN SMALL LETTER F */
        KC_g                             = 0x0067,  /* U+0067 LATIN SMALL LETTER G */
        KC_h                             = 0x0068,  /* U+0068 LATIN SMALL LETTER H */
        KC_i                             = 0x0069,  /* U+0069 LATIN SMALL LETTER I */
        KC_j                             = 0x006a,  /* U+006A LATIN SMALL LETTER J */
        KC_k                             = 0x006b,  /* U+006B LATIN SMALL LETTER K */
        KC_l                             = 0x006c,  /* U+006C LATIN SMALL LETTER L */
        KC_m                             = 0x006d,  /* U+006D LATIN SMALL LETTER M */
        KC_n                             = 0x006e,  /* U+006E LATIN SMALL LETTER N */
        KC_o                             = 0x006f,  /* U+006F LATIN SMALL LETTER O */
        KC_p                             = 0x0070,  /* U+0070 LATIN SMALL LETTER P */
        KC_q                             = 0x0071,  /* U+0071 LATIN SMALL LETTER Q */
        KC_r                             = 0x0072,  /* U+0072 LATIN SMALL LETTER R */
        KC_s                             = 0x0073,  /* U+0073 LATIN SMALL LETTER S */
        KC_t                             = 0x0074,  /* U+0074 LATIN SMALL LETTER T */
        KC_u                             = 0x0075,  /* U+0075 LATIN SMALL LETTER U */
        KC_v                             = 0x0076,  /* U+0076 LATIN SMALL LETTER V */
        KC_w                             = 0x0077,  /* U+0077 LATIN SMALL LETTER W */
        KC_x                             = 0x0078,  /* U+0078 LATIN SMALL LETTER X */
        KC_y                             = 0x0079,  /* U+0079 LATIN SMALL LETTER Y */
        KC_z                             = 0x007a,  /* U+007A LATIN SMALL LETTER Z */
        KC_BRACELEFT                     = 0x007B,  /* U+007B LEFT CURLY BRACKET */
        KC_BAR                           = 0x007C,  /* U+007C VERTICAL LINE */
        KC_BRACERIGHT                    = 0x007D,  /* U+007D RIGHT CURLY BRACKET */
        KC_ASCIITILDE                    = 0x007E,  /* U+007E TILDE */
        KC_DELETE                        = 0x002E + nonAsciiOffset,
        KC_SHIFT_LEFT                    = 0x00A0 + nonAsciiOffset,  /* Left shift */
        KC_SHIFT_RIGHT                   = 0x00A1 + nonAsciiOffset,  /* Right shift */
        KC_CTRL_LEFT                     = 0x00A2 + nonAsciiOffset,  /* Left control */
        KC_CTRL_RIGHT                    = 0x00A3 + nonAsciiOffset,  /* Right control */
        KC_F1                            = 0x0070 + nonAsciiOffset,
        KC_F2                            = 0x0071 + nonAsciiOffset,
        KC_F3                            = 0x0072 + nonAsciiOffset,
        KC_F4                            = 0x0073 + nonAsciiOffset,
        KC_F5                            = 0x0074 + nonAsciiOffset,
        KC_F6                            = 0x0075 + nonAsciiOffset,
        KC_F7                            = 0x0076 + nonAsciiOffset,
        KC_F8                            = 0x0077 + nonAsciiOffset,
        KC_F9                            = 0x0078 + nonAsciiOffset,
        KC_F10                           = 0x0079 + nonAsciiOffset,
        KC_F11                           = 0x007A + nonAsciiOffset,
        KC_F12                           = 0x007B + nonAsciiOffset,
        KC_HOME                          = 0x0024 + nonAsciiOffset,
        KC_LEFT                          = 0x0025 + nonAsciiOffset,  /* Move left, left arrow */
        KC_UP                            = 0x0026 + nonAsciiOffset,  /* Move up, up arrow */
        KC_RIGHT                         = 0x0027 + nonAsciiOffset,  /* Move right, right arrow */
        KC_DOWN                          = 0x0028 + nonAsciiOffset,  /* Move down, down arrow */
        KC_PAGE_UP                       = 0x0021 + nonAsciiOffset,
        KC_PAGE_DOWN                     = 0x0022 + nonAsciiOffset,
        KC_END                           = 0x0023 + nonAsciiOffset
    }
}

version(Posix)
{
    import deimos.X11.keysymdef;

    immutable nonAsciiOffset = 0x007F - 0xFF00;

    enum KEY : uint
    {
        KC_NULL                          = 0x0000,
        KC_BACKSPACE                     = 0x0008,  /* BACK SPACE, BACK CHAR */
        KC_TAB                           = 0x0009,
        KC_RETURN                        = 0x000D,  /* RETURN, ENTER */
        KC_PAUSE                         = 0x0013,  /* PAUSE, HOLD */
        KC_SCROLL_LOCK                   = 0x0014,
        KC_SYS_REQ                       = 0x0015,
        KC_ESCAPE                        = 0x001B,
        KC_SPACE                         = 0x0020,  /* U+0020 SPACE */
        KC_EXCLAM                        = 0x0021,  /* U+0021 EXCLAMATION MARK */
        KC_QUOTEDBL                      = 0x0022,  /* U+0022 QUOTATION MARK */
        KC_NUMBERSIGN                    = 0x0023,  /* U+0023 NUMBER SIGN */
        KC_DOLLAR                        = 0x0024,  /* U+0024 DOLLAR SIGN */
        KC_PERCENT                       = 0x0025,  /* U+0025 PERCENT SIGN */
        KC_AMPERSAND                     = 0x0026,  /* U+0026 AMPERSAND */
        KC_APOSTROPHE                    = 0x0027,  /* U+0027 APOSTROPHE */
        KC_QUOTERIGHT                    = 0x0027,  /* DEPRECATED */
        KC_PARENLEFT                     = 0x0028,  /* U+0028 LEFT PARENTHESIS */
        KC_PARENRIGHT                    = 0x0029,  /* U+0029 RIGHT PARENTHESIS */
        KC_ASTERISK                      = 0x002A,  /* U+002A ASTERISK */
        KC_PLUS                          = 0x002B,  /* U+002B PLUS SIGN */
        KC_COMMA                         = 0x002C,  /* U+002C COMMA */
        KC_MINUS                         = 0x002D,  /* U+002D HYPHEN-MINUS */
        KC_PERIOD                        = 0x002E,  /* U+002E FULL STOP */
        KC_SLASH                         = 0x002F,  /* U+002F SOLIDUS */
        KC_0                             = 0x0030,  /* U+0030 DIGIT ZERO */
        KC_1                             = 0x0031,  /* U+0031 DIGIT ONE */
        KC_2                             = 0x0032,  /* U+0032 DIGIT TWO */
        KC_3                             = 0x0033,  /* U+0033 DIGIT THREE */
        KC_4                             = 0x0034,  /* U+0034 DIGIT FOUR */
        KC_5                             = 0x0035,  /* U+0035 DIGIT FIVE */
        KC_6                             = 0x0036,  /* U+0036 DIGIT SIX */
        KC_7                             = 0x0037,  /* U+0037 DIGIT SEVEN */
        KC_8                             = 0x0038,  /* U+0038 DIGIT EIGHT */
        KC_9                             = 0x0039,  /* U+0039 DIGIT NINE */
        KC_COLON                         = 0x003A,  /* U+003A COLON */
        KC_SEMICOLON                     = 0x003B,  /* U+003B SEMICOLON */
        KC_LESS                          = 0x003C,  /* U+003C LESS-THAN SIGN */
        KC_EQUAL                         = 0x003D,  /* U+003D EQUALS SIGN */
        KC_GREATER                       = 0x003E,  /* U+003E GREATER-THAN SIGN */
        KC_QUESTION                      = 0x003F,  /* U+003F QUESTION MARK */
        KC_AT                            = 0x0040,  /* U+0040 COMMERCIAL AT */
        KC_A                             = 0x0041,  /* U+0041 LATIN CAPITAL LETTER A */
        KC_B                             = 0x0042,  /* U+0042 LATIN CAPITAL LETTER B */
        KC_C                             = 0x0043,  /* U+0043 LATIN CAPITAL LETTER C */
        KC_D                             = 0x0044,  /* U+0044 LATIN CAPITAL LETTER D */
        KC_E                             = 0x0045,  /* U+0045 LATIN CAPITAL LETTER E */
        KC_F                             = 0x0046,  /* U+0046 LATIN CAPITAL LETTER F */
        KC_G                             = 0x0047,  /* U+0047 LATIN CAPITAL LETTER G */
        KC_H                             = 0x0048,  /* U+0048 LATIN CAPITAL LETTER H */
        KC_I                             = 0x0049,  /* U+0049 LATIN CAPITAL LETTER I */
        KC_J                             = 0x004a,  /* U+004A LATIN CAPITAL LETTER J */
        KC_K                             = 0x004b,  /* U+004B LATIN CAPITAL LETTER K */
        KC_L                             = 0x004c,  /* U+004C LATIN CAPITAL LETTER L */
        KC_M                             = 0x004d,  /* U+004D LATIN CAPITAL LETTER M */
        KC_N                             = 0x004e,  /* U+004E LATIN CAPITAL LETTER N */
        KC_O                             = 0x004f,  /* U+004F LATIN CAPITAL LETTER O */
        KC_P                             = 0x0050,  /* U+0050 LATIN CAPITAL LETTER P */
        KC_Q                             = 0x0051,  /* U+0051 LATIN CAPITAL LETTER Q */
        KC_R                             = 0x0052,  /* U+0052 LATIN CAPITAL LETTER R */
        KC_S                             = 0x0053,  /* U+0053 LATIN CAPITAL LETTER S */
        KC_T                             = 0x0054,  /* U+0054 LATIN CAPITAL LETTER T */
        KC_U                             = 0x0055,  /* U+0055 LATIN CAPITAL LETTER U */
        KC_V                             = 0x0056,  /* U+0056 LATIN CAPITAL LETTER V */
        KC_W                             = 0x0057,  /* U+0057 LATIN CAPITAL LETTER W */
        KC_X                             = 0x0058,  /* U+0058 LATIN CAPITAL LETTER X */
        KC_Y                             = 0x0059,  /* U+0059 LATIN CAPITAL LETTER Y */
        KC_Z                             = 0x005a,  /* U+005A LATIN CAPITAL LETTER Z */
        KC_BRACKETLEFT                   = 0x005B,  /* U+005B LEFT SQUARE BRACKET */
        KC_BACKSLASH                     = 0x005C,  /* U+005C REVERSE SOLIDUS */
        KC_BRACKETRIGHT                  = 0x005D,  /* U+005D RIGHT SQUARE BRACKET */
        KC_ASCIICIRCUM                   = 0x005E,  /* U+005E CIRCUMFLEX ACCENT */
        KC_UNDERSCORE                    = 0x005F,  /* U+005F LOW LINE */
        KC_GRAVE                         = 0x0060,  /* U+0060 GRAVE ACCENT */
        KC_QUOTELEFT                     = 0x0060,  /* DEPRECATED */
        KC_a                             = 0x0061,  /* U+0061 LATIN SMALL LETTER A */
        KC_b                             = 0x0062,  /* U+0062 LATIN SMALL LETTER B */
        KC_c                             = 0x0063,  /* U+0063 LATIN SMALL LETTER C */
        KC_d                             = 0x0064,  /* U+0064 LATIN SMALL LETTER D */
        KC_e                             = 0x0065,  /* U+0065 LATIN SMALL LETTER E */
        KC_f                             = 0x0066,  /* U+0066 LATIN SMALL LETTER F */
        KC_g                             = 0x0067,  /* U+0067 LATIN SMALL LETTER G */
        KC_h                             = 0x0068,  /* U+0068 LATIN SMALL LETTER H */
        KC_i                             = 0x0069,  /* U+0069 LATIN SMALL LETTER I */
        KC_j                             = 0x006a,  /* U+006A LATIN SMALL LETTER J */
        KC_k                             = 0x006b,  /* U+006B LATIN SMALL LETTER K */
        KC_l                             = 0x006c,  /* U+006C LATIN SMALL LETTER L */
        KC_m                             = 0x006d,  /* U+006D LATIN SMALL LETTER M */
        KC_n                             = 0x006e,  /* U+006E LATIN SMALL LETTER N */
        KC_o                             = 0x006f,  /* U+006F LATIN SMALL LETTER O */
        KC_p                             = 0x0070,  /* U+0070 LATIN SMALL LETTER P */
        KC_q                             = 0x0071,  /* U+0071 LATIN SMALL LETTER Q */
        KC_r                             = 0x0072,  /* U+0072 LATIN SMALL LETTER R */
        KC_s                             = 0x0073,  /* U+0073 LATIN SMALL LETTER S */
        KC_t                             = 0x0074,  /* U+0074 LATIN SMALL LETTER T */
        KC_u                             = 0x0075,  /* U+0075 LATIN SMALL LETTER U */
        KC_v                             = 0x0076,  /* U+0076 LATIN SMALL LETTER V */
        KC_w                             = 0x0077,  /* U+0077 LATIN SMALL LETTER W */
        KC_x                             = 0x0078,  /* U+0078 LATIN SMALL LETTER X */
        KC_y                             = 0x0079,  /* U+0079 LATIN SMALL LETTER Y */
        KC_z                             = 0x007a,  /* U+007A LATIN SMALL LETTER Z */
        KC_BRACELEFT                     = 0x007B,  /* U+007B LEFT CURLY BRACKET */
        KC_BAR                           = 0x007C,  /* U+007C VERTICAL LINE */
        KC_BRACERIGHT                    = 0x007D,  /* U+007D RIGHT CURLY BRACKET */
        KC_ASCIITILDE                    = 0x007E,  /* U+007E TILDE */
        KC_DELETE                        = 0x007F,
        KC_SHIFT_LEFT                    = 0xFFE1 + nonAsciiOffset,  /* Left shift */
        KC_SHIFT_RIGHT                   = 0xFFE2 + nonAsciiOffset,  /* Right shift */
        KC_CTRL_LEFT                     = 0xFFE3 + nonAsciiOffset,  /* Left control */
        KC_CTRL_RIGHT                    = 0xFFE4 + nonAsciiOffset,  /* Right control */
        KC_F1                            = 0xFFBE + nonAsciiOffset,
        KC_F2                            = 0xFFBF + nonAsciiOffset,
        KC_F3                            = 0xFFC0 + nonAsciiOffset,
        KC_F4                            = 0xFFC1 + nonAsciiOffset,
        KC_F5                            = 0xFFC2 + nonAsciiOffset,
        KC_F6                            = 0xFFC3 + nonAsciiOffset,
        KC_F7                            = 0xFFC4 + nonAsciiOffset,
        KC_F8                            = 0xFFC5 + nonAsciiOffset,
        KC_F9                            = 0xFFC6 + nonAsciiOffset,
        KC_F10                           = 0xFFC7 + nonAsciiOffset,
        KC_F11                           = 0xFFC8 + nonAsciiOffset,
        KC_F12                           = 0xFFC9 + nonAsciiOffset,
        KC_HOME                          = 0xFF50 + nonAsciiOffset,
        KC_LEFT                          = 0xFF51 + nonAsciiOffset,  /* Move left, left arrow */
        KC_UP                            = 0xFF52 + nonAsciiOffset,  /* Move up, up arrow */
        KC_RIGHT                         = 0xFF53 + nonAsciiOffset,  /* Move right, right arrow */
        KC_DOWN                          = 0xFF54 + nonAsciiOffset,  /* Move down, down arrow */
        KC_PAGE_UP                       = 0xFF55 + nonAsciiOffset,
        KC_PAGE_DOWN                     = 0xFF56 + nonAsciiOffset,
        KC_END                           = 0xFF57 + nonAsciiOffset
    }

}

/** Keyboard scan codes taken from OIS. **/
/++
    enum KEY : uint
	{
		KC_UNASSIGNED  = 0x00,
		KC_ESCAPE      = 0x01,
		KC_1           = 0x02,
		KC_2           = 0x03,
		KC_3           = 0x04,
		KC_4           = 0x05,
		KC_5           = 0x06,
		KC_6           = 0x07,
		KC_7           = 0x08,
		KC_8           = 0x09,
		KC_9           = 0x0A,
		KC_0           = 0x0B,
		KC_MINUS       = 0x0C,    // - on main keyboard
		KC_EQUALS      = 0x0D,
		KC_BACK        = 0x0E,    // backspace
		KC_TAB         = 0x0F,
		KC_Q           = 0x10,
		KC_W           = 0x11,
		KC_E           = 0x12,
		KC_R           = 0x13,
		KC_T           = 0x14,
		KC_Y           = 0x15,
		KC_U           = 0x16,
		KC_I           = 0x17,
		KC_O           = 0x18,
		KC_P           = 0x19,
		KC_LBRACKET    = 0x1A,
		KC_RBRACKET    = 0x1B,
		KC_RETURN      = 0x1C,    // Enter on main keyboard
		KC_LCONTROL    = 0x1D,
		KC_A           = 0x1E,
		KC_S           = 0x1F,
		KC_D           = 0x20,
		KC_F           = 0x21,
		KC_G           = 0x22,
		KC_H           = 0x23,
		KC_J           = 0x24,
		KC_K           = 0x25,
		KC_L           = 0x26,
		KC_SEMICOLON   = 0x27,
		KC_APOSTROPHE  = 0x28,
		KC_GRAVE       = 0x29,    // accent
		KC_LSHIFT      = 0x2A,
		KC_BACKSLASH   = 0x2B,
		KC_Z           = 0x2C,
		KC_X           = 0x2D,
		KC_C           = 0x2E,
		KC_V           = 0x2F,
		KC_B           = 0x30,
		KC_N           = 0x31,
		KC_M           = 0x32,
		KC_COMMA       = 0x33,
		KC_PERIOD      = 0x34,    // . on main keyboard
		KC_SLASH       = 0x35,    // / on main keyboard
		KC_RSHIFT      = 0x36,
		KC_MULTIPLY    = 0x37,    // * on numeric keypad
		KC_LMENU       = 0x38,    // left Alt
		KC_SPACE       = 0x39,
		KC_CAPITAL     = 0x3A,
		KC_F1          = 0x3B,
		KC_F2          = 0x3C,
		KC_F3          = 0x3D,
		KC_F4          = 0x3E,
		KC_F5          = 0x3F,
		KC_F6          = 0x40,
		KC_F7          = 0x41,
		KC_F8          = 0x42,
		KC_F9          = 0x43,
		KC_F10         = 0x44,
		KC_NUMLOCK     = 0x45,
		KC_SCROLL      = 0x46,    // Scroll Lock
		KC_NUMPAD7     = 0x47,
		KC_NUMPAD8     = 0x48,
		KC_NUMPAD9     = 0x49,
		KC_SUBTRACT    = 0x4A,    // - on numeric keypad
		KC_NUMPAD4     = 0x4B,
		KC_NUMPAD5     = 0x4C,
		KC_NUMPAD6     = 0x4D,
		KC_ADD         = 0x4E,    // + on numeric keypad
		KC_NUMPAD1     = 0x4F,
		KC_NUMPAD2     = 0x50,
		KC_NUMPAD3     = 0x51,
		KC_NUMPAD0     = 0x52,
		KC_DECIMAL     = 0x53,    // . on numeric keypad
		KC_OEM_102     = 0x56,    // < > | on UK/Germany keyboards
		KC_F11         = 0x57,
		KC_F12         = 0x58,
		KC_F13         = 0x64,    //                     (NEC PC98)
		KC_F14         = 0x65,    //                     (NEC PC98)
		KC_F15         = 0x66,    //                     (NEC PC98)
		KC_KANA        = 0x70,    // (Japanese keyboard)
		KC_ABNT_C1     = 0x73,    // / ? on Portugese (Brazilian) keyboards
		KC_CONVERT     = 0x79,    // (Japanese keyboard)
		KC_NOCONVERT   = 0x7B,    // (Japanese keyboard)
		KC_YEN         = 0x7D,    // (Japanese keyboard)
		KC_ABNT_C2     = 0x7E,    // Numpad . on Portugese (Brazilian) keyboards
		KC_NUMPADEQUALS= 0x8D,    // = on numeric keypad (NEC PC98)
		KC_PREVTRACK   = 0x90,    // Previous Track (KC_CIRCUMFLEX on Japanese keyboard)
		KC_AT          = 0x91,    //                     (NEC PC98)
		KC_COLON       = 0x92,    //                     (NEC PC98)
		KC_UNDERLINE   = 0x93,    //                     (NEC PC98)
		KC_KANJI       = 0x94,    // (Japanese keyboard)
		KC_STOP        = 0x95,    //                     (NEC PC98)
		KC_AX          = 0x96,    //                     (Japan AX)
		KC_UNLABELED   = 0x97,    //                        (J3100)
		KC_NEXTTRACK   = 0x99,    // Next Track
		KC_NUMPADENTER = 0x9C,    // Enter on numeric keypad
		KC_RCONTROL    = 0x9D,
		KC_MUTE        = 0xA0,    // Mute
		KC_CALCULATOR  = 0xA1,    // Calculator
		KC_PLAYPAUSE   = 0xA2,    // Play / Pause
		KC_MEDIASTOP   = 0xA4,    // Media Stop
		KC_VOLUMEDOWN  = 0xAE,    // Volume -
		KC_VOLUMEUP    = 0xB0,    // Volume +
		KC_WEBHOME     = 0xB2,    // Web home
		KC_NUMPADCOMMA = 0xB3,    // , on numeric keypad (NEC PC98)
		KC_DIVIDE      = 0xB5,    // / on numeric keypad
		KC_SYSRQ       = 0xB7,
		KC_RMENU       = 0xB8,    // right Alt
		KC_PAUSE       = 0xC5,    // Pause
		KC_HOME        = 0xC7,    // Home on arrow keypad
		KC_UP          = 0xC8,    // UpArrow on arrow keypad
		KC_PGUP        = 0xC9,    // PgUp on arrow keypad
		KC_LEFT        = 0xCB,    // LeftArrow on arrow keypad
		KC_RIGHT       = 0xCD,    // RightArrow on arrow keypad
		KC_END         = 0xCF,    // End on arrow keypad
		KC_DOWN        = 0xD0,    // DownArrow on arrow keypad
		KC_PGDOWN      = 0xD1,    // PgDn on arrow keypad
		KC_INSERT      = 0xD2,    // Insert on arrow keypad
		KC_DELETE      = 0xD3,    // Delete on arrow keypad
		KC_LWIN        = 0xDB,    // Left Windows key
		KC_RWIN        = 0xDC,    // Right Windows key
		KC_APPS        = 0xDD,    // AppMenu key
		KC_POWER       = 0xDE,    // System Power
		KC_SLEEP       = 0xDF,    // System Sleep
		KC_WAKE        = 0xE3,    // System Wake
		KC_WEBSEARCH   = 0xE5,    // Web Search
		KC_WEBFAVORITES= 0xE6,    // Web Favorites
		KC_WEBREFRESH  = 0xE7,    // Web Refresh
		KC_WEBSTOP     = 0xE8,    // Web Stop
		KC_WEBFORWARD  = 0xE9,    // Web Forward
		KC_WEBBACK     = 0xEA,    // Web Back
		KC_MYCOMPUTER  = 0xEB,    // My Computer
		KC_MAIL        = 0xEC,    // Mail
		KC_MEDIASELECT = 0xED     // Media Select
	}

++/
