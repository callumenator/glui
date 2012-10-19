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
            {
                m_vscroll.current = 0;
                m_vscroll.range = [0, m_text.nLines];
            }
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
        TextArea.Caret getCaret(int x, int y)
        {
            auto relx = x - m_screenPos.x - 5;
            if (m_allowHScroll)
                relx += m_hscroll.current * m_font.m_maxWidth;

            auto rely = y - m_screenPos.y - textOffsetY() - m_font.m_lineHeight/2;
            if (m_allowVScroll)
                rely += m_vscroll.current * m_font.m_lineHeight;

            if (relx < 0 || rely < 0)
                return TextArea.Caret();

            return m_text.getCaret(m_font, relx, rely);
        }

        void set(Font font, WidgetArgs args)
        {
            super.set(args);

            m_type = "WIDGETTEXT";
            m_cacheId = glGenLists(1);
            m_text = new PieceTableTextArea;
            //m_text = new SimpleTextArea;

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

                m_vscroll.eventSignal.connect(&this.scrollEvent);
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

        int scrollEvent(Widget widget, WidgetEvent event)
        {
            m_refreshCache = true;
            needRender();
            return 0;
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

                renderHighlights(); // line highlights
                renderSelection();  // text selection

                auto startRow = 0;
                if (m_allowVScroll)
                    startRow = m_vscroll.current;
                auto _text = m_text.getTextLines(startRow, m_dim.y / m_font.m_lineHeight);

                if (m_highlighter)
                    renderCharacters(m_font, _text, m_highlighter);
                else
                    renderCharacters(m_font, _text, m_textColor);

                glEndList();
                m_refreshCache = false;
            }

            glPopMatrix();

            if (m_editable && m_drawCaret && (amIFocused || isAChildFocused) )
                renderCaret();

            if (recurse)
                renderChildren();
        }


        /**
        * Draw the caret
        */
        void renderCaret()
        {
            glPushMatrix();
                glLoadIdentity();
                glTranslatef(m_parent.screenPos.x + m_pos.x, m_parent.screenPos.y + m_pos.y, 0);
                setCoords();

                if (m_allowVScroll)
                    glTranslatef(0, -m_vscroll.current*m_font.m_lineHeight, 0);

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


        /**
        * Helper for drawing a box, used for line highlights and selections.
        * Assume we are in render coordinates:
        * ----------------------
        * setCoords();
        * glScalef(1,-1,1);
        * ----------------------
        */
        void drawBox(float x0, float y0, float x1, float y1, float[4] color)
        {
            if (m_allowVScroll)
                glTranslatef(0, m_vscroll.current*m_font.m_lineHeight, 0);

            glColor4fv(color.ptr);
            glBegin(GL_QUADS);
            glVertex2f(x0, y0);
            glVertex2f(x1, y0);
            glVertex2f(x1, y1);
            glVertex2f(x0, y1);
            glEnd();

            if (m_allowVScroll)
                glTranslatef(0, -m_vscroll.current*m_font.m_lineHeight, 0);
        }


        /**
        * Draw line highlights
        */
        void renderHighlights()
        {
            if (m_lineHighlights.length == 0)
                return;

            uint width = m_dim.x;
            if (m_allowHScroll)
            {
                auto rnge = m_hscroll.range;
                width += rnge[1]*m_font.m_maxWidth;
            }

            foreach(line, color; m_lineHighlights)
            {
                drawBox(-5, -line*m_font.m_lineHeight - m_font.m_maxHoss,
                        width, -line*m_font.m_lineHeight + m_font.m_maxHeight,
                        color);
            }
        }


        /**
        * Render the text selection background
        */
        void renderSelection()
        {
            if (!haveSelection)
                return;

            if (m_allowVScroll)
                glTranslatef(0, m_vscroll.current*m_font.m_lineHeight, 0);

            scope(exit)
            {
                if (m_allowVScroll)
                    glTranslatef(0, -m_vscroll.current*m_font.m_lineHeight, 0);
            }

            auto startRow = 0;
            if (m_allowVScroll)
                startRow = m_vscroll.current;

            auto r = reduce!(min, max)(m_selectionRange);
            auto lower = r[0];
            auto upper = r[1];

            auto lowerCaret = m_text.getCaret(lower);
            auto upperCaret = m_text.getCaret(upper);

            int[2] offset0 = m_text.getCaretPosition(m_font, lowerCaret);
            int[2] offset1 = m_text.getCaretPosition(m_font, upperCaret);

            float[4] selectionColor = [0.,0.,1.,1.];
            if (lowerCaret.row == upperCaret.row)
            {
                drawBox(offset0[0], -offset0[1], offset1[0], -offset0[1] + m_font.m_lineHeight, selectionColor);
            }
            else
            {
                // Only draw the visible part of the selection
                auto lineRange = [startRow, startRow + m_dim.y/m_font.m_lineHeight];
                std.stdio.writeln(lineRange);

                // Quick rejection tests
                if (lowerCaret.row > lineRange[1] || upperCaret.row < lineRange[0])
                    return;

                // Draw first selection row
                drawBox(offset0[0], -offset0[1],
                        offset0[0] + m_text.getLineWidth(m_font, lowerCaret.row),
                        -offset0[1] + m_font.m_lineHeight, selectionColor);

                // Draw last selection row
                drawBox(0, -offset1[1], offset1[0], -offset1[1] + m_font.m_lineHeight, selectionColor);

                // Draw rows in-between
                if (upperCaret.row > lowerCaret.row + 1)
                {
                    foreach(int row; lowerCaret.row+1..upperCaret.row)
                    {
                        if (row < lineRange[0])
                            continue;
                        if (row > lineRange[1])
                            return;

                        float y0 = -offset0[1] - (row - cast(int)(lowerCaret.row))*m_font.m_lineHeight;
                        drawBox(0, y0, m_text.getLineWidth(m_font, row),
                                y0 + m_font.m_lineHeight, selectionColor);
                    }
                }
            }
        }


        /**
        * Setup coordinates for rendering.
        */
        void setCoords()
        {
            resetXCoord();
            resetYCoord();
        }


        /**
        * Set X coord for rendering.
        */
        void resetXCoord()
        {
            glTranslatef(0*m_pos.x + 5, 0, 0);

            // Translate by the scroll amounts as well...
            if (m_allowHScroll)
                glTranslatef(-m_hscroll.current*m_font.m_maxWidth, 0, 0);
        }


        /**
        * Set Y coord for rendering.
        */
        void resetYCoord()
        {
            glTranslatef(0, 0*m_pos.y + textOffsetY() + m_font.m_lineHeight, 0);

            // Translate by the scroll amounts as well...
            // if (m_allowVScroll)
            //    glTranslatef(0, -m_vscroll.current*m_font.m_lineHeight, 0);
        }


        /**
        * Calculate the vertical offset for the selected alignment type.
        */
        int textOffsetY()
        {
            // Calculate vertical offset, depends on alignment
            float yoffset = 0;
            final switch(m_vAlign) with(VAlign)
            {
                case CENTER:
                {
                    auto lines = m_text.nLines;
                    auto height = lines * m_font.m_lineHeight;
                    yoffset = m_dim.y/2.0f + m_font.m_maxHoss/2.0f - height/2.0f - m_font.m_lineHeight/2.0f;

                    if (yoffset < 0) yoffset = 0;
                    break;
                }
                case BOTTOM:
                {
                    auto lines = m_text.nLines;
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


        /**
        * Dispatch events.
        */
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
                    auto rc = getCaret(pos.x, pos.y);

                    //m_text.moveCaret(rc.row, rc.col);
                    std.stdio.writeln("MoveCaret: ", (benchmark!( { text.moveCaret(rc.row, rc.col); } )(1))[0].to!("msecs", int));

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


        /**
        * Decide whether key events need to be processed (key repeats).
        */
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


        /**
        * Handle key events
        */
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
                    adjustVisiblePortion();
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
                    adjustVisiblePortion();
                    break;
                }
                case KC_PAGE_UP: // page up key
                {
                    auto nLines = cast(int) (m_dim.y / m_font.m_lineHeight);
                    while(nLines - 1 > 0)
                    {
                        nLines --;
                        if (!m_text.moveUp())
                            break;
                    }

                    if (root.shiftIsDown)
                        updateSelectionRange();
                    else
                        clearSelection();

                    m_drawCaret = true;
                    needRender();
                    adjustVisiblePortion();
                    break;
                }
                case KC_PAGE_DOWN: // page down key
                {
                    auto nLines = cast(int) (m_dim.y / m_font.m_lineHeight);
                    while(nLines - 1 > 0)
                    {
                        nLines --;
                        if (!m_text.moveDown())
                            break;
                    }

                    if (root.shiftIsDown)
                        updateSelectionRange();
                    else
                        clearSelection();

                    m_drawCaret = true;
                    needRender();
                    adjustVisiblePortion();
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
                    adjustVisiblePortion();
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
                    adjustVisiblePortion();
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
                    adjustVisiblePortion();
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
                    adjustVisiblePortion();
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
                    adjustVisiblePortion();
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
                    adjustVisiblePortion();
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
                        adjustVisiblePortion();

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
                        adjustVisiblePortion();
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
                                adjustVisiblePortion();
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
                                adjustVisiblePortion();
                                break;
                            }
                            case KC_X: // copy selection to clipboard and delete selection
                            {
                                copyToClipboard();
                                deleteSelectedText();
                                adjustVisiblePortion();
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
                        adjustVisiblePortion();
                    }
                    break;
                }

                default:
            }

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
                auto nCols = ((m_dim.x - 5) / m_font.m_maxWidth);
                auto minCol = m_hscroll.current;
                auto maxCol = minCol + nCols;
                if (m_text.col > maxCol)
                    m_hscroll.current = m_text.col - (nCols - 1);
                else if (m_text.col < minCol)
                    m_hscroll.current = m_text.col;
            }
            // If text insert moves caret off screen vertically, adjust vscroll
            if (m_allowVScroll)
            {
                auto minRow = m_vscroll.current;
                auto maxRow = minRow + (m_dim.y / m_font.m_lineHeight) - 1;
                if (m_text.row > maxRow)
                {
                    m_vscroll.current = m_vscroll.current + (m_text.row - maxRow);
                    m_refreshCache = true;
                    needRender();
                }
                else if (m_text.row < minRow)
                {
                    m_vscroll.current = m_text.row;
                    m_refreshCache = true;
                    needRender();
                }
            }
        }


        /**
        * Use drag events for updating text selection.
        */
        override bool requestDrag(int[2] pos)
        {
            m_pendingDrag = true;
            return true;
        }


        /**
        * Use drag events for updating text selection.
        */
        override void drag(int[2] pos, int[2] delta)
        {
            auto loc = getCaret(pos.x, pos.y);

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

            m_text.moveCaret(loc.row, loc.col);
            m_caretPos = m_text.getCaretPosition(m_font);
        }


        /**
        * Update the text selection range with current caret.
        */
        void updateSelectionRange()
        {
            m_selectionRange[1] = m_text.offset;
            m_refreshCache = true;
        }


        /**
        * Clear the current text selection info.
        */
        void clearSelection()
        {
            if (!haveSelection())
                return;

            m_selectionRange[] = [0,0];
            m_refreshCache = true;
            needRender();
        }


        /**
        * Returns: true if text is selected.
        */
        bool haveSelection()
        {
            return m_selectionRange[0] != m_selectionRange[1];
        }


        /**
        * Deletes the currently selected text.
        */
        void deleteSelectedText()
        {
            if (!haveSelection())
                return;

            auto r = reduce!(min, max)(m_selectionRange);
            auto deleted = m_text.remove(r[0], r[1]-1);
            eventSignal.emit(this, WidgetEvent(TextRemove(deleted)));
            clearSelection();
        }


        /**
        * Returns: the currently selected text as a string.
        */
        string getSelectedText()
        in
        {
            assert(haveSelection());
        }
        body
        {
            auto r = reduce!(min, max)(m_selectionRange);
            std.stdio.writeln(typeof(m_text.text).stringof);
            return m_text.getTextBetween(r[0],r[1]);
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
                    auto selected = getSelectedText();
                    auto lines = splitLines(selected);
                    foreach(i; 0..lines.length-1)
                        selection ~= lines[i] ~ '\r';

                    if (selected[$-1] == '\n')
                        selection ~= lines[$-1] ~ ['\r', '\0'];
                    else
                        selection ~= lines[$-1] ~ '\0';

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
                    auto lines = splitLines(readin);
                    foreach(i, line; lines)
                    {
                        if (i == lines.length-1)
                        {
                            if (readin[$-1] == '\n' || readin[$-2..$] == ['\n','\r'])
                                paste ~= line ~ '\n';
                            else
                                paste ~= line;
                        }
                        else
                            paste ~= line ~ '\n';
                    }

                    m_text.insert(paste);
                    m_refreshCache = true;
                    needRender();
                }
            }
        }

    private:

        TextArea m_text;
        Font m_font = null;

        KEY m_lastKey = KEY.KC_NULL;

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


