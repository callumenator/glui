// Written in the\ D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: UI text elements.
*/

module glui.widget.text;

import
    std.array,
    std.conv,
    std.string,
    std.datetime;

import
    derelict.opengl.gl;

import
    glui.truetype,
    glui.widget.base;

/**
* Text box. This is a possibly editable box for rendering text.
*/
class WidgetText : WidgetWindow
{
    public:

        // Text horizontal alignment
        enum HAlign
        {
            LEFT, CENTER, RIGHT
        }

        // Text vertical alignment
        enum VAlign
        {
            TOP, CENTER, BOTTOM
        }

        // Get
        @property TextArea text() { return m_text; }
        @property RGBA textColor() const { return m_textColor; }
        @property RGBA textBgColor() const { return m_textBgColor; }

        // Set
        @property void editable(bool v) { m_editable = v; }
        @property void textColor(RGBA v) { m_textColor = v; }
        @property void textBgColor(RGBA v) { m_textBgColor = v; }
        @property void halign(HAlign v) { m_hAlign = v; }
        @property void valign(VAlign v) { m_vAlign = v; }

        @property void text(string v)
        {
            m_text.set(v);
            if (m_allowVScroll)
                m_vscroll.current = 0;
            m_refreshCache = true;
            needRender();
        }

        void write(T...)(T args)
        {
            string s;
            foreach(arg; args)
            s ~= to!string(arg);

            m_text.insert(s);
            m_refreshCache = true;
            needRender();
        }

        void writeln(T...)(T args)
        {
            write(args, "\n");
        }

