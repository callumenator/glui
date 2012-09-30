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
    std.algorithm,
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
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

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
        @property uint row() const { return m_text.row; }
        @property uint col() const { return m_text.col; }

        // Set
        @property void editable(bool v) { m_editable = v; }
        @property void textColor(RGBA v) { m_textColor = v; }
        @property void textBgColor(RGBA v) { m_textBgColor = v; }
        @property void halign(HAlign v) { m_hAlign = v; }
        @property void valign(VAlign v) { m_vAlign = v; }

        @property void highlighter(SyntaxHighlighter v)
        {
            m_highlighter = v;
            m_refreshCache = true;
            needRender();
        }

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

        void addLineHighlight(int line, RGBA color)
        {
            m_lineHighlights[line] = color;
        }

        void removeLineHighlight(int line)
        {
            m_lineHighlights.remove(line);
        }

        /**
        * x and y are absolute screen coords
        */
        int[2] getRowCol(int x, int y)
        {
            auto relx = x - m_screenPos.x - 5;
            if (m_allowHScroll)
                relx += m_hscroll.current * m_font.m_maxWidth;

            auto rely = y - m_screenPos.y - textOffsetY() - m_font.m_lineHeight/2;
            if (m_allowVScroll)
                rely += m_vscroll.current * m_font.m_lineHeight;

            if (relx < 0 || rely < 0)
                return [0,0];

            return m_text.getRowCol(m_font, relx, rely);
        }

        uint getOffset(int x, int y)
        {
            auto relx = x - m_screenPos.x - 5;
            if (m_allowHScroll)
                relx += m_hscroll.current * m_font.m_maxWidth;

            auto rely = y - m_screenPos.y - textOffsetY() - m_font.m_lineHeight/2;
            if (m_allowVScroll)
                rely += m_vscroll.current * m_font.m_lineHeight;

            if (relx < 0 || rely < 0)
                return 0;

            return m_text.getOffset(m_font, relx, rely);
        }

        void set(Font font, WidgetArgs args)
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
            int scrollCr = 0, scrollTh = 10;

            fill(args, arg("textcolor", m_textColor),
                       arg("textbackground", m_textBgColor),
                       arg("editable", m_editable),
                       arg("vscroll", m_allowVScroll),
                       arg("hscroll", m_allowHScroll),
                       arg("repeatdelay", m_repeatDelayTime),
                       arg("repeathold", m_repeatHoldTime),
                       arg("caretblinkdelay", m_caretBlinkDelay),
                       arg("valign", m_vAlign),
                       arg("halign", m_hAlign),
                       arg("highlighter", m_highlighter),
                       arg("scrollbackground", scrollBg),
                       arg("scrollforeground", scrollFg),
                       arg("scrollborder", scrollBd),
                       arg("scrollfade", scrollFade),
                       arg("scrollcornerradius", scrollCr),
                       arg("scrollthick", scrollTh));

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
                                    widgetArgs(
                                    "pos", [m_dim.x - scrollTh, 0],
                                    "dim", [scrollTh, m_dim.y - scrollTh],
                                    "range", [0,1000],
                                    "fade", scrollFade,
                                    "slidercolor", scrollFg,
                                    "sliderborder", scrollBd,
                                    "background", scrollBg,
                                    "cornerRadius", scrollCr,
                                    "orientation", Orientation.VERTICAL));
            }

            if (m_allowHScroll)
            {
                m_hscroll = m_root.create!WidgetScroll(this,
                                    widgetArgs(
                                    "pos", [m_dim.x - scrollTh, 0],
                                    "dim", [scrollTh, m_dim.y - scrollTh],
                                    "range", [0,1000],
                                    "fade", scrollFade,
                                    "slidercolor", scrollFg,
                                    "sliderborder", scrollBd,
                                    "background", scrollBg,
                                    "cornerRadius", scrollCr,
                                    "orientation", Orientation.HORIZONTAL));
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

        override void render(Flag!"RenderChildren" recurse = Flag!"RenderChildren".yes)
        {
            super.render(Flag!"RenderChildren".no);

            if (m_font is null)
                return;

            glPushMatrix();
            setCoords();
            glScalef(1,-1,1);

            if (!m_refreshCache)
            {
                glCallList(m_cacheId);
            }
            else
            {
                // Text has not been cached, so cache and draw it
                glNewList(m_cacheId, GL_COMPILE_AND_EXECUTE);

                auto clip = m_clip;
                clip[0] += 1;
                clip[1] += 1;
                clip[2] -= 2;
                clip[3] -= 2;
                clipboxToScreen(clip);
                glScissor(clip[0], clip[1], clip[2], clip[3]);

                // Handle line highlights
                uint width;
                if (m_allowHScroll)
                {
                    auto rnge = m_hscroll.range;
                    width = m_dim.x + rnge[1]*m_font.m_maxWidth;
                }
                else
                    width = m_dim.x;

                foreach(line, color; m_lineHighlights)
                {
                    glColor4fv(color.ptr);
                    glBegin(GL_QUADS);
                    glVertex2f(-5, -line*m_font.m_lineHeight - m_font.m_maxHoss);
                    glVertex2f(width, -line*m_font.m_lineHeight - m_font.m_maxHoss);
                    glVertex2f(width, -line*m_font.m_lineHeight + m_font.m_maxHeight);
                    glVertex2f(-5, -line*m_font.m_lineHeight + m_font.m_maxHeight);
                    glEnd();
                }

                if (haveSelection)
                {
                    auto lower = min(m_selectionRange[0], m_selectionRange[1]);
                    auto upper = max(m_selectionRange[0], m_selectionRange[1]);

                    auto pre = m_text.text[0..lower];
                    auto mid= m_text.text[lower..upper];
                    auto post = m_text.text[upper..$];

                    if (m_highlighter)
                    {
                        int[2] offset;
                        offset = renderCharacters(m_font, pre, m_highlighter);
                        offset = renderCharacters(m_font, mid, m_highlighter, [0.,0.,1.,1.], offset);
                        offset = renderCharacters(m_font, post, m_highlighter, [0.,0.,0.,0.], offset);
                    }
                    else
                    {
                        int[2] offset;
                        offset = renderCharacters(m_font, pre, m_textColor);
                        offset = renderCharacters(m_font, mid, m_textColor, [0.,0.,1.,1.], offset);
                        offset = renderCharacters(m_font, post, m_textColor, [0.,0.,0.,0.], offset);
                    }

                }
                else
                {
                    if (m_highlighter)
                        renderCharacters(m_font, m_text.text, m_highlighter);
                    else
                        renderCharacters(m_font, m_text.text, m_textColor);
                }

                glEndList();
                m_refreshCache = false;
            }

            glPopMatrix();

            if (m_editable && m_drawCaret && (amIFocused || isAChildFocused) )
                renderCaret();

            if (recurse)
                renderChildren();
        }

        // Draw the caret
        void renderCaret()
        {
            glPushMatrix();
                glLoadIdentity();
                glTranslatef(m_parent.screenPos.x + m_pos.x, m_parent.screenPos.y + m_pos.y, 0);
                setCoords();
                glTranslatef(m_caretPos[0], m_caretPos[1], 0);
                glScalef(1,-1,1);
                glColor4fv(m_textColor.ptr);
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
            resetXCoord();
            resetYCoord();
        }

        void resetXCoord()
        {
            glTranslatef(0*m_pos.x + 5, 0, 0);
            // Translate by the scroll amounts as well...
            if (m_allowHScroll)
                glTranslatef(-m_hscroll.current*m_font.m_maxWidth, 0, 0);
        }

        void resetYCoord()
        {
            glTranslatef(0, 0*m_pos.y + textOffsetY() + m_font.m_lineHeight, 0);

            // Translate by the scroll amounts as well...
            if (m_allowVScroll)
                glTranslatef(0, -m_vscroll.current*m_font.m_lineHeight, 0);
        }

        int textOffsetY()
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
            return cast(int)yoffset;
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
                case MOUSECLICK:
                {
                    auto preOffset = m_text.offset;
                    auto pos = event.get!MouseClick.pos;
                    auto rc = getRowCol(pos.x, pos.y);

                    m_text.moveCaret(rc.x, rc.y);

                    std.stdio.writeln(m_selectionRange);

                    if (root.shiftIsDown)
                    {
                        if (m_selectionRange[0] == m_selectionRange[1])
                        {
                            clearSelection();
                            m_selectionRange[0] = preOffset;
                        }

                        updateSelectionRange();
                    }
                    else
                    {
                        clearSelection();
                    }

                    m_caretPos = m_text.getCaretPosition(m_font);
                    m_drawCaret = true;
                    needRender();
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

                    if (root.shiftIsDown)
                        updateSelectionRange();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_END: // end key
                {
                    m_text.end();

                    if (root.shiftIsDown)
                        updateSelectionRange();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_LEFT: // left arrow
                {
                    if (root.ctrlIsDown)
                        m_text.jumpLeft();
                    else
                        m_text.moveLeft();

                    if (root.shiftIsDown)
                        updateSelectionRange();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_RIGHT: // right arrow
                {
                    if (root.ctrlIsDown)
                        m_text.jumpRight();
                    else
                        m_text.moveRight();

                    if (root.shiftIsDown)
                        updateSelectionRange();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_UP: // up arrow
                {
                    m_text.moveUp();

                    if (root.shiftIsDown)
                        updateSelectionRange();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_DOWN: // down arrow
                {
                    m_text.moveDown();

                    if (root.shiftIsDown)
                        updateSelectionRange();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_TAB: // down arrow
                {
                    string tab = '\t'.to!string;
                    m_text.insert(tab);
                    eventSignal.emit(this, WidgetEvent(TextInsert(tab)));
                    m_drawCaret = true;
                    m_refreshCache = true;
                    needRender();
                    break;
                }
                case KC_DELETE: // del
                {
                    char deleted = m_text.rightText();
                    m_text.del();
                    eventSignal.emit(this, WidgetEvent(TextRemove(deleted.to!string)));
                    m_drawCaret = true;
                    m_refreshCache = true;
                    needRender();
                    break;
                }
                case KC_SHIFT_LEFT:
                case KC_SHIFT_RIGHT:
                {
                    if (!haveSelection())
                        m_selectionRange[] = [m_text.offset, m_text.offset];

                    break;
                }
                case KC_RETURN: // Carriage return
                {
                    if (m_editable)
                    {
                        // If current line is indented (has tabs) replicate for this line
                        auto line = m_text.getCurrentLine();

                        m_text.insert("\n");
                        eventSignal.emit(this, WidgetEvent(TextReturn()));

                        foreach(char c; line)
                        {
                            if (c == '\t')
                                m_text.insert('\t');
                            else
                                break;
                        }

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
                        eventSignal.emit(this, WidgetEvent(TextRemove(deleted.to!string)));
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
                        m_text.insert(cast(char)key);
                        eventSignal.emit(this, WidgetEvent(TextInsert(to!string(cast(char)key))));
                        m_drawCaret = true;
                        m_refreshCache = true;
                        needRender();
                    }

                    break;
                }

                default:
            }

            if (!root.shiftIsDown)
            {
                clearSelection();
                m_refreshCache = true;
                needRender();
            }

            adjustVisiblePortion();
        } // handleKey


        /**
        * Update the visible portion of the text, to make the caret visible
        */
        void adjustVisiblePortion()
        {
            m_caretPos = m_text.getCaretPosition(m_font);

            // If text insert moves caret off screen horizontally, adjust hscroll
            if (m_allowHScroll)
            {
                auto minCol = m_hscroll.current;
                auto maxCol = minCol + ((m_dim.x - 5) / m_font.m_maxWidth);
                if (m_text.col > maxCol)
                    m_hscroll.current = m_hscroll.current + (m_text.col - maxCol)*5;
                else if (m_text.col < minCol)
                    m_hscroll.current = m_text.col;
            }
            // If text insert moves caret off screen vertically, adjust vscroll
            if (m_allowVScroll)
            {
                auto minRow = m_vscroll.current;
                auto maxRow = minRow + (m_dim.y / m_font.m_lineHeight) - 1;
                if (m_text.row > maxRow)
                    m_vscroll.current = m_vscroll.current + (m_text.row - maxRow);
                else if (m_text.row < minRow)
                    m_vscroll.current = m_text.row;
            }
        }

        override bool requestDrag(int[2] pos)
        {
            m_pendingDrag = true;
            return true;
        }

        override void drag(int[2] pos, int[2] delta)
        {
            auto offset = getOffset(pos.x, pos.y);

            if (m_pendingDrag)
            {
                m_selectionRange[] = [offset, offset];
                m_pendingDrag = false;
            }
            else
            {
                m_selectionRange[1] = offset;
                m_refreshCache = true;
                needRender();
            }
        }

        void updateSelectionRange()
        {
            m_selectionRange[1] = m_text.offset;
            m_refreshCache = true;
        }

        void clearSelection()
        {
            m_selectionRange[] = [0,0];
            m_refreshCache = true;
        }

        bool haveSelection()
        {
            return m_selectionRange[0] != m_selectionRange[1];
        }

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
        int[2] m_caretPos = [0,0];

        HAlign m_hAlign = HAlign.LEFT;
        VAlign m_vAlign = VAlign.TOP;

        StopWatch m_repeatTimer;
        bool m_repeating = false;
        bool m_holding = false;
        long m_repeatHoldTime;
        long m_repeatDelayTime;

        bool m_editable = true; // can the text be edited?

        SyntaxHighlighter m_highlighter = null; // add in a syntax highlighter

        GLuint m_cacheId = 0; // display list for caching
        bool m_refreshCache = true;

        RGBA[int] m_lineHighlights;

        bool m_pendingDrag = false;
        uint[2] m_selectionRange;
}


// Convenience class for static text
class WidgetLabel : WidgetText
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:
        void set(Font font, WidgetArgs args)
        {
            super.set(font, args);
            m_type = "WIDGETLABEL";

            // Alignment is vertically centered by default:
            m_vAlign = WidgetText.VAlign.CENTER;
            m_editable = false;

            int[2] dims = [0,0];
            bool fixedWidth = false, fixedHeight = false;

            fill(args, arg("fixedwidth", fixedWidth),
                       arg("fixedheight", fixedHeight));

            if ("fixeddims" in args)
            {
                auto v = ("fixeddims" in args).get!bool;
                fixedWidth = v;
                fixedHeight = v;
            }

            if ("text" in args)
            {
                auto s = ("text" in args).get!string;
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
            if (cast(int)(m_offset) > cast(int)(m_text.length - 1))
                return cast(char)0;

            return m_text[m_offset];
        }

        void set(string s)
        {
            m_text.clear;
            m_offset = 0;
            insert(s);
        }

        void insert(char c)
        {
            insert(c.to!string);
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

        /**
        * Move left to next character
        */
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


        /**
        * Jump left to next word
        */
        void jumpLeft()
        {
            if (col == 0)
                return;

            while(col > 0 && m_offset > 0 && isBlank(leftText))
                moveLeft();

            while(col > 0 && m_offset > 0 && !isBlank(leftText))
                moveLeft();
        }

        /**
        * Move right to next character
        */
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

        /**
        * Jump right to next word
        */
        void jumpRight()
        {
            auto endCol = col + countToEndOfLine();

            if (isBlank(rightText))
            {
                while(col < endCol && m_offset < m_text.length && isBlank(rightText))
                    moveRight();
            }
            else
            {
                while(col < endCol && m_offset < m_text.length && !isBlank(rightText))
                    moveRight();

                while(col < endCol && m_offset < m_text.length && isBlank(rightText))
                    moveRight();
            }
        }

        void moveUp()
        {
            uint preMoveRow = m_row,
                 preMoveColumn = m_column,
                 preMoveOffset = m_offset;

            bool found = false;
            while(m_offset > 0)
            {
                moveLeft(true);
                if (m_column == m_seekColumn ||
                    m_column < m_seekColumn && countToEndOfLine() == 0 && m_row == preMoveRow - 1 ||
                    (m_column == 0 && m_text[m_offset] == '\n'))
                {
                    found = true;
                    break;
                }
            }

            if  (!found)
            {
                m_offset = preMoveOffset;
                m_column = preMoveColumn;
                m_row = preMoveRow;
            }
        }

        void moveDown()
        {
            uint preMoveRow = m_row,
                 preMoveColumn = m_column,
                 preMoveOffset = m_offset;

            bool found = false;
            while(m_offset < m_text.length)
            {
                moveRight(true);
                if (m_column == m_seekColumn ||
                    m_column < m_seekColumn && countToEndOfLine() == 0 && m_row == preMoveRow + 1 ||
                    (m_column == 0 && m_text[m_offset] == '\n'))
                {
                    found = true;
                    break;
                }
            }

            if  (!found)
            {
                m_offset = preMoveOffset;
                m_column = preMoveColumn;
                m_row = preMoveRow;
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
                count ++;
            }
            return count;
        }

        string getLine(uint _row)
        {
            auto lines = splitLines(m_text);
            if (_row < lines.length)
                return lines[_row];
            else
                return "";
        }

        string getCurrentLine()
        {
            return getLine(row);
        }

        int[2] getCaretPosition(ref const(Font) font)
        {
            int[2] cpos = [0,0];
            foreach(i, char c; m_text)
            {
                if (i == m_offset)
                    break;

                if (c == '\n')
                {
                    cpos[0] = 0;
                    cpos[1] += font.m_lineHeight;
                }
                else if (c == '\t')
                {
                    cpos[0] += tabSpaces*font.m_wids[(cast(uint)' ') - 32];
                }
                else
                {
                    cpos[0] += font.m_wids[(cast(uint)c) - 32];
                }
            }
            return cpos;
        }

        /**
        * Return the row, col at screen position x, y relative to lower
        * left corner of first character. Returned row and col are always
        * inside the available text.
        */
        int[2] getRowCol(ref const(Font) font, int x, int y)
        {
            int[2] cpos = [0,0];

            if (m_text.length == 0)
                return cpos;

            // y is determined solely by font.m_lineHeight
            cpos[0] = cast(int) (y / font.m_lineHeight);

            auto lines = splitLines(m_text);
            if (cpos[0] > lines.length - 1)
                cpos[0] = lines.length - 1;

            float _x = 0;
            foreach(char c; lines[cpos[0]])
            {
                if (_x > x)
                    break;

                if (c == '\t')
                    _x += tabSpaces*font.m_wids[(cast(uint)' ') - 32];
                else
                    _x += font.m_wids[(cast(uint)c) - 32];

                cpos[1] ++;
            }
            return cpos;
        }

        /**
        * Return the 1-D text offset at screen position x, y relative to lower
        * left corner of first character. Returned offset is always
        * inside the available text.
        */
        uint getOffset(ref const(Font) font, int x, int y)
        {
            uint offset = 0;

            if (m_text.length == 0)
                return offset;

            auto rc = getRowCol(font, x, y);

            int _row, _col;

            while(_row != rc[0] || _col != rc[1])
            {
                if (m_text[offset] == '\n')
                {
                    _row += 1;
                    _col = 0;
                }
                else
                    _col ++;

                offset ++;
            }
            return offset;
        }

        void moveCaret(uint newRow, uint newCol)
        {
            if (newRow == row && newCol == col)
                return;

            if (newRow > row || (newRow == row && newCol > col))
            {
                while(m_offset < m_text.length && (row != newRow || col != newCol))
                    moveRight();
            }
            else
            {
                while(m_offset > 0 && (row != newRow || col != newCol))
                    moveLeft();
            }
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

        bool isBlank(char c)
        {
            return c == ' ' ||
                   c == '\t';
        }

        uint m_offset = 0;
        string m_text = "";

        // Default number of spaces for a tab
        uint tabSpaces = 4;

        // Current column and row of the caret (insertion point)
        uint m_column = 0;
        uint m_row = 0;

        // When moving up and down through carriage returns, try to get to this column
        uint m_seekColumn = 0;
}