/**
* This interface defines a TextArea, a class which manages text sequences,
* insertion, deletion, and caret operations.
*/
abstract class TextArea
{
    /**
    *The caret defines the input/operation point in the text sequence.
    */
    struct Caret { size_t offset, row, col; }

    /**
    * Return the current caret row.
    */
    @property size_t row() const;

    /**
    * Return the current caret column.
    */
    @property size_t col() const;

    /**
    * Return the current caret 1-D offset.
    */
    @property size_t offset() const;

    /**
    * Return the number of lines in the text.
    */
    @property size_t nLines() const;

    /**
    * Set the text to the given string. This implies a clear().
    */
    void set(string s);

    /**
    * Clear all current text, and reset the caret to 0,0,0.
    */
    void clear();

    /**
    * Insert a char at the current caret location.
    */
    void insert(char s);

    /**
    * Insert a string at the current caret location.
    */
    void insert(string s);

    /**
    * Apply the keyboard delete operation at the current caret location.
    */
    string del();

    /**
    * Apply the keyboard backspace operation at the current caret location.
    */
    string backspace();

    /**
    * Remove all text between [from,to] (inclusive) offsets into the text sequence.
    */
    string remove(size_t from, size_t to);

    /**
    * Return the text to the left of the caret.
    */
    char leftText();

