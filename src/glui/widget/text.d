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
    std.stdio,
    std.range,
    std.container,
    std.ascii,
    std.c.string,
    std.algorithm,
    std.array,
    std.conv,
    std.string,
    std.datetime,
    std.typetuple;

import
    derelict.opengl.gl;

import
    glui.truetype,
    glui.widget.base;


version(Windows)
{
    import core.sys.windows.windows;

    extern(Windows)
    {
        HGLOBAL GlobalAlloc(UINT uFlags, SIZE_T dwBytes);
        LPVOID GlobalLock(HGLOBAL hMem);
        BOOL GlobalUnlock(HGLOBAL hMem);
        BOOL OpenClipboard(HWND hWndNewOwner);
        BOOL EmptyClipboard();
        HANDLE SetClipboardData(UINT uFormat, HANDLE hMem);
        HANDLE GetClipboardData(UINT uFormat);
        BOOL CloseClipboard();
    }
}

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
        @property TextArea2 text() { return m_text; }
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
            m_refreshCache = true;
            needRender();
        }

        void removeLineHighlight(int line)
        {
            m_lineHighlights.remove(line);
            m_refreshCache = true;
            needRender();
        }

        void removeAllLineHighlights()
        {
            m_lineHighlights.clear;
            m_refreshCache = true;
            needRender();
        }

        /**
        * x and y are absolute screen coords
        */
        TextArea2.Location getLocation(int x, int y)
        {
            auto relx = x - m_screenPos.x - 5;
            if (m_allowHScroll)
                relx += m_hscroll.current * m_font.m_maxWidth;

            auto rely = y - m_screenPos.y - textOffsetY() - m_font.m_lineHeight/2;
            if (m_allowVScroll)
                rely += m_vscroll.current * m_font.m_lineHeight;

            if (relx < 0 || rely < 0)
                return TextArea2.Location();

            return m_text.getLocation(m_font, relx, rely);
        }

        void set(Font font, WidgetArgs args)
        {
            super.set(args);

            m_type = "WIDGETTEXT";
            m_cacheId = glGenLists(1);
            m_text = new TextArea2;

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
            if (m_caretBlinkDelay == -1) m_caretBlinkDelay = 600;

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

            debug
            {
                long perf_tick_in = Clock.currSystemTick().msecs();
            }

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
                    auto r = reduce!(min, max)(m_selectionRange);
                    auto lower = r[0];
                    auto upper = r[1];

                    auto pre = m_text.text[0..lower];
                    auto mid = m_text.text[lower..upper];
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

            debug
            {
                long perf_tick_diff = Clock.currSystemTick().msecs() - perf_tick_in;
                std.stdio.writeln("TEXT Render time: ", perf_tick_diff);
            }

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
                    auto rc = getLocation(pos.x, pos.y);

                    m_text.moveCaret(rc.row, rc.col);

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
                    else
                        clearSelection();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_END: // end key
                {
                    m_text.end();

                    if (root.shiftIsDown)
                        updateSelectionRange();
                    else
                        clearSelection();

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
                    else
                        clearSelection();

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
                    else
                        clearSelection();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_UP: // up arrow
                {
                    m_text.moveUp();

                    if (root.shiftIsDown)
                        updateSelectionRange();
                    else
                        clearSelection();

                    m_drawCaret = true;
                    needRender();
                    break;
                }
                case KC_DOWN: // down arrow
                {
                    m_text.moveDown();

                    if (root.shiftIsDown)
                        updateSelectionRange();
                    else
                        clearSelection();

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
                    if (!haveSelection())
                    {
                        auto deleted = m_text.rightText();
                        m_text.del();
                        eventSignal.emit(this, WidgetEvent(TextRemove(deleted.to!string)));
                    }
                    else
                    {
                        deleteSelectedText();
                    }

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
                        deleteSelectedText();

                        // If current line is indented (has tabs) replicate for the new line
                        auto cLine = m_text.getCurrentLine();
                        m_text.insert("\n");
                        foreach(char c; cLine)
                        {
                            if (c == '\t')
                                m_text.insert('\t');
                            else
                                break;
                        }

                        if (m_autoBraceIndent && strip(cLine) == "{") // If current line is a brace, check for auto indent
                            m_text.insert("\t");

                        m_drawCaret = true;
                        m_refreshCache = true;
                        needRender();

                        eventSignal.emit(this, WidgetEvent(TextInsert("\n")));
                    }
                    break;
                }
                case KC_BACKSPACE: // backspace
                {
                    if (m_editable)
                    {
                        if (haveSelection())
                            deleteSelectedText();
                        else
                        {
                            char deleted = m_text.leftText();
                            m_text.backspace();
                            eventSignal.emit(this, WidgetEvent(TextRemove(deleted.to!string)));
                        }
                        m_drawCaret = true;
                        m_refreshCache = true;
                        needRender();
                    }
                    break;
                }
                case 32:..case 126: // printables
                {
                    if (root.ctrlIsDown)
                    {
                        switch(key) with (KEY)
                        {
                            case KC_A: // select all
                            {
                                m_selectionRange[0] = 0;
                                m_text.gotoEndOfText();
                                updateSelectionRange();
                                break;
                            }
                            case KC_C: // copy selection to clipboard
                            {
                                copyToClipboard();
                                break;
                            }
                            case KC_V: // copy selection to clipboard
                            {
                                pasteFromClipboard();
                                break;
                            }
                            case KC_X: // copy selection to clipboard and delete selection
                            {
                                copyToClipboard();
                                deleteSelectedText();
                                break;
                            }

                            default: break;
                        }
                    }
                    else if (m_editable)
                    {
                        deleteSelectedText();

                        /++
                        if (key == KC_BRACERIGHT)
                        {
                            auto cLine = m_text.getCurrentLine();
                            if (m_autoBraceIndent && strip(cLine) == "}") // check for auto indent
                            {
                                auto loc = m_text.searchLeft('{');
                                if (m_text.leftText() == '\t')
                                    m_text.del();
                            }
                        }
                        ++/

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
            auto loc = getLocation(pos.x, pos.y);

            if (m_pendingDrag)
            {
                m_selectionRange[] = [loc.offset, loc.offset];
                m_pendingDrag = false;
            }
            else
            {
                m_selectionRange[1] = loc.offset;
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
            needRender();
        }

        bool haveSelection()
        {
            return m_selectionRange[0] != m_selectionRange[1];
        }

        void deleteSelectedText()
        {
            if (!haveSelection())
                return;

            auto r = reduce!(min, max)(m_selectionRange);
            auto deleted = m_text.text[r[0]..r[1]];
            m_text.remove(r[0], r[1]-1);
            eventSignal.emit(this, WidgetEvent(TextRemove(deleted)));
            clearSelection();
        }

        string getSelectedText()
        in
        {
            assert(haveSelection());
        }
        body
        {
            auto r = reduce!(min, max)(m_selectionRange);
            return m_text.text[r[0]..r[1]];
        }

        void copyToClipboard()
        {
            version(Windows)
            {
                if (!haveSelection())
                    return;

                if (OpenClipboard(null) && EmptyClipboard())
                {
                    string selection;
                    foreach(line; splitLines(getSelectedText()))
                        selection ~= line ~ '\r';

                    selection ~= '\0';

                    auto hnd = GlobalAlloc(0, selection.length);
                    char* pchData = cast(char*)GlobalLock(hnd);
                    strcpy(pchData, selection.ptr);
                    GlobalUnlock(hnd);
                    SetClipboardData(1 /** CF_TEXT **/, hnd);
                    CloseClipboard();
                }
            }
        }

        void pasteFromClipboard()
        {
            version(Windows)
            {
                if (OpenClipboard(null))
                {
                    scope(exit) { CloseClipboard(); }
                    auto hData = GetClipboardData(1 /** CF_TEXT **/);

                    char* buffer = cast(char*)GlobalLock(hData);
                    scope(exit) { GlobalUnlock(hData); }

                    uint bytes = 0;
                    auto buffPtr = buffer;
                    while(*(buffPtr++) != '\0')
                        bytes ++;

                    if (bytes == 0)
                        return;

                    char[] readin;
                    readin.length = bytes;
                    memcpy(readin.ptr, buffer, bytes);

                    string paste;
                    foreach(line; splitLines(readin))
                        paste ~= line ~ '\n';

                    m_text.insert(paste);
                    m_refreshCache = true;
                    needRender();
                }
            }
        }

    private:

        KEY m_lastKey = KEY.KC_NULL;

        Font m_font = null;
        TextArea2 m_text;
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

        bool m_autoBraceIndent = true;
}


// Convenience class for static text
class WidgetLabel : WidgetText
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:
        override void set(Font font, WidgetArgs args)
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

        struct Location { uint offset, row, col; }

        @property Location loc() const { return m_loc; } // current caret m_location
        @property uint col() const { return m_loc.col; } // current caret column
        @property uint row() const { return m_loc.row; } // current caret row
        @property uint offset() { return m_loc.offset; } // current caret 1-D offset
        @property string text() { return m_text; } // current text

        // Get the character to the left of the current cursor/offset
        @property char leftText()
        {
            if (m_loc.offset <= 0)
                return cast(char)0;

            return m_text[m_loc.offset-1];
        }

        @property char rightText()
        {
            if (cast(int)(m_loc.offset) > cast(int)(m_text.length - 1))
                return cast(char)0;

            return m_text[m_loc.offset];
        }

        void set(string s)
        {
            m_text.clear;
            m_loc.offset = 0;
            insert(s);
        }

        void insert(char c)
        {
            insert(c.to!string);
        }

        void insert(string s)
        {
            insertInPlace(m_text, m_loc.offset, s);

            foreach(i; 0..s.length)
                moveRight();
        }

        void backspace()
        {
            if (m_loc.offset > 0)
            {
                deleteSelection(m_loc.offset-1, m_loc.offset-1);
                moveLeft();
            }
        }

        void del()
        {
            if (m_loc.offset < m_text.length)
                deleteSelection(m_loc.offset, m_loc.offset);
        }

        void del(size_t from, size_t to)
        {
            deleteSelection(from, to);
        }

        void remove(size_t from, size_t to)
        {
            deleteSelection(from, to);
        }

        void deleteSelection(size_t from, size_t to)
        in
        {
            assert(from < m_text.length);
            assert(to < m_text.length);
            assert(to >= from);
        }
        body
        {
            string newtext;
            if (from > 0)
                newtext = m_text[0..from] ~ m_text[to+1..$];
            else
                newtext = m_text[to+1..$];

            if (m_loc.offset != from && to-from > 0 )
                foreach(i; 0..(to-from) + 1)
                    moveLeft();

            m_text = newtext;
        }

        /**
        * Move left to next character
        */
        void moveLeft(bool seeking = false)
        {
            if (m_loc.offset > 0)
            {
                m_loc.offset --;
                if (m_loc.col == 0)
                {
                    // Go up a line
                    m_loc.col = countToStartOfLine();
                    m_loc.row --;
                }
                else
                {
                    m_loc.col --;
                }
            }

            if (!seeking)
                m_seekColumn = m_loc.col;
        }


        /**
        * Jump left to next word
        */
        void jumpLeft()
        {
            if (col == 0)
                return;

            if (isDelim(leftText) && !isBlank(leftText))
            {
                moveLeft();
                return;
            }

            while(col > 0 && m_loc.offset > 0 && isBlank(leftText))
                moveLeft();

            while(col > 0 && m_loc.offset > 0 && !isDelim(leftText))
                moveLeft();
        }

        /**
        * Move right to next character
        */
        void moveRight(bool seeking = false)
        {
            if (m_loc.offset < m_text.length)
            {
                if (m_text[m_loc.offset] == '\n')
                {
                    // Go down a line
                    m_loc.col = 0;
                    m_loc.row ++;
                }
                else
                {
                    m_loc.col ++;
                }
                m_loc.offset ++;
            }

            if (!seeking)
                m_seekColumn = m_loc.col;
        }

        /**
        * Jump right to next word
        */
        void jumpRight()
        {
            auto endCol = col + countToEndOfLine();

            if (isDelim(rightText))
            {
                while(col < endCol && m_loc.offset < m_text.length && isDelim(rightText))
                    moveRight();
            }
            else
            {
                while(col < endCol && m_loc.offset < m_text.length && !isDelim(rightText))
                    moveRight();

                while(col < endCol && m_loc.offset < m_text.length && isBlank(rightText))
                    moveRight();
            }
        }

        void moveUp()
        {
            uint preMoveRow = m_loc.row,
                 preMoveColumn = m_loc.col,
                 preMoveOffset = m_loc.offset;

            bool found = false;
            while(m_loc.offset > 0)
            {
                moveLeft(true);
                if (m_loc.col == m_seekColumn ||
                    m_loc.col < m_seekColumn && countToEndOfLine() == 0 && m_loc.row == preMoveRow - 1 ||
                    (m_loc.col == 0 && m_text[m_loc.offset] == '\n'))
                {
                    found = true;
                    break;
                }
            }

            if  (!found)
            {
                m_loc.offset = preMoveOffset;
                m_loc.col = preMoveColumn;
                m_loc.row = preMoveRow;
            }
        }

        void moveDown()
        {
            uint preMoveRow = m_loc.row,
                 preMoveColumn = m_loc.col,
                 preMoveOffset = m_loc.offset;

            bool found = false;
            while(m_loc.offset < m_text.length)
            {
                moveRight(true);
                if (m_loc.col == m_seekColumn ||
                    m_loc.col < m_seekColumn && countToEndOfLine() == 0 && m_loc.row == preMoveRow + 1 ||
                    (m_loc.col == 0 && m_text[m_loc.offset] == '\n'))
                {
                    found = true;
                    break;
                }
            }

            if  (!found)
            {
                m_loc.offset = preMoveOffset;
                m_loc.col = preMoveColumn;
                m_loc.row = preMoveRow;
            }
        }

        void home() // home key
        {
            while (m_loc.col != 0)
                moveLeft();
        }

        void end() // end key
        {
            if (m_loc.offset == m_text.length)
                return;

            while(m_loc.offset < m_text.length && m_text[m_loc.offset] != '\n')
                moveRight();
        }

        /**
        * Move caret to the start of the text
        */
        void gotoStartOfText()
        {
            while(m_loc.offset > 0)
                moveLeft();
        }

        /**
        * Move caret to the end of the text
        */
        void gotoEndOfText()
        {
            while(m_loc.offset < m_text.length)
                moveRight();
        }

        uint countToStartOfLine()
        {
            if (m_loc.offset == 0)
                return 0;

            int i = m_loc.offset - 1, count = 0;

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
            uint i = m_loc.offset, count = 0;
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

        /**
        * Return x,y caret position in screen coords, relative to first character
        */
        int[2] getCaretPosition(ref const(Font) font)
        {
            int[2] cpos = [0,0];
            foreach(i, char c; m_text)
            {
                if (i == m_loc.offset)
                    break;

                if (c == '\n')
                {
                    cpos[0] = 0;
                    cpos[1] += font.m_lineHeight;
                }
                else if (c == '\t')
                {
                    cpos[0] += tabSpaces*font.width(' ');
                }
                else
                {
                    cpos[0] += font.width(c);
                }
            }
            return cpos;
        }

        /**
        * Return the row, col at screen position x, y relative to lower
        * left corner of first character. Returned row and col are always
        * inside the available text.
        */
        Location getLocation(ref const(Font) font, int x, int y)
        {
            Location _loc;

            //int[2] cpos = [0,0];

            if (m_text.length == 0)
                return _loc;

            // row is determined solely by font.m_lineHeight
            _loc.row = cast(int) (y / font.m_lineHeight);

            auto lines = splitLines(m_text);
            if (_loc.row > lines.length - 1)
                _loc.row = lines.length - 1;

            if (_loc.row > 0)
                foreach(l; lines[0.._loc.row])
                    _loc.offset += l.length;

            float _x = 0;
            foreach(char c; lines[_loc.row])
            {
                if (_x > x)
                    break;

                if (c == '\t')
                    _x += tabSpaces*font.width(' ');
                else
                    _x += font.width(c);

                _loc.col ++;
                _loc.offset ++;
            }
            return _loc;
        }

        void moveCaret(uint newRow, uint newCol)
        {
            if (newRow == row && newCol == col)
                return;

            if (newRow > row || (newRow == row && newCol > col))
            {
                while(m_loc.offset < m_text.length && (row != newRow || col != newCol))
                    moveRight();
            }
            else
            {
                while(m_loc.offset > 0 && (row != newRow || col != newCol))
                    moveLeft();
            }
        }

        /**
        * Move left from caret until given char is found, return row, column and offset
        */
        Location searchLeft(char c)
        {
            auto store = m_loc;
            while (m_loc.offset > 0 && m_text[m_loc.offset] != c)
                moveLeft();

            auto rVal = m_loc;
            m_loc = store;
            return rVal;
        }

        /**
        * Move right from caret until given char is found, return row, column and offset
        */
        Location searchRight(char c)
        {
            auto store = m_loc;
            while (m_loc.offset < m_text.length && m_text[m_loc.offset] != c)
                moveRight();

            auto rVal = m_loc;
            m_loc = store;
            return rVal;
        }

        // Clear all text
        void clear()
        {
            m_text.clear;
            m_loc.offset = 0;
            m_loc.row = 0;
            m_loc.col = 0;
            m_seekColumn = 0;
        }

    private:

        bool isDelim(char c)
        {
            return isBlank(c) ||
                   !isAlphaNum(c);
        }

        bool isBlank(char c)
        {
            return c == ' ' ||
                   c == '\t' ;
        }

        string m_text = "";

        // Default number of spaces for a tab
        uint tabSpaces = 4;

        // Current column and row of the caret (insertion point)
        Location m_loc;

        // When moving up and down through carriage returns, try to get to this column
        uint m_seekColumn = 0;
}



struct Span
{
    string buffer;
    size_t newLines;

    this(string _buffer)
    {
        buffer = _buffer;
        countNewLines();
    }

    @property size_t length()
    {
        return buffer.length;
    }

    /**
    * Count number of newlines in the buffer
    */
    size_t countNewLines()
    {
        newLines = 0;
        foreach(char c; buffer)
            if (c == '\n')
                newLines ++;

        return newLines;
    }

    /**
    * Create two new spans, by splitting this span at splitAt.
    * A left and right span are returned as a Tuple. The left
    * span contains the original span up to and including splitAt - 1,
    * the right span contains the original span from splitAt to length.
    */
    Tuple!(Span, Span) split(size_t splitAt)
    in
    {
        assert(splitAt > 0 && splitAt < buffer.length);
    }
    body
    {
        auto left = Span(buffer[0..splitAt]);
        auto right = Span(buffer[splitAt..$]);
        return tuple(left, right);
    }
}


class SpanList
{
    class Node
    {
        Node prev, next;
        Span payload;

        this() {}
        this(Span data) { payload = data; }
    }

    Node head, tail; // sentinels

    this()
    {
        clear();
    }

    @property bool empty() { return head.next == tail && tail.prev == head; };
    @property ref Span front() { return head.next.payload; }
    @property ref Span back() { return tail.prev.payload; }
    @property Node frontNode() { return head.next; }
    @property Node backNode() { return tail.prev; }

    Node insertAfter()(Node n, Span payload)
    {
        auto newNode = new Node(payload);
        newNode.next = n.next;
        newNode.prev = n;
        n.next.prev = newNode;
        n.next = newNode;
        return newNode;
    }

    Node[] insertAfter(Range)(Node n, Range r) if (is(ElementType!Range == Span))
    {
        Node[] newNodes;
        foreach(s; r)
        {
            newNodes ~= insertAfter(n, s);
            n = n.next;
        }
        return newNodes;
    }

    Node insertBefore(Node n, Span payload)
    {
        return insertAfter(n.prev, payload);
    }

    Node insertFront(Span payload)
    {
        return insertAfter(head, payload);
    }

    Node insertBack(Span payload)
    {
        return insertAfter(tail.prev, payload);
    }

    /**
    * Inserts the span at the given logical index.
    * Returns: the Node corresponding to the new Span
    */
    Node insertAt(size_t index, Span s)
    {
        if (index == 0)
            return insertAfter(head, s);
        else
        {
            auto found = findNode(index);

            if (found.node is head || found.node is tail)
                return insertBack(s);

            if (found.offset == 0)
                return insertBefore(found.node, s);
            else if (found.offset == found.span.length)
                return insertAfter(found.node, s);
            else
            {
                auto splitNode = found.span.split(found.offset);
                auto newNodes = insertAfter(found.node, [splitNode[0], s, splitNode[1]]);
                remove(found.node);
                return newNodes[1];
            }
        }
    }

    /**
    * Remove a single Node
    */
    void remove(Node node)
    {
        node.prev.next = node.next;
        node.next.prev = node.prev;
    }

    /**
    * Remove all Nodes between left and right, inclusive.
    * Returns: An array of Spans which were removed.
    */
    Span[] remove(Node lNode, Node rNode)
    in
    {
        assert(lNode !is head && lNode !is tail);
        assert(rNode !is head && rNode !is tail);
    }
    body
    {
        lNode.prev.next = rNode.next;
        rNode.next.prev = lNode.prev;

        Appender!(Span[]) removed;
        while(lNode !is rNode)
        {
            removed.put(lNode.payload);
            lNode = lNode.next;
        }
        removed.put(rNode.payload);

        return removed.data;
    }

    /**
    * Remove spans covering a arange of logical indices, taking
    * care of fractional spans (from and to are inclusive).
    * Returns: A Tuple containing an array of Spans removed, and
    * spans inserted at the left and right 'edges' of the removed Spans.
    */
    Tuple!(Span[],"del",Node,"lAdd",Node,"rAdd") remove(size_t from, size_t to)
    {
        Tuple!(Span[],"del",Node,"lAdd",Node,"rAdd") result;

        auto left = findNode(from);
        if (left.node is tail) return result;

        auto right = findNode(to);

        if (left.offset > 0)
        {
            auto newSpan = Span(left.span.buffer[0..left.offset]);
            result.lAdd = insertBefore(left.node, newSpan);
        }

        if (right.node is tail)
            right.node = tail.prev;
        else if (right.offset + 1 < right.span.length)
        {
            auto newSpan = Span(right.span.buffer[right.offset+1..$]);
            result.rAdd = insertAfter(right.node, newSpan);
        }

        result.del = remove(left.node, right.node);
        return result;
    }

    /**
    * Return the Node and Span which spans the corresponding logical index
    * and the local offset into that span.
    */
    Tuple!(Node,"node",Span,"span",size_t,"offset") findNode(size_t idx)
    {
        Tuple!(Node,"node",Span,"span",size_t,"offset") result;

        size_t offset = 0, spanOffset = 0;
        for(auto c = head.next; c != tail; c = c.next)
        {
            spanOffset = idx - offset;

            if (idx >= offset && idx < offset + c.payload.buffer.length)
            {
                result.span = c.payload;
                result.node = c;
                result.offset = spanOffset;
                return result;
            }

            offset += c.payload.buffer.length;
        }

        result.node = tail;
        return result;
    }

    /**
    * Standard bidirectional range which can shrink from both ends
    */
    struct Range
    {
        Node first, last;

        this(Node _first, Node _last)
        {
            first = _first;
            last = _last;
        }

        @property bool empty()
        {
            return first is null;
        }

        @property ref Span front()
        {
            return first.payload;
        }

        @property ref Span back()
        {
            return last.payload;
        }

        @property ref Node frontNode()
        {
            return first;
        }

        @property ref Node backNode()
        {
            return last;
        }

        void popFront()
        {
            if (first is last)
            {
                first = null;
                last = null;
            }
            else
                first = first.next;
        }

        void popBack()
        {
            if (first is last)
            {
                first = null;
                last = null;
            }
            else
                last = last.prev;
        }
    }

    /**
    * Not really a range...
    */
    struct IndexRange
    {
        Node first, last, current;

        this(Node _first, Node _last, Node _current = null)
        {
            first = _first;
            last = _last;
            current = _current;

            if (!current)
                current = first;
        }

        @property bool emptyForward()
        {
            return current is last;
        }

        @property bool emptyBackward()
        {
            return current is first;
        }

        @property ref Span front()
        {
            return current.payload;
        }

        @property ref Node frontNode()
        {
            return current;
        }

        void next()
        {
            assert(!emptyForward);
            current = current.next;
        }

        void prev()
        {
            assert(!emptyBackward);
            current = current.prev;
        }
    }

    IndexRange indexer(Node starter = null)
    {
        return IndexRange(head.next, tail.prev, starter);
    }

    Range opSlice()
    {
        return Range(head.next, tail.prev);
    }

    Range opSlice(Node first, Node last)
    {
        return Range(first, last);
    }

    void clear()
    {
        head = new Node;
        tail = new Node;
        head.next = tail;
        tail.prev = head;
    }
}


class TextArea2
{
    struct Caret { size_t offset, row, col; }
    struct Location { uint offset, row, col; }

    string m_original;
    Appender!string m_edit;
    SpanList m_spans;
    Caret m_caret;

    uint m_tabSpaces = 4;
    uint m_totalNewLines;
    string m_currentLine;

    size_t m_seekColumn;

    debug
    {
        alias std.datetime.Clock clock;
    }

    @property size_t row() const { return m_caret.row; }
    @property size_t col() const { return m_caret.col; }
    @property size_t offset() { return m_caret.offset; }

    this()
    {
        m_spans = new SpanList();
    }

    this(string originalText)
    {
        this();
        loadOriginal(originalText);
    }

    void loadOriginal(string text)
    {
        clear();
        m_original = text;
        auto newSpan = Span(m_original[0..$]);
        auto newNode = m_spans.insertAt(0, newSpan);
        m_totalNewLines = newSpan.newLines;
        setCaret(newSpan.length);
    }

    /**
    * Insert text at the caret position
    */
    void insert(string s)
    {
        insertAt(m_caret.offset, s);
    }

    void insert(char s)
    {
        insertAt(m_caret.offset, s.to!string);
    }

    private void insertAt(size_t index /** logical index **/, string s)
    {
        auto begin = m_edit.data.length;
        m_edit.put(s);
        auto newSpan = Span(m_edit.data[begin..$]);
        auto newNode = m_spans.insertAt(index, newSpan);
        m_totalNewLines += newSpan.newLines;

        if (index == m_caret.offset)
        {
            if (newSpan.newLines > 0)
            {
                m_caret.row += newSpan.newLines;
                if (s[$-1] == '\n')
                    m_caret.col = 0;
                else
                    m_caret.col = (splitLines(s))[$-1].length;
            }
            else
            {
                m_caret.col += s.length;
            }

            m_caret.offset += s.length;
            m_seekColumn = m_caret.col;
        }
        else
        {
            setCaret(index + s.length);
        }

        m_currentLine = byLine(m_caret.row).front;  // optimize
    }

    /**
    * Remove text between [from,to] (inclusive). Either from or to must
    * be the current caret location.
    */
    void remove(size_t from, size_t to)
    in
    {
        //assert(from < to);
        //writeln("REMOVE: ", from, ", ", to);
        //assert(from == m_caret.offset || to == m_caret.offset);
    }
    body
    {
        auto mods = m_spans.remove(from, to);

        if (mods.del.length == 0)
            return;

        // Calculate new caret location
        auto totalDel = reduce!("a + b.newLines")(0, mods.del);

        if (mods.lAdd !is null)
            totalDel -= mods.lAdd.payload.newLines;
        if (mods.rAdd !is null)
            totalDel -= mods.rAdd.payload.newLines;

        m_totalNewLines -= totalDel;
        auto length = to - from + 1; // this includes newlines

        if (from == m_caret.offset)
        {
            m_currentLine = byLine(m_caret.row).front; // optimize
            return;
        }

        m_caret.offset = from;

        if (totalDel > 0) // optimize for single newline deletion
            setCaret(from);
        else
            m_caret.col -= (length - totalDel);

        m_currentLine = byLine(m_caret.row).front; // optimize
        //setCaret(from);
    }

    void del()
    {
        remove(m_caret.offset, m_caret.offset);
    }

    void backspace()
    {
        if (m_caret.offset > 0)
            remove(m_caret.offset-1, m_caret.offset-1);
    }

    /**
    * Slow way of setting the caret
    */
    void setCaret(size_t index)
    {
        auto rc = getRowCol(index);
        m_caret.row = rc.row;
        m_caret.col = rc.col;
        m_caret.offset = index;
        m_seekColumn = m_caret.col;
    }

    char leftText()
    {
        if (m_caret.offset == 0)
            return cast(char)0;
        else if (m_caret.col == 0)
            return '\n';
        else return m_currentLine[m_caret.col-1];
    }

    char rightText()
    {
        if (m_caret.row == m_totalNewLines && m_caret.col == m_currentLine.length)
            return cast(char)0;
        else if (m_caret.col == m_currentLine.length)
            return '\n';
        else return m_currentLine[m_caret.col];
    }

    string getLine(size_t line)
    {
        if (line == m_caret.row)
            return m_currentLine;
        else
            return byLine(line).front;
    }

    string getCurrentLine()
    {
        return m_currentLine;
    }


    /**
    * Return the row and column corresponding to the given logical index
    */
    Tuple!(int,"row",int,"col") getRowCol(size_t index)
    {
        Tuple!(int,"row",int,"col") result;

        size_t offset;
        auto r = byLine();
        while(!r.empty && offset + r.front.length + 1 < index)
        {
            offset += r.front.length + 1; // count the newline
            result.col = r.front.length;
            result.row ++;
            r.popFront();
        }

        if (r.empty)
            return result;

        if (index == offset + r.front.length + 1)
        {
            result.row ++;
            result.col = 0;
        }
        else
            result.col = index - offset;

        return result;
    }


    /**
    * Return the row, col at screen position x, y relative to lower
    * left corner of first character. Returned row and col are always
    * inside the available text.
    */
    Location getLocation(ref const(Font) font, int x, int y)
    {
        Tuple!(int,"row",int,"col",int,"offset") loc;

        if (m_spans.empty)
            return Location(loc.offset, loc.row, loc.col);

        // row is determined solely by font.m_lineHeight
        loc.row = cast(int) (y / font.m_lineHeight);
        loc.row = min(loc.row, m_totalNewLines);

        if (loc.row > 0)
        {
            int r = 0;
            auto range = byLine(0);
            while(r != loc.row)
            {
                loc.offset += range.front.length + 1; // +1 counts the newline '\n'
                range.popFront();
                r ++;
            }
        }

        float _x = 0;
        foreach(char c; getLine(loc.row))
        {
            if (_x > x)
                break;

            if (c == '\t')
                _x += m_tabSpaces*font.width(' ');
            else
                _x += font.width(c);

            loc.col ++;
            //loc.offset ++;
        }
        return Location(loc.offset, loc.row, loc.col);
    }

    /**
    * For the given font, resturn the x,y coordinates of the caret
    * relative to the first character of the entire text sequence.
    */
    int[2] getCaretPosition(ref const(Font) font)
    {
        Tuple!(int,"x",int,"y") loc;
        loc.y = m_caret.row * font.m_lineHeight;

        auto row = byLine(m_caret.row).front;
        size_t _x;
        while(_x < row.length && _x != m_caret.col)
        {
            if (row[_x] == '\t')
                loc.x += m_tabSpaces*font.width(' ');
            else
                loc.x += font.width(row[_x]);
            _x ++;
        }

        return [loc.x, loc.y];
    }


    /**
    * Move the caret left by one character.
    * Returns: true if move succeeded, else false.
    */
    bool moveLeft()
    {
        if (m_caret.col > 0)
        {
            m_caret.col --;
            m_caret.offset --;
            m_seekColumn = m_caret.col;
            return true;
        }
        else
        {
            if (m_caret.row > 0)
            {
                m_caret.row --;
                m_caret.offset --;
                m_currentLine = byLine(m_caret.row).front;
                m_caret.col = m_currentLine.length;
                m_seekColumn = m_caret.col;
                return true;
            }
        }
        return false;
    }

    /**
    * Move the caret right by one character.
    * Returns: true if move succeeded, else false.
    */
    bool moveRight()
    {
        if (m_caret.col < m_currentLine.length) // move right along the current line
        {
            m_caret.col ++;
            m_caret.offset ++;
            m_seekColumn = m_caret.col;
            return true;
        }
        else
        {
            if (m_caret.row < m_totalNewLines) // move down to the next line
            {
                m_caret.col = 0;
                m_caret.row ++;
                m_caret.offset ++;
                m_currentLine = byLine(m_caret.row).front;
                m_seekColumn = m_caret.col;
                return true;
            }
        }
        return false;
    }

    /**
    * Move caret up one line.
    * Returns: true if move succeeded, else false.
    */
    bool moveUp()
    {
        if (m_caret.row > 0)
        {
            auto temp = m_caret.col + 1;
            m_caret.row --;
            m_currentLine = byLine(m_caret.row).front;
            m_caret.col = min(m_currentLine.length, m_seekColumn);
            m_caret.offset -= temp + (m_currentLine.length - m_caret.col);
            return true;
        }
        return false;
    }

    /**
    * Move caret down one line.
    * Returns: true if move succeeded, else false.
    */
    bool moveDown()
    {
        if (m_caret.row < m_totalNewLines)
        {
            auto temp = (m_currentLine.length - m_caret.col) + 1;
            m_caret.row ++;
            m_currentLine = byLine(m_caret.row).front;
            m_caret.col = min(m_currentLine.length, m_seekColumn);
            m_caret.offset += temp + m_caret.col;
            return true;
        }
        return false;
    }

    void jumpLeft()
    {
    }

    void jumpRight()
    {
    }

    /**
    * Move caret to start of line
    */
    void home()
    {
        m_caret.offset -= m_caret.col;
        m_caret.col = 0;
        m_seekColumn = m_caret.col;
    }

    /**
    * Move caret to end of line
    */
    void end()
    {
        m_caret.offset += m_currentLine.length - m_caret.col;
        m_caret.col = m_currentLine.length;
        m_seekColumn = m_caret.col;
    }

    void gotoEndOfText()
    {
        while(moveDown()) {}
        while(moveRight()) {}
    }

    void gotoStartOfText()
    {
        setCaret(0);
    }

    /**
    * Move the caret as close to the given row and column as possible.
    */
    void moveCaret(size_t newRow, size_t newCol)
    {
        if (newRow == m_caret.row && newCol == m_caret.col)
            return;

        if (newRow > m_caret.row || (newRow == m_caret.row && newCol > m_caret.col))
            while(moveRight() && (m_caret.row != newRow || m_caret.col != newCol)) {}
        else
            while(moveLeft() && (m_caret.row != newRow || m_caret.col != newCol)) {}
    }

    /**
    * Return a Range for iterating through the text by line, starting
    * at the given line number.
    */
    struct LineRange
    {
        SpanList.Range r;
        string buffer;
        string lineSlice;
        bool finished;

        this(SpanList.Range list, size_t startLine)
        {
            r = list;
            size_t bufferStartRow = 0;
            while(!r.empty && bufferStartRow + r.front.newLines < startLine)
            {
                bufferStartRow += r.front.newLines;
                r.popFront();
            }

            if (r.empty)
                return;

            int chomp = 0;
            buffer = r.front.buffer;
            r.popFront();
            if (bufferStartRow != startLine)
            {
                uint i = 0;
                while(i < buffer.length && bufferStartRow != startLine)
                {
                    if (buffer[i] == '\n')
                        bufferStartRow ++;
                    chomp++;
                    i++;
                }
                buffer = buffer[chomp..$];
            }

            if (count(buffer, '\n') == 0)
            {
                int gotNewlines = 0;
                while(!r.empty && gotNewlines == 0)
                {
                    buffer ~= r.front.buffer;
                    gotNewlines += r.front.newLines;
                    r.popFront();
                }
            }
            setSlice();
        }


        @property bool empty()
        {
            return finished;
        }

        @property string front()
        {
            return lineSlice;
        }

        void setSlice()
        {
            auto newAt = countUntil(buffer, '\n');
            if (newAt == -1)
                lineSlice = buffer;
            else
                lineSlice = buffer[0..newAt];
        }

        void popFront()
        {
            auto newAt = countUntil(buffer, '\n');
            if (newAt != -1)
                buffer = buffer[newAt+1..$];
            else
            {
                finished = true;
                lineSlice.clear;
                return;
            }

            newAt = countUntil(buffer, '\n');
            if (newAt == -1)
            {
                int gotLines = 0;
                while(!r.empty && gotLines == 0)
                {
                    buffer ~= r.front.buffer;
                    gotLines += r.front.newLines;
                    r.popFront();
                }
                setSlice();
            }
            else
            {
                lineSlice = buffer[0..newAt];
            }
        }
    }

    LineRange byLine(size_t startLine = 0)
    {
        return LineRange(m_spans[], startLine);
    }

    void set(string s)
    {
        clear();
        loadOriginal(s);
    }

    void clear()
    {
        m_caret = Caret();
        m_original.clear;
        m_edit.clear;
        m_currentLine = null;
        m_totalNewLines = 0;
        m_spans.clear;
    }

    /**
    * Return the contained text as a single string (char sequence)
    */
    override string toString()
    {
        Appender!string text;
        foreach(span; m_spans)
            text.put(span.buffer);
        return text.data();
    }
}

unittest /** List **/
{
    /++
    auto text = new TextArea2();

    text.insert("line 0\nline 1\n");
    assert(text.m_caret.col == 0);
    assert(text.m_caret.row == 2);
    assert(text.m_caret.offset == 14);

    text.insert("line 2");
    assert(text.m_caret.col == 6);
    assert(text.m_caret.row == 2);
    assert(text.m_caret.offset == 20);

    text.insert("line 2 plus some more stuff \nblah blah");
    assert(text.m_caret.col == 9);
    assert(text.m_caret.row == 3);
    assert(text.m_caret.offset == 58);

    text.insert("line 3 and stuff ");
    assert(text.m_caret.col == 26);
    assert(text.m_caret.row == 3);
    assert(text.m_caret.offset == 75);

    assert(text.getRowCol(10).row == 1);
    assert(text.getRowCol(10).col == 3);
    assert(text.getRowCol(19).row == 2);
    assert(text.getRowCol(19).col == 5);
    assert(text.getRowCol(57).row == 3);
    assert(text.getRowCol(57).col == 8);

    //assert(false, "End of test");
    ++/
}