        PrioritySignal!(Widget, KEY)  widgetTextInsertEvent;
        PrioritySignal!(Widget, char) widgetTextDeleteEvent;
        PrioritySignal!(Widget)       widgetTextReturnEvent;

    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }


    public:

        void set(KeyVal...)(Font font, KeyVal args)
        {
            super.set(args);

            m_type = "WIDGETTEXT";
            m_cacheId = glGenLists(1);
            m_text = new TextArea;

            m_font = font;
            m_repeatDelayTime = -1;
            m_repeatHoldTime = -1;
            m_caretBlinkDelay = -1;

            // Scroll bar options
            RGBA scrollBg = RGBA(0,0,0,1);
            RGBA scrollFg = RGBA(1,1,1,1);
            RGBA scrollBd = RGBA(0,0,0,1);
            bool scrollFade = true;
            int scrollCr = 0;

            foreach(arg; unpack(args))
            {
                switch(arg.key.toLower)
                {
                    case "textcolor":
                        m_textColor = arg.get!RGBA(m_type);
                        break;

                    case "textbackground":
                        m_textBgColor = arg.get!RGBA(m_type);
                        break;

                    case "editable":
                        m_editable= arg.get!bool(m_type);
                        break;

                    case "vscroll":
                        m_allowVScroll= arg.get!bool(m_type);
                        break;

                    case "hscroll":
                        m_allowHScroll= arg.get!bool(m_type);
                        break;

                    case "repeatdelay":
                        m_repeatDelayTime = arg.get!int(m_type);
                        break;

                    case "repeathold":
                        m_repeatHoldTime = arg.get!int(m_type);
                        break;

                    case "caretblinkdelay":
                        m_caretBlinkDelay = arg.get!int(m_type);
                        break;

                    case "valign":
                    case "verticalalign":
                        m_vAlign = arg.get!VAlign(m_type);
                        break;

                    case "halign":
                    case "horizontalalign":
                        m_hAlign = arg.get!HAlign(m_type);
                        break;

                    case "scrollbackground":
                        scrollBg = arg.get!RGBA(m_type);
                        break;

                    case "scrollcolor":
                        scrollFg = arg.get!RGBA(m_type);
                        break;

                    case "scrollborder":
                        scrollBd = arg.get!RGBA(m_type);
                        break;

                    case "scrollfade":
                        scrollFade = arg.get!bool(m_type);
                        break;

                    case "scrollcornerradius":
                        scrollCr = arg.get!int(m_type);
                        break;

                    default:
                }
            }

            // Set some reasonable defaults
            if (m_repeatDelayTime == -1) m_repeatDelayTime = 20;
            if (m_repeatHoldTime == -1)  m_repeatHoldTime = 500;
            if (m_caretBlinkDelay == -1) m_caretBlinkDelay = 400;

            // Request recurrent timer event from root for blinking the caret
            if (m_editable) requestTimer(m_caretBlinkDelay, &this.timerEvent, true);

            // Make scroll bars
            if (m_allowVScroll)
            {
                m_vscroll = m_root.create!WidgetScroll(this,
                                    arg("dim", [20, m_dim.y - 20]),
                                    arg("range", [0,1000]),
                                    arg("fade", scrollFade),
                                    arg("slidercolor", scrollFg),
                                    arg("sliderborder", scrollBd),
                                    arg("background", scrollBg),
                                    arg("cornerRadius", scrollCr),
                                    arg("orientation", Orientation.VERTICAL));
            }

            if (m_allowHScroll)
            {
                m_hscroll = m_root.create!WidgetScroll(this,
                                    arg("dim", [20, m_dim.y - 20]),
                                    arg("range", [0,1000]),
                                    arg("fade", scrollFade),
                                    arg("slidercolor", scrollFg),
                                    arg("sliderborder", scrollBd),
                                    arg("background", scrollBg),
                                    arg("cornerRadius", scrollCr),
                                    arg("orientation", Orientation.HORIZONTAL));
            }
        }

        // Geometry has changed, so update scroll bars
        override void geometryChanged(Widget.GeometryChangeFlag flag)
        {
            super.geometryChanged(flag);

            // Only need to update slider positions if size has changed
            if (flag & Widget.GeometryChangeFlag.DIMENSION)
            {
                if (m_allowVScroll)
                {
                    m_vscroll.setPos(m_dim.x-17, 1);
                    m_vscroll.setDim(16, m_dim.y-17);
                }

                if (m_allowHScroll)
                {
                    m_hscroll.setPos(1, m_dim.y-17);
                    m_hscroll.setDim(m_dim.x-17, 16);
                }
            }
        }

        // Timer event is used to turn on/off the caret
        void timerEvent(long delay)
        {
            // If this is the caret timer, toggle caretDraw flag, and call render
            if (delay == m_caretBlinkDelay)
            {
                m_drawCaret = !m_drawCaret;
                needRender();
            }
        }

        override void render()
        {
            super.render();

            if (m_font is null)
                return;

            setCoords();
            glPushMatrix();
            glScalef(1,-1,1);
            glPushMatrix();

            long before = timerMsecs;
            if (!m_refreshCache)
            {
                glCallList(m_cacheId);
            }
            else
            {
                // Text has not been cached, so cache and draw it
                glNewList(m_cacheId, GL_COMPILE_AND_EXECUTE);
                renderCharacters(m_font, m_text.text, m_textColor);
                glEndList();
                m_refreshCache = false;
            }
            //std.stdio.writeln("Render: ", cast(float)(timerMsecs - before)/m_text.text.length);

            glPopMatrix();
            glPopMatrix();

            if (m_editable && m_drawCaret && (amIFocused || isAChildFocused) )
                renderCaret();
        }

        // Draw the caret
        void renderCaret()
        {
            glPushMatrix();
                glLoadIdentity();
                glTranslatef(m_parent.screenPos.x, m_parent.screenPos.y, 0);
                setCoords();
                glTranslatef(m_caretPos[0], m_caretPos[1], 0);
                glScalef(1,-1,1);
                glColor4f(1.,1.,1.,1);
                glBegin(GL_QUADS);
                    glVertex2f(0,0);
                    glVertex2f(0,m_font.m_maxHeight);
                    glVertex2f(2,m_font.m_maxHeight);
                    glVertex2f(2,0);
                glEnd();
            glPopMatrix();
        }

        // Setup draw coords
        void setCoords()
        {
            // Calculate vertical offset, depends on alignment
            float yoffset = 0;
            final switch(m_vAlign) with(VAlign)
            {
                case CENTER:
                {
                    auto lines = split(m_text.text, "\n").length;
                    auto height = lines * m_font.m_lineHeight;
                    yoffset = m_dim.y/2.0f + m_font.m_maxHoss/2.0f - height/2.0f - m_font.m_lineHeight/2.0f;

                    if (yoffset < 0) yoffset = 0;
                    break;
                }
                case BOTTOM:
                {
                    auto lines = split(m_text.text, "\n").length;
                    auto height = lines * m_font.m_lineHeight;
                    yoffset = (cast(float)m_dim.y - height)/2;
                    if (yoffset < 0) yoffset = 0;
                    break;
                }
                case TOP:
                {
                    yoffset = 0;
                    break;
                }
            }

            glTranslatef(m_pos.x + 5, m_pos.y + yoffset + m_font.m_lineHeight, 0);

            // Translate by the scroll amounts as well...
            if (m_allowHScroll)
                glTranslatef(-m_hscroll.current*m_font.m_maxWidth, 0, 0);
            if (m_allowVScroll)
                glTranslatef(0, -2*m_vscroll.current*m_font.m_lineHeight, 0);
        }

        // Dispatch events
        override void event(ref Event event)
        {
            if (!amIFocused && !isAChildFocused) return;

            switch(event.type) with(EventType)
            {
                case KEYRELEASE:
                {
                    m_repeating = false;
                    m_holding = false;
                    m_repeatTimer.stop();
                    m_repeatTimer.reset();
                    break;
                }
                case KEYHOLD:
                {
                    KEY key;
                    if (needToProcessKey(event, key))
                        handleKey(key);
                    break;
                }
                case KEYPRESS:
                {
                    handleKey(event.get!KeyPress.key);
                    break;
                }
                default: break;
            }
        } // event

        // Key repeat delay logic
        bool needToProcessKey(ref Event event, out KEY key)
        {
            if (event.type == EventType.KEYHOLD)
            {
                if (!m_holding && !m_repeating)
                {
                    m_holding = true;
                    m_repeatTimer.reset();
                    m_repeatTimer.start();
                    return false;
                }

                double elapsed = m_repeatTimer.peek().msecs;

                if (m_repeating)
                {
                    if (elapsed < m_repeatDelayTime)
                    {
                        return false;
                    }
                    else
                    {
                        m_repeatTimer.reset();
                        m_repeatTimer.start();
                    }
                }
                else
                {
                    if (elapsed < m_repeatHoldTime)
                    {
                        return false;
                    }
                    else
                    {
                        m_holding = false;
                        m_repeating = true;
                        m_repeatTimer.reset();
                        m_repeatTimer.start();
                        return false;
                    }
                }
            } /// if KEY_HELD

            key = m_lastKey;
            return true;
        }

        // Handle key events
        void handleKey(in KEY key)
        {
            m_lastKey = key;

            switch(cast(uint)key) with (KEY)
            {
                case KC_HOME: // home key
                {
                    m_text.home();
                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_END: // end key
                {
                    m_text.end();
                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_LEFT: // left arrow
                {
                    m_text.moveLeft();
                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_RIGHT: // right arrow
                {
                    m_text.moveRight();
                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_UP: // up arrow
                {
                    m_text.moveUp();
                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_DOWN: // down arrow
                {
                    m_text.moveDown();
                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_DELETE: // del
                {
                    char deleted = m_text.rightText();
                    m_text.del();
                    widgetTextDeleteEvent.emit(this, deleted);
                    m_drawCaret = true;
                    m_refreshCache = true;
                    needRender();
                    break;
                }
                case KC_RETURN: // Carriage return
                {
                    if (m_editable)
                    {
                        m_text.insert("\n");
                        widgetTextReturnEvent.emit(this);
                        m_drawCaret = true;
                        m_refreshCache = true;
                        needRender();
                    }
                    break;
                }
                case KC_BACKSPACE: // backspace
                {
                    if (m_editable)
                    {
                        char deleted = m_text.leftText();
                        m_text.backspace();
                        widgetTextDeleteEvent.emit(this, deleted);
                        m_drawCaret = true;
                        m_refreshCache = true;
                        needRender();
                    }
                    break;
                }
                case 32:..case 126: // printables
                {
                    if (m_editable)
                    {
                        m_text.insert(to!string(cast(char)key));
                        widgetTextInsertEvent.emit(this, key);
                        m_drawCaret = true;
                        m_refreshCache = true;
                        needRender();
                    }

                    break;
                }

                default:
            }

            m_caretPos = m_text.getCaretPosition(m_font);

        } // handleKey


    private:

        KEY m_lastKey = KEY.KC_NULL;

        Font m_font = null;
        TextArea m_text;
        RGBA m_textColor = {1,1,1,1};
        RGBA m_textBgColor = {0,0,0,0};

        bool m_allowVScroll = false;
        bool m_allowHScroll = false;
        WidgetScroll m_vscroll;
        WidgetScroll m_hscroll;

        long m_caretBlinkDelay;
        bool m_drawCaret;
        float[2] m_caretPos = [0,0];

        HAlign m_hAlign = HAlign.LEFT;
        VAlign m_vAlign = VAlign.TOP;

        StopWatch m_repeatTimer;
        bool m_repeating = false;
        bool m_holding = false;
        long m_repeatHoldTime;
        long m_repeatDelayTime;

        bool m_editable = true; // can the text be edited?

        GLuint m_cacheId = 0; // display list for caching
        bool m_refreshCache = true;
}


// Convenience class for static text
class WidgetLabel : WidgetText
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:
        void set(KeyVals...)(Font font, KeyVals args)
        {
            super.set(font, args);
            m_type = "WIDGETLABEL";

            // Alignment is vertically centered by default:
            m_vAlign = WidgetText.VAlign.CENTER;
            m_editable = false;

            int[2] dims = [0,0];
            bool fixedWidth = false, fixedHeight = false;

            foreach(arg; unpack(args))
            {
                switch(arg.key.toLower)
                {
                    case "fixeddims":
                        fixedWidth = arg.get!bool(m_type);
                        fixedHeight = arg.get!bool(m_type);
                        break;

                    case "fixedwidth":
                        fixedWidth = arg.get!bool(m_type);
                        break;

                    case "fixedheigth":
                        fixedHeight = arg.get!bool(m_type);
                        break;

                    case "text":
                        auto s = arg.get!string(m_type);
                        m_text.set(s);

                        // Set default dimensions
                        auto lines = split(s, "\n");
                        float xdim = 0;
                        foreach(line; lines)
                        {
                            auto l = 1.2*getLineLength(line, m_font);
                            if (l > xdim)
                                xdim = l;
                        }

                        dims = [cast(int)xdim,
                                cast(int)(1.5*lines.length*m_font.m_lineHeight)];

                        break;

                    default:
                }
            }

            if (fixedWidth) dims.x = m_dim.x;
            if (fixedHeight) dims.y = m_dim.y;
            setDim(dims.x, dims.y);
        }
}


// Handles text storage and manipulation for WidgetText
class TextArea
{
    public:

        @property uint col() const { return m_column; }
        @property uint row() const { return m_row; }

        @property string text() { return m_text; }
        @property uint offset() { return m_offset; }

        // Get the character to the left of the current cursor/offset
        @property char leftText()
        {
            if (m_offset <= 0)
                return cast(char)0;

            return m_text[m_offset-1];
        }

        @property char rightText()
        {
            if (m_offset + 1 > m_text.length)
                return cast(char)0;

            return m_text[m_offset+1];
        }

        void set(string s)
        {
            m_text.clear;
            m_offset = 0;
            insert(s);
        }

        void insert(string s)
        {
            // TODO: the column and row changes don't correctly account for
            // insertions which contain carriage returns

            insertInPlace(m_text, m_offset, s);
            m_offset += s.length;

            if (s.length == 1 && s[0] == '\n')
            {
                m_column = 0;
                m_row++;
            }
            else
            {
                m_column += s.length;
                m_seekColumn = m_column;
            }
        }

        void backspace()
        {
            if (m_offset > 0)
            {
                deleteSelection(m_offset-1, m_offset-1);
                moveLeft();
            }
        }

        void del()
        {
            if (m_offset < m_text.length)
            {
                deleteSelection(m_offset, m_offset);
            }
        }

        void deleteSelection(size_t from, size_t to)
        {
            m_text = m_text[0..from] ~ m_text[to+1..$];
        }

        void moveLeft(bool seeking = false)
        {
            if (m_offset > 0)
            {
                m_offset --;
                if (m_column == 0)
                {
                    // Go up a line
                    m_column = countToStartOfLine();
                    m_row --;
                }
                else
                {
                    m_column --;
                }
            }

            if (!seeking)
                m_seekColumn = m_column;
        }

        void moveRight(bool seeking = false)
        {
            if (m_offset < m_text.length)
            {
                if (m_text[m_offset] == '\n')
                {
                    // Go down a line
                    m_column = 0;
                    m_row ++;
                }
                else
                {
                    m_column ++;
                }
                m_offset ++;
            }

            if (!seeking)
                m_seekColumn = m_column;
        }

        void moveUp()
        {
            uint preMoveOffset = m_offset, preMoveColumn = m_column;

            bool found = false;
            while(m_offset > 0)
            {
                moveLeft(true);
                if (m_column == m_seekColumn || (m_column == 0 && m_text[m_offset] == '\n'))
                {
                    found = true;
                    break;
                }
            }

            if  (m_offset == 0)
            {
                m_offset = preMoveOffset;
                m_column = preMoveColumn;
            }
        }

        void moveDown()
        {
            uint preMoveOffset = m_offset, preMoveColumn = m_column;

            bool found = false;
            while(m_offset < m_text.length)
            {
                moveRight(true);
                if (m_column == m_seekColumn || (m_column == 0 && m_text[m_offset] == '\n'))
                {
                    found = true;
                    break;
                }
            }

            if  (!found)
            {
                m_offset = preMoveOffset;
                m_column = preMoveColumn;
            }
        }

        void home() // home key
        {
            while (m_column != 0)
                moveLeft();
        }

        void end() // end key
        {
            if (m_offset == m_text.length)
                return;

            while(m_offset < m_text.length && m_text[m_offset] != '\n')
                moveRight();
        }

        uint countToStartOfLine()
        {
            if (m_offset == 0)
                return 0;

            int i = m_offset - 1, count = 0;

            if (m_text[i] == '\n')
                return 0;

            while (i >= 0 && m_text[i] != '\n')
            {
                i--;
                count ++;
            }
            return count;
        }

        uint countToEndOfLine()
        {
            uint i = m_offset, count = 0;
            while (i < m_text.length && m_text[i] != '\n')
            {
                i++;
                count++;
            }
            return count;
        }

        float[2] getCaretPosition(ref const(Font) font)
        {
            float[2] cpos = [0,0];
            foreach(i, char c; m_text)
            {
                if (i == m_offset)
                    break;

                if (c == '\n')
                {
                    cpos[0] = 0;
                    cpos[1] += font.m_lineHeight;
                }
                else
                {
                    cpos[0] += font.m_wids[(cast(uint)c) - 32];
                }
            }
            return cpos;
        }

        // Clear all text
        void clear()
        {
            m_text.clear;
            m_offset = 0;
            m_row = 0;
            m_column = 0;
            m_seekColumn = 0;
        }


    private:
        uint m_offset = 0;
        string m_text = "";

        // Current column and row of the caret (insertion point)
        uint m_column = 0;
        uint m_row = 0;

        // When moving up and down through carriage returns, try to get to this column
        uint m_seekColumn = 0;
}