    /**
    * Return the text to the right of the caret (i.e. at the caret).
    */
    char rightText();

    /**
    * Get text in the given line as a string.
    */
    string getLine(size_t line);

    /**
    * Get the text in the line at the current caret location.
    */
    string getCurrentLine();

    /**
    * Get all text between lines [from, from + n_lines] (inclusive). If
    * n_lines is not set, all lines beginning at from are returned. Text
    * is returned as a single string.
    */
    string getTextLines(size_t from = 0, int n_lines = -1);

    /**
    * Get all text between offsets [from, to] (inclusive).
    */
    string getTextBetween(size_t from, size_t to);

    /**
    * Get the caret corresponding to the given 1-D offset.
    */
    Caret getCaret(size_t index);

    /**
    * Get the caret corresponding to the given (x,y) coordinates relative
    * to the first character in the text sequence, assuming the given font.
    */
    Caret getCaret(ref const(Font) font, int x, int y);

    /**
    * Assuming the given font, return the coordinates (x,y) of the current caret location.
    */
    int[2] getCaretPosition(ref const(Font) font);

    /**
    * Assuming the given font, return the coordinates (x,y) of the given caret.
    */
    int[2] getCaretPosition(ref const(Font) font, Caret caret);

    /**
    * Move the caret left one character.
    */
    bool moveLeft();

    /**
    * Move the caret right one character.
    */
    bool moveRight();

    /**
    * Move the caret up one line. Try to seek the same column as the current line.
    */
    bool moveUp();

    /**
    * Move the caret down one line. Try to seek the same column as the current line.
    */
    bool moveDown();

    /**
    * Jump the caret left to the next word/symbol.
    */
    void jumpLeft();

    /**
    * Jump the caret right to the next word/symbol.
    */
    void jumpRight();

    /**
    * Place the caret at the start of the current line.
    */
    void home();

    /**
    * Place the caret at the end of the current line.
    */
    void end();

    /**
    * Place the caret at the start of the entire text sequence.
    */
    void gotoStartOfText();

    /**
    * Place the caret at the end of the entire text sequence.
    */
    void gotoEndOfText();

    /**
    * Move the caret to the given row and column.
    */
    void moveCaret(size_t newRow, size_t newCol);

    /**
    * Calculate the screen width of a line, given a font.
    */
    int getLineWidth(ref const(Font) font, size_t line);

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
}


// Handles text storage and manipulation for WidgetText
class SimpleTextArea : TextArea
{
    public:

        @property size_t col() const { return m_loc.col; }
        @property size_t row() const { return m_loc.row; }
        @property size_t offset() const { return m_loc.offset; }
        @property size_t nLines() const { return m_text.count('\n') + 1; }

        /**
        * Set and clear all text
        */

        void set(string s)
        {
            m_text.clear;
            m_loc.offset = 0;
            insert(s);
        }

        void clear()
        {
            m_text.clear;
            m_loc.offset = 0;
            m_loc.row = 0;
            m_loc.col = 0;
            m_seekColumn = 0;
        }

        /**
        * Text insertion...
        */

        void insert(char c)
        {
            insert(c.to!string);
        }

        void insert(string s)
        {
            insertInPlace(m_text, m_loc.offset, s);

            foreach(i; 0..s.length)
                moveRight();

            m_seekColumn = m_loc.col;
        }

        /**
        * Text deletion...
        */

        string del()
        {
            if (m_loc.offset < m_text.length)
                return deleteSelection(m_loc.offset, m_loc.offset);
            else return "";
        }

        string backspace()
        {
            if (m_loc.offset > 0)
            {
                auto removed = deleteSelection(m_loc.offset-1, m_loc.offset-1);
                moveLeft();
                m_seekColumn = m_loc.col;
                return removed;
            }
            return "";
        }

        string remove(size_t from, size_t to)
        {
            return deleteSelection(from, to);
        }

        /**
        * Text and caret retrieval...
        */

        char leftText()
        {
            if (m_loc.offset <= 0)
                return cast(char)0;

            return m_text[m_loc.offset-1];
        }

        char rightText()
        {
            if (cast(int)(m_loc.offset) > cast(int)(m_text.length - 1))
                return cast(char)0;

            return m_text[m_loc.offset];
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

        string getTextLines(size_t from = 0, int n_lines = -1)
        {
            auto lines = splitLines(m_text);
            if (from >= lines.length)
                return "";

            lines = lines[from..$];

            Appender!string text;
            size_t gotLines = 0;
            while(!lines.empty && gotLines != n_lines)
            {
                text.put(lines.front);
                text.put("\n");
                gotLines ++;
                lines.popFront();
            }
            return text.data;
        }

        string getTextBetween(size_t from, size_t to)
        in
        {
            assert(from < to);
            assert(from > 0 && to < m_text.length);
        }
        body
        {
            return m_text[from..to+1];
        }

        Caret getCaret(size_t index)
        {
            auto temp = m_loc;
            Caret c;
            if (index > m_loc.offset)
            {
                while(m_loc.offset > 0 && index != m_loc.offset)
                    moveRight();
            }
            else if (index < m_loc.offset)
            {
                while(m_loc.offset > 0 && index != m_loc.offset)
                    moveLeft();
            }

            c = m_loc;
            m_loc = temp;
            return c;
        }

        Caret getCaret(ref const(Font) font, int x, int y)
        {
            Caret _loc;

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
                    _x += m_tabSpaces*font.width(' ');
                else
                    _x += font.width(c);

                _loc.col ++;
                _loc.offset ++;
            }
            return _loc;
        }

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
                    cpos[0] += m_tabSpaces*font.width(' ');
                }
                else
                {
                    cpos[0] += font.width(c);
                }
            }
            return cpos;
        }

        int[2] getCaretPosition(ref const(Font) font, Caret caret)
        {
            auto temp = m_loc;
            m_loc = caret;
            auto result = getCaretPosition(font);
            m_loc = temp;
            return result;
        }

        /**
        * Caret manipulation...
        */

        bool moveLeft()
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
            return true;
        }

        bool moveRight()
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

            return true;
        }

        bool moveUp()
        {
            uint preMoveRow = m_loc.row,
                 preMoveColumn = m_loc.col,
                 preMoveOffset = m_loc.offset;

            bool found = false;
            while(m_loc.offset > 0)
            {
                moveLeft();
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
            return true;
        }

        bool moveDown()
        {
            uint preMoveRow = m_loc.row,
                 preMoveColumn = m_loc.col,
                 preMoveOffset = m_loc.offset;

            bool found = false;
            while(m_loc.offset < m_text.length)
            {
                moveRight();
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
            return true;
        }

        void jumpLeft()
        {
            if (col == 0)
                return;

            if (isDelim(leftText) && !isBlank(leftText))
            {
                moveLeft();
                m_seekColumn = m_loc.col;
                return;
            }

            while(col > 0 && m_loc.offset > 0 && isBlank(leftText))
                moveLeft();

            while(col > 0 && m_loc.offset > 0 && !isDelim(leftText))
                moveLeft();

            m_seekColumn = m_loc.col;
        }

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

            m_seekColumn = m_loc.col;
        }

        void home() // home key
        {
            while (m_loc.col != 0)
                moveLeft();
            m_seekColumn = m_loc.col;
        }

        void end() // end key
        {
            if (m_loc.offset == m_text.length)
                return;

            while(m_loc.offset < m_text.length && m_text[m_loc.offset] != '\n')
                moveRight();

            m_seekColumn = m_loc.col;
        }

        void gotoStartOfText()
        {
            while(m_loc.offset > 0)
                moveLeft();
            m_seekColumn = m_loc.col;
        }

        void gotoEndOfText()
        {
            while(m_loc.offset < m_text.length)
                moveRight();
            m_seekColumn = m_loc.col;
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

            m_seekColumn = m_loc.col;
        }

        int getLineWidth(ref const(Font) font, size_t line)
        {
            int width = font.width(' ');
            auto _line = getLine(line);
            foreach(char c; _line)
            {
                if (c == '\t')
                    width += m_tabSpaces * font.width(' ');
                else
                    width += font.width(c);
            }
            return width;
        }

        /**
        * Move left from caret until given char is found, return row, column and offset
        */
        Caret searchLeft(char c)
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
        Caret searchRight(char c)
        {
            auto store = m_loc;
            while (m_loc.offset < m_text.length && m_text[m_loc.offset] != c)
                moveRight();

            auto rVal = m_loc;
            m_loc = store;
            return rVal;
        }

    private:

        string deleteSelection(size_t from, size_t to)
        in
        {
            assert(from < m_text.length);
            assert(to < m_text.length);
            assert(to >= from);
        }
        body
        {
            auto removed = m_text[from..to];
            string newtext;
            if (from > 0)
                newtext = m_text[0..from] ~ m_text[to+1..$];
            else
                newtext = m_text[to+1..$];

            if (m_loc.offset != from && to-from > 0 )
                foreach(i; 0..(to-from) + 1)
                    moveLeft();

            m_seekColumn = m_loc.col;
            m_text = newtext;
            return removed;
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

        string m_text = "";

        // Default number of spaces for a tab
        uint m_tabSpaces = 4;

        // Current column and row of the caret (insertion point)
        Caret m_loc;

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
    size_t length;

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
        length ++;
        return newNode;
    }

    Node[] insertAfter(Range)(Node n, Range r) if (is(ElementType!Range == Span))
    {
        Node[] newNodes;
        foreach(s; r)
        {
            newNodes ~= insertAfter(n, s);
            n = n.next;
            length ++;
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
        length --;
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
        length -= removed.data.length;

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


class PieceTableTextArea : TextArea
{
    public:

        @property size_t row() const { return m_caret.row; }
        @property size_t col() const { return m_caret.col; }
        @property size_t offset() { return m_caret.offset; }
        @property size_t nLines() const { return m_totalNewLines + 1; }

        this()
        {
            m_spans = new SpanList();
        }

        this(string originalText)
        {
            this();
            loadOriginal(originalText);
        }

        /**
        * Set and clear all text
        */

        void set(string s)
        {
            loadOriginal(s);
            m_caret = Caret(0,0,0);
        }

        void clear()
        {
            m_original.clear;
            m_edit.clear;
            m_currentLine = null;
            m_totalNewLines = 0;
            m_spans.clear;
        }

        /**
        * Text insertion...
        */

        void insert(char s)
        {
            insertAt(m_edit, m_caret.offset, s.to!string);
        }

        void insert(string s)
        {
            insertAt(m_edit, m_caret.offset, s);
        }

        /**
        * Text deletion...
        */

        string del()
        {
            return remove(m_caret.offset, m_caret.offset);
        }

        string backspace()
        {
            if (m_caret.offset > 0)
                return remove(m_caret.offset-1, m_caret.offset-1);
            else return "";
        }

        string remove(size_t from, size_t to)
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
                return "";

            // Calculate new caret location
            auto totalDel = reduce!("a + b.newLines")(0, mods.del);
            auto removed = reduce!("a ~ b.buffer")("", mods.del);

            if (mods.lAdd !is null)
                totalDel -= mods.lAdd.payload.newLines;
            if (mods.rAdd !is null)
                totalDel -= mods.rAdd.payload.newLines;

            m_totalNewLines -= totalDel;
            auto length = to - from + 1; // this includes newlines

            if (from == m_caret.offset)
            {
                m_currentLine = byLine(m_caret.row).front; // optimize
                return removed;
            }

            m_caret.offset = from;

            if (totalDel > 0) // optimize for single newline deletion
                setCaret(from);
            else
                m_caret.col -= (length - totalDel);

            m_currentLine = byLine(m_caret.row).front; // optimize
            return removed;
        }

        /**
        * Text and caret retrieval...
        */

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

        string getTextLines(size_t from = 0, int n_lines = -1)
        {
            Appender!string text;

            auto range = byLine(from);
            size_t gotLines = 0;
            while(!range.empty && gotLines != n_lines)
            {
                text.put(range.front);
                text.put("\n");
                gotLines ++;
                range.popFront();
            }
            return text.data;
        }

        string getTextBetween(size_t from, size_t to)
        in
        {
            assert(from < to);
        }
        body
        {
            auto a = getCaret(from);
            auto b = getCaret(to);
            auto block = getTextLines(a.row, (b.row - a.row) + 1);
            return block[(a.col)..(a.col + (to-from))];
        }

        Caret getCaret(size_t index)
        {
            Caret result;

            size_t offset;
            auto r = byLine();
            while(!r.empty && result.offset + r.front.length + 1 < index)
            {
                result.offset += r.front.length + 1; // count the newline
                result.col = r.front.length;
                result.row ++;
                r.popFront();
            }

            if (r.empty)
                return result;

            if (index == result.offset + r.front.length + 1)
            {
                result.row ++;
                result.col = 0;
            }
            else
            {
                result.col = index - result.offset;
                result.offset += result.col;
            }

            return result;
        }

        Caret getCaret(ref const(Font) font, int x, int y)
        {
            Caret loc;

            if (m_spans.empty)
                return loc;

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
                loc.offset ++;
            }
            return loc;
        }

        int[2] getCaretPosition(ref const(Font) font)
        {
            int[2] loc;
            loc[1] = m_caret.row * font.m_lineHeight;

            size_t _x;
            while(_x < m_currentLine.length && _x != m_caret.col)
            {
                if (m_currentLine[_x] == '\t')
                    loc[0] += m_tabSpaces*font.width(' ');
                else
                    loc[0] += font.width(m_currentLine[_x]);
                _x ++;
            }

            return [loc.x, loc.y];
        }

        int[2] getCaretPosition(ref const(Font) font, Caret caret)
        {
            int[2] loc;
            loc[1] = caret.row * font.m_lineHeight;

            size_t _x;
            string line = byLine(caret.row).front;
            while(_x < line.length && _x != caret.col)
            {
                if (line[_x] == '\t')
                    loc[0] += m_tabSpaces*font.width(' ');
                else
                    loc[0] += font.width(line[_x]);
                _x ++;
            }

            return [loc.x, loc.y];
        }

        /**
        * Caret manipulation...
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
            if (isDelim(leftText) && !isBlank(leftText))
            {
                moveLeft();
                return;
            }

            while(isBlank(leftText) && moveLeft()){}
            while(!isDelim(leftText) && moveLeft()){}
        }

        void jumpRight()
        {
            if (isDelim(rightText) && !isBlank(rightText))
            {
                moveRight();
                return;
            }

            while(!isDelim(rightText) && moveRight()){}
            while(isBlank(rightText) && moveRight()){}
        }

        void home()
        {
            m_caret.offset -= m_caret.col;
            m_caret.col = 0;
            m_seekColumn = m_caret.col;
        }

        void end()
        {
            m_caret.offset += m_currentLine.length - m_caret.col;
            m_caret.col = m_currentLine.length;
            m_seekColumn = m_caret.col;
        }

        void gotoStartOfText()
        {
            setCaret(0);
        }

        void gotoEndOfText()
        {
            while(moveDown()) {}
            while(moveRight()) {}
        }

        void moveCaret(size_t newRow, size_t newCol)
        {
            //if (newRow == m_caret.row && newCol == m_caret.col)
            //    return;

            // Why is this so slow? It's O(n) currently...


            auto r = m_spans[];
            size_t cCol = 0, cRow = 0, cOff = 0;
            while(!r.empty && cRow + r.front.newLines < newRow)
            {
                cRow += r.front.newLines;
                cOff += r.front.length;
                r.popFront();
            }

            if (r.empty)
                assert(false);

            auto line = r.front.buffer;
            auto newAt = line.countUntil('\n');

            int i = 0;
            while(i < line.length && cRow != newRow)
            {
                if (line[i] == '\n')
                    cRow++;
                i++;
                cOff++;
            }

            while(i < line.length && cCol != newCol) // this could be optimized, but meh
            {
                i++;
                cCol++;
                cOff++;
            }

            m_caret.col = cCol;
            m_caret.row = cRow;
            m_caret.offset = cOff;
            m_seekColumn = cCol;
            m_currentLine = byLine(cRow).front;
        }

        int getLineWidth(ref const(Font) font, size_t line)
        {
            int width = font.width(' ');
            auto _line = byLine(line).front;
            foreach(char c; _line)
            {
                if (c == '\t')
                    width += m_tabSpaces * font.width(' ');
                else
                    width += font.width(c);
            }
            return width;
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

    private:

        void loadOriginal(string text)
        {
            clear();
            insertAt(m_original, 0, text);
            m_currentLine = byLine(0).front;
        }

        void setCaret(size_t index)
        {
            auto rc = getCaret(index);
            m_caret.row = rc.row;
            m_caret.col = rc.col;
            m_caret.offset = index;
            m_seekColumn = m_caret.col;
        }

        void insertAt(Appender!string buf, size_t index /** logical index **/, string s)
        {
            auto begin = buf.data.length;
            buf.put(s);

            // Split the span into managable chunks
            size_t spanSize = 2000;
            size_t newLines = 0;
            if (s.length > spanSize)
            {
                size_t grabbed = 0;

                while(grabbed != s.length)
                {
                    auto canGrab = min(s.length - grabbed, spanSize); // elements left to take
                    auto loIndex = begin + grabbed;
                    auto hiIndex = begin + grabbed + canGrab;

                    auto newSpan = Span(buf.data[loIndex..hiIndex]);
                    auto newNode = m_spans.insertAt(index + grabbed, newSpan);
                    newLines += newSpan.newLines;
                    grabbed += canGrab;
                }
            }
            else
            {
                auto newSpan = Span(buf.data[begin..$]);
                auto newNode = m_spans.insertAt(index, newSpan);
                newLines += newSpan.newLines;
            }

            m_totalNewLines += newLines;

            if (index == m_caret.offset)
            {
                if (newLines > 0)
                {
                    m_caret.row += newLines;
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

        Appender!string m_original;
        Appender!string m_edit;
        SpanList m_spans;
        Caret m_caret;

        uint m_tabSpaces = 4;
        uint m_totalNewLines;
        public string m_currentLine;

        size_t m_seekColumn;
}

unittest
{

    /++
    import std.file;
    import glui.truetype, glui.window;


    string readIn = readText("c:/d/dmd2/src/phobos/std/datetime.d");
    auto text = new PieceTableTextArea(readIn);
    auto a = benchmark!( { text.moveCaret(15000, 10); } )(100);
    writeln("Msecs: ", a[0].to!("msecs", int));

    assert(false, "End of Test");
    ++/

/++
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

