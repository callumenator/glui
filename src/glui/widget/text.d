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
        @property TextArea textArea() { return m_text; }
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

                renderHighlights(); // line highlights
                renderSelection(); // text selection

                auto startRow = m_allowVScroll ? m_vscroll.current : 0;
                auto stopRow = m_dim.y / m_font.m_lineHeight;
                auto _text = m_text.getTextLines(startRow, stopRow);

                if (m_highlighter)
                {
                    auto h = m_highlighter.highlight(m_text.getText(), startRow, stopRow);
                    renderCharacters(m_font, h);
                    //renderCharacters(m_font, _text, m_highlighter);
                }
                else
                {
                    renderCharacters(m_font, _text, m_textColor);
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
                drawBox(offset0[0], -offset0[1] - m_font.m_maxHoss,
                        offset1[0], -offset0[1] + m_font.m_maxHeight,
                        selectionColor);
            }
            else
            {
                // Only draw the visible part of the selection
                auto lineRange0 = startRow;
                auto lineRange1 = startRow + cast(int)(m_dim.y/m_font.m_lineHeight) - 1;

                // Quick rejection tests
                if (lowerCaret.row > lineRange1 || upperCaret.row < lineRange0)
                    return;

                // Draw first selection row
                drawBox(offset0.x,
                        -offset0.y - m_font.m_maxHoss,
                        offset0.x + m_text.getLineWidth(m_font, lowerCaret.row),
                        -offset0.y + m_font.m_maxHeight,
                        selectionColor);

                // Draw last selection row
                drawBox(0,
                        -offset1.y - m_font.m_maxHoss,
                        offset1.x,
                        -offset1.y + m_font.m_maxHeight,
                        selectionColor);

                // Draw rows in-between
                if (upperCaret.row > lowerCaret.row + 1)
                {
                    foreach(int row; lowerCaret.row+1..upperCaret.row)
                    {
                        if (row < lineRange0)
                            continue;
                        if (row > lineRange1)
                            return;

                        float y0 = -offset0.y - (row - cast(int)(lowerCaret.row))*m_font.m_lineHeight;
                        drawBox(0,
                                y0 - m_font.m_maxHoss,
                                m_text.getLineWidth(m_font, row),
                                y0 + m_font.m_maxHeight,
                                selectionColor);
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
                case MOUSEHOLD:
                {
                    if (amIDragging &&
                        (m_allowVScroll && root.mouse.ypos > m_screenPos.y + m_dim.y ||
                         m_allowVScroll && root.mouse.ypos < m_screenPos.y ||
                         m_allowHScroll && root.mouse.xpos > m_screenPos.x + m_dim.x ||
                         m_allowHScroll && root.mouse.xpos < m_screenPos.x ))
                    {
                        drag(root.mouse.pos, [0,0]);
                        adjustVisiblePortion();
                    }
                    break;
                }
                case MOUSECLICK:
                {
                    auto preOffset = m_text.offset;
                    auto pos = event.get!MouseClick.pos;
                    auto rc = getCaret(pos.x, pos.y);

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
                case MOUSEWHEEL:
                {
                    if (ctrlIsDown)
                        changeFontSize(2 * event.get!MouseWheel.delta / 120);

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

                        // If current line is indented replicate for the new line
                        auto cCol = m_text.col;
                        auto cLine = m_text.getCurrentLine();
                        m_text.insert("\n");

                        auto r = cLine.save();
                        auto c = 0;
                        while(c < cCol && !r.empty && (r.front.isWhite()))
                        {
                            c ++;
                            m_text.insert(r.front.to!char); // unicode!!
                            r.popFront();
                        }

                        if (m_autoBraceIndent) // If current line ends with an lbrace, check for auto indent
                        {
                            auto stripped = stripRight(cLine);
                            if (cCol >= stripped.length && stripped.length >= 1 && stripped[$-1] == '{')
                                m_text.insert("\t");
                        }

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
                            case KC_Z: // undo or redo, depending on shift
                            {
                                if (root.shiftIsDown)
                                    m_text.redo();
                                else
                                    m_text.undo();

                                adjustVisiblePortion();
                                m_drawCaret = true;
                                m_refreshCache = true;
                                needRender();
                                break;
                            }

                            default: break;
                        }
                    }
                    else if (m_editable)
                    {
                        deleteSelectedText();

                        if (key == KC_BRACERIGHT && m_autoBraceIndent)
                            closeBraceIndent();

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

        void closeBraceIndent()
        {
            auto cLine = m_text.getCurrentLine();
            if (m_text.row > 0 && m_autoBraceIndent && strip(cLine).empty) // check for auto indent
            {
                bool found = false;
                int depth = 0;
                int lineNum = m_text.row-1;
                auto pLine = m_text.getLine(lineNum);
                while(lineNum >= 0)
                {
                    foreach(c; retro(pLine))
                    {
                        if (c == '}')
                            depth ++;
                        else if (c == '{')
                        {
                            if (depth == 0)
                            {
                                found = true;
                                break;
                            }
                            else
                                depth --;
                        }
                    }

                    if (found)
                        break;

                    lineNum --;
                    pLine = m_text.getLine(lineNum);
                }

                if (found)
                {
                    // Delete all indent on the current line
                    while(m_text.col > 0)
                        m_text.backspace();

                    // Count indent on line with brace
                    foreach(c; pLine)
                    {
                        if (c != '\t' && c != '\n')
                            break;
                        else
                            m_text.insert(c);
                    }
                }
            }
        }

        void changeFontSize(int delta)
        {
            if (!m_font)
                return;

            auto newSize = cast(int)(m_font.m_ptSize + delta);
            if (newSize < 4)
                return;

            auto newFont = loadFont(m_font.filename, newSize);

            if (newFont)
            {
                m_font = newFont;
                adjustVisiblePortion();
                m_refreshCache = true;
                needRender();
            }
        }

    private:

        TextArea m_text;
        Font m_font = null;

        KEY m_lastKey = KEY.KC_NULL;

        RGBA m_textColor = {1,1,1,1};
        RGBA m_textBgColor = {0,0,0,0};

        WidgetScroll m_vscroll;
        WidgetScroll m_hscroll;
        bool m_allowVScroll = false;
        bool m_allowHScroll = false;

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
    * Return the entire text sequence.
    */
    string getText();

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

    void undo();

    void redo();

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

        override @property size_t col() const { return m_loc.col; }
        override @property size_t row() const { return m_loc.row; }
        override @property size_t offset() const { return m_loc.offset; }
        override @property size_t nLines() const { return m_text.count('\n') + 1; }

        /**
        * Set and clear all text
        */

        override void set(string s)
        {
            m_text.clear;
            m_loc.offset = 0;
            insert(s);
        }

        override void clear()
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

        override void insert(char c)
        {
            insert(c.to!string);
        }

        override void insert(string s)
        {
            insertInPlace(m_text, m_loc.offset, s);

            foreach(i; 0..s.length)
                moveRight();

            m_seekColumn = m_loc.col;
        }

        /**
        * Text deletion...
        */

        override string del()
        {
            if (m_loc.offset < m_text.length)
                return deleteSelection(m_loc.offset, m_loc.offset);
            else return "";
        }

        override string backspace()
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

        override string remove(size_t from, size_t to)
        {
            return deleteSelection(from, to);
        }

        /**
        * Text and caret retrieval...
        */

        override string getText()
        {
            return m_text;
        }

        override char leftText()
        {
            if (m_loc.offset <= 0)
                return cast(char)0;

            return m_text[m_loc.offset-1];
        }

        override char rightText()
        {
            if (cast(int)(m_loc.offset) > cast(int)(m_text.length - 1))
                return cast(char)0;

            return m_text[m_loc.offset];
        }

        override string getLine(uint _row)
        {
            auto lines = splitLines(m_text);
            if (_row < lines.length)
                return lines[_row];
            else
                return "";
        }

        override string getCurrentLine()
        {
            return getLine(row);
        }

        override string getTextLines(size_t from = 0, int n_lines = -1)
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

        override string getTextBetween(size_t from, size_t to)
        in
        {
            assert(from < to);
            assert(from > 0 && to < m_text.length);
        }
        body
        {
            return m_text[from..to+1];
        }

        override Caret getCaret(size_t index)
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

        override Caret getCaret(ref const(Font) font, int x, int y)
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

        override int[2] getCaretPosition(ref const(Font) font)
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

        override int[2] getCaretPosition(ref const(Font) font, Caret caret)
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

        override bool moveLeft()
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

        override bool moveRight()
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

        override bool moveUp()
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

        override bool moveDown()
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

        override void jumpLeft()
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

        override void jumpRight()
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

        override void home() // home key
        {
            while (m_loc.col != 0)
                moveLeft();
            m_seekColumn = m_loc.col;
        }

        override void end() // end key
        {
            if (m_loc.offset == m_text.length)
                return;

            while(m_loc.offset < m_text.length && m_text[m_loc.offset] != '\n')
                moveRight();

            m_seekColumn = m_loc.col;
        }

        override void gotoStartOfText()
        {
            while(m_loc.offset > 0)
                moveLeft();
            m_seekColumn = m_loc.col;
        }

        override void gotoEndOfText()
        {
            while(m_loc.offset < m_text.length)
                moveRight();
            m_seekColumn = m_loc.col;
        }

        override void moveCaret(uint newRow, uint newCol)
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

        override int getLineWidth(ref const(Font) font, size_t line)
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

        override void undo()
        {
        }

        override void redo()
        {
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


struct Stack(T)
{
    SList!T stack;
    alias stack this;

    T pop()
    {
        return stack.removeAny();
    }

    T top()
    {
        return stack.front();
    }

    ref Stack!T push(T v)
    {
        stack.insertFront(v);
        return this;
    }

    bool empty() const
    {
        return stack.empty();
    }
}


struct Span
{
    string* buffer;
    size_t offset;
    size_t length;
    size_t newLines;

    this(string* _buffer, size_t _offset, size_t _length)
    {
        buffer = _buffer;
        offset = _offset;
        length = _length;
        countNewLines();
    }

    /**
    * Count number of newlines in the buffer
    */
    size_t countNewLines()
    {
        newLines = 0;
        foreach(char c; spannedText())
            if (c == '\n')
                newLines ++;

        return newLines;
    }

    string spannedText()
    in
    {
        assert(buffer !is null);
    }
    body
    {
        return (*buffer)[offset..offset+this.length];
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
        assert(splitAt > 0 && splitAt < length);
    }
    body
    {
        auto left = Span(buffer, offset, splitAt);
        auto right = Span(buffer, offset + splitAt, length - splitAt);
        return tuple(left, right);
    }
}

class Node
{
    Node prev, next;
    Span payload;

    this() {}
    this(Span data) { payload = data; }
    this(Node n) { prev = n.prev; next = n.next; payload = n.payload; }
}

class SpanList
{
    Node head, tail; // sentinels
    size_t length;   // this is the number of nodes
    Tuple!(Node,"node",size_t,"index") lastInsert;
    Tuple!(Node,"node",size_t,"index") lastRemove;
    string dummy = "DUMMY";

    struct Change
    {
        enum Action {INSERT, REMOVE, GROW, SHRINK_LEFT, SHRINK_RIGHT}

        int v, n; // change in length, change in newlines
        Node node;
        Action action;

        this(Node _node, Action _action, int _v = 0, int _n = 0)
        {
            v = _v;
            n = _n;
            node = _node;
            action = _action;
        }
    }

    Stack!Change undoStack;
    Stack!Change redoStack;
    Stack!int undoSize; // number of Changes to pop off stack to undo last change
    Stack!int redoSize; // ditto for redo

    this()
    {
        clear();
    }

    @property bool empty() { return head.next == tail && tail.prev == head; };
    @property ref Span front() { return head.next.payload; }
    @property ref Span back() { return tail.prev.payload; }
    @property Node frontNode() { return head.next; }
    @property Node backNode() { return tail.prev; }

    Node insertAfter()(Node n, Node newNode)
    {
        newNode.next = n.next;
        newNode.prev = n;
        n.next.prev = newNode;
        n.next = newNode;
        length ++;
        return newNode;
    }

    Node insertAfter()(Node n, Span payload)
    {
        auto newNode = new Node(payload);
        return insertAfter(n, newNode);
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
    Node insertAt(size_t index, Span s, bool allowMerge = true)
    {
        // Grow the last-used node if possible
        if (allowMerge && lastInsert.node !is null && index == lastInsert.index)
        {
            lastInsert.node.payload.length += s.length;
            lastInsert.node.payload.newLines += s.newLines;

            lastInsert.index = index + s.length;
            undoStack.push( Change(lastInsert.node, Change.Action.GROW, s.length, s.newLines) );
            undoSize.push(1);
            return lastInsert.node;
        }

        // Could not grow last node, so create a new one
        Node newNode = null;

        if (index == 0)
        {
            newNode = insertAfter(head, s);
            undoStack.push( Change(newNode, Change.Action.INSERT) );
            undoSize.push(1);
        }
        else
        {
            auto found = findNode(index);

            if (found.node is head || found.node is tail)
            {
                newNode = insertBack(s);
                undoStack.push( Change(newNode, Change.Action.INSERT) );
                undoSize.push(1);
            }
            else if (found.offset == 0)
            {
                newNode = insertBefore(found.node, s);
                undoStack.push( Change(newNode, Change.Action.INSERT) );
                undoSize.push(1);
            }
            else if (found.offset == found.span.length)
            {
                newNode = insertAfter(found.node, s);
                undoStack.push( Change(newNode, Change.Action.INSERT) );
                undoSize.push(1);
            }
            else
            {
                auto splitNode = found.span.split(found.offset);
                auto newNodes = insertAfter(found.node, [splitNode[0], s, splitNode[1]]);
                foreach(node; newNodes)
                    undoStack.push( Change(node, Change.Action.INSERT) );

                remove(found.node);
                undoStack.push( Change(found.node, Change.Action.REMOVE) );
                undoSize.push(newNodes.length + 1);

                newNode = newNodes[1];
            }
        }

        lastInsert.index = index + s.length;
        lastInsert.node = newNode;
        return newNode;
    }

    /**
    * Remove a single Node
    */
    string remove(Node node)
    {
        node.prev.next = node.next;
        node.next.prev = node.prev;
        length --;
        return node.payload.spannedText();
    }

    /**
    * Remove all Nodes between left and right, inclusive.
    * Returns: An array of Spans which were removed.
    */
    string remove(Node lNode, Node rNode, ref size_t undoCount)
    in
    {
        assert(lNode !is head && lNode !is tail);
        assert(rNode !is head && rNode !is tail);
    }
    body
    {
        lNode.prev.next = rNode.next;
        rNode.next.prev = lNode.prev;

        if (lNode is rNode)
        {
            remove(lNode);
            undoStack.push( Change( lNode, Change.Action.REMOVE) );
            undoCount ++;
            return lNode.payload.spannedText();
        }

        Appender!string removed;
        while(lNode !is rNode)
        {
            removed.put( lNode.payload.spannedText() );
            undoStack.push( Change( lNode, Change.Action.REMOVE) );
            undoCount ++;
            lNode = lNode.next;
        }
        removed.put( rNode.payload.spannedText() );
        length -= removed.data.length;

        return removed.data;
    }

    /**
    * Remove spans covering a arange of logical indices, taking
    * care of fractional spans (from and to are inclusive).
    * Returns: A Tuple containing an array of Spans removed, and
    * spans inserted at the left and right 'edges' of the removed Spans.
    */
    string remove(size_t from, size_t to)
    in
    {
        assert(from <= to);
    }
    body
    {
        string removed;

        auto left = findNode(from);
        if (left.node is tail)
            return removed;

        auto right = findNode(to);
        if (right.node is tail)
        {
            right.node = right.node.prev;
            right.span = right.node.payload;
            right.offset = right.span.length - 1;
        }

        size_t undoCount = 0;

        // If the left and right node are the same, we may be able to shrink
        if (left.node is right.node)
        {
            // Try to shrink from left or right
            size_t len = right.offset - left.offset + 1;
            if (left.offset == 0)
            {
                removed = shrinkLeft(left.node, len, undoCount);
                undoSize.push(1);
                return removed;
            }
            else if (right.offset >= left.span.length - 1)
            {
                removed = shrinkRight(left.node, len, undoCount);
                undoSize.push(1);
                return removed;
            }
            // else fall through to generic remove
        }

        size_t lOff = 0, rOff = 0; // offsets frmo left and right edge
        if (left.offset > 0) with(left.node.payload) // Insert a node/span for the left edge of the left node
        {
            lOff = left.offset;
            auto newSpan = Span(buffer, offset, left.offset);
            auto newNode = insertBefore(left.node, newSpan);
            undoStack.push( Change(newNode, Change.Action.INSERT) );
            undoCount ++;
        }

        if (right.offset < right.span.length - 1) with(right.node.payload)
        {
            rOff = length - right.offset - 1;
            auto newSpan = Span(buffer, offset + right.offset + 1, length - (right.offset + 1));
            auto newNode = insertAfter(right.node, newSpan);
            undoStack.push( Change(newNode, Change.Action.INSERT) );
            undoCount ++;
        }

        removed = remove(left.node, right.node, undoCount);
        undoSize.push(undoCount);
        return removed[lOff..$-rOff];
    }

    unittest /** remove **/
    {
        string buffer = "this is a test buffer for running tests\non the" ~
                        " functions found in the SpanList class blah blah";

        auto l = new SpanList();
        l.insertAt(0, Span(&buffer, 0, buffer.length));

        // Shrinking removes
        //writeln("TEST SHRINK LEFT RIGHT");
        assert(l.remove(0, 5) == "this i");
        assert(l.remove(0, 9) == "s a test b");
        assert(l[].front.spannedText() == "uffer for running tests\non the" ~
                        " functions found in the SpanList class blah blah");
        assert(l.remove(49, 100) == " the SpanList class blah blah");

        l.clear();

        // Remove part of adjacent spans
        //writeln("TEST [xxx|xx][xx|xx]");
        l.insertAt(0, Span(&buffer, 0, 35));
        l.insertAt(-1, Span(&buffer, 35, buffer.length - 35));
        auto s = l[];
        assert(s.front.spannedText() == "this is a test buffer for running t");
        s.popFront();
        assert(s.front.spannedText() == "ests\non the functions found in the SpanList class blah blah");
        assert(l.remove(30, 40) == "ing tests\no");

        l.clear();

        // Remove all of left span and part of adjacent right span
        //writeln("TEST |xxxxx][xx|xx]");
        l.insertAt(0, Span(&buffer, 0, 35));
        l.insertAt(-1, Span(&buffer, 35, buffer.length - 35));
        assert(l.remove(0, 40) == "this is a test buffer for running tests\no");
        assert(l[].front.spannedText() == "n the functions found in the SpanList class blah blah");

        l.clear();

        // Remove part of left span and all of adjacent right span
        //writeln("TEST [xx|xxx][xxxx|");
        l.insertAt(0, Span(&buffer, 0, 35));
        l.insertAt(-1, Span(&buffer, 35, buffer.length - 35));
        assert(l.remove(30, 100) == "ing tests\non the functions found in the SpanList class blah blah");
        assert(l[].front.spannedText() == "this is a test buffer for runn");

        l.clear();

        // Remove part of left span, middle spans, and part of right span
        //writeln("TEST [xx|xxx][xxxx][xxxx][xx|xx]");
        l.insertAt(0, Span(&buffer, 0, 20));
        l.insertAt(-1, Span(&buffer, 20, 20));
        l.insertAt(-1, Span(&buffer, 40, 20));
        l.insertAt(-1, Span(&buffer, 60, 34));
        assert(l[].back.spannedText() == "nd in the SpanList class blah blah");
        assert(l.remove(5, 65) == "is a test buffer for running tests\non the functions found in ");
        s = l[];
        assert(s.front.spannedText() == "this ");
        s.popFront();
        assert(s.front.spannedText() == "the SpanList class blah blah");

        l.clear();

        // Remove all of left span, middle spans, and part of right span
        //writeln("TEST |xxxxx][xxxx][xxxx][xx|xx]");
        l.insertAt(0, Span(&buffer, 0, 20));
        l.insertAt(-1, Span(&buffer, 20, 20));
        l.insertAt(-1, Span(&buffer, 40, 20));
        l.insertAt(-1, Span(&buffer, 60, 34));
        assert(l.remove(0, 65) == buffer[0..66]);
        assert(l[].front.spannedText() == buffer[66..$]);

        l.clear();

        // Remove part of left span, middle spans, and all of the right span
        //writeln("TEST [xx|xxx][xxxx][xxxx][xxxx|");
        l.insertAt(0, Span(&buffer, 0, 20));
        l.insertAt(-1, Span(&buffer, 20, 20));
        l.insertAt(-1, Span(&buffer, 40, 20));
        l.insertAt(-1, Span(&buffer, 60, 34));
        assert(l.remove(5, 94) == buffer[5..94]);
        assert(l[].front.spannedText() == buffer[0..5]);

        l.clear();

        // Remove one middle span
        //writeln("TEST [xxxxx]|xxxx|[xxxx][xxxx]");
        l.insertAt(0, Span(&buffer, 0, 20));
        l.insertAt(-1, Span(&buffer, 20, 20));
        l.insertAt(-1, Span(&buffer, 40, 20));
        l.insertAt(-1, Span(&buffer, 60, 34));
        assert(l.remove(20, 39) == buffer[20..40]);
    }

    /**
    * Shrink a node's payload by increasing the left edge. Shrink occurs in-place.
    */
    string shrinkLeft(Node node, size_t shrinkBy, ref size_t undoCount)
    {
        auto del = (node.payload.spannedText())[0 .. shrinkBy];
        auto newLines = del.count('\n');
        auto newLen = node.payload.length - shrinkBy;

        if (newLen == 0)
        {
            undoStack.push( Change(node, Change.Action.REMOVE) );
            remove(node);
        }
        else
        {
            undoStack.push( Change(node, Change.Action.SHRINK_LEFT, shrinkBy, newLines) );
            node.payload.length -= shrinkBy;
            node.payload.offset += shrinkBy;
            node.payload.newLines -= newLines;
        }

        undoCount ++;
        return del;
    }

    /**
    * Shrink a node's payload by reducing the right edge. Shrink occurs in-place.
    */
    string shrinkRight(Node node, size_t shrinkBy, ref size_t undoCount)
    {
        auto del = (node.payload.spannedText())[$ - shrinkBy .. $];
        auto newLines = del.count('\n');
        auto newLen = node.payload.length - shrinkBy;

        if (newLen == 0)
        {
            undoStack.push( Change(node, Change.Action.REMOVE) );
            remove(node);
        }
        else
        {
            undoStack.push( Change(node, Change.Action.SHRINK_RIGHT, shrinkBy, newLines) );
            node.payload.length -= shrinkBy;
            node.payload.newLines -= newLines;
        }

        undoCount ++;
        return del;
    }

    unittest /** shrink **/
    {
        string buffer = "abcdefghijklmnop";
        auto l = new SpanList();
        auto n = new Node();
        n.next = n; // dummies so that remove works
        n.prev = n; // ditto
        auto s = Span(&buffer, 0, buffer.length);

        n.payload = s;
        size_t undoCount;
        auto res = l.shrinkLeft(n, 5, undoCount);
        assert(res == "abcde", "Shrink left fail 1: " ~ res);
        assert(n.payload.spannedText() == "fghijklmnop", "Shrink left fail 2: " ~ n.payload.spannedText());

        res = l.shrinkLeft(n, 11, undoCount);
        assert(res == "fghijklmnop", "Shrink left fail 1: " ~ res);

        n.payload = s;
        res = l.shrinkRight(n, 7, undoCount);
        assert(res == "jklmnop", "Shrink right fail 1: " ~ res);
        assert(n.payload.spannedText() == "abcdefghi", "Shrink right fail 2: " ~ n.payload.spannedText());

        res = l.shrinkRight(n, 9, undoCount);
        assert(res == "abcdefghi", "Shrink right fail 1: " ~ res);
    }

    /**
    * Pop one element off the undo stack, and undo it.
    */
    Change[] undo()
    {
        Change[] changes;
        if (undoStack.empty)
            return changes;

        auto nels = undoSize.pop();
        changes.length = nels;

        foreach(i; 0..nels)
        {
            auto change = undoStack.pop();
            redoStack.push(change);

            final switch (change.action) with(Change.Action)
            {
                case INSERT: // undoing an insert
                    remove(change.node);
                    break;
                case REMOVE: // undoing a remove
                    insertAfter(change.node.prev, change.node);
                    break;
                case GROW: // undoing a grow
                    change.node.payload.length -= change.v;
                    change.node.payload.newLines -= change.n;
                    break;
                case SHRINK_LEFT: // undoing a left shrink
                    change.node.payload.offset -= change.v;
                    change.node.payload.length += change.v;
                    change.node.payload.newLines += change.n;
                    break;
                case SHRINK_RIGHT: // undoing a right shrink
                    change.node.payload.length += change.v;
                    change.node.payload.newLines += change.n;
                    break;
            }

            changes[i] = change;
        }
        redoSize.push(nels);
        return changes;
    }

    /**
    * Merge the last n operations into one
    */
    void mergeUndoStack(size_t n)
    {
        int size = 0;
        foreach(i; 0..n)
            size += undoSize.pop();

        undoSize.push(size);
    }

    void clearUndoStack()
    {
        undoStack.clear;
        redoStack.clear;
        undoSize.clear;
        redoSize.clear;
    }

    Change[] redo()
    {
        Change[] changes;
        if (redoStack.empty)
            return changes;

        auto nels = redoSize.pop();
        changes.length = nels;

        foreach(i; 0..nels)
        {
            auto change = redoStack.pop();
            undoStack.push(change);

            final switch (change.action) with(Change.Action)
            {
                case INSERT: // redoing an insert
                    insertAfter(change.node.prev, change.node);
                    break;
                case REMOVE: // redoing a remove
                    remove(change.node);
                    break;
                case GROW: // redoing a grow
                    change.node.payload.length += change.v;
                    change.node.payload.newLines += change.n;
                    break;
                case SHRINK_LEFT: // redoing a left shrink
                    change.node.payload.offset += change.v;
                    change.node.payload.length -= change.v;
                    change.node.payload.newLines -= change.n;
                    break;
                case SHRINK_RIGHT: // redoing a right shrink
                    change.node.payload.length -= change.v;
                    change.node.payload.newLines -= change.n;
                    break;
            }

            changes[i] = change;
        }
        undoSize.push(nels);
        return changes;
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

            if (idx >= offset && idx < offset + c.payload.length)
            {
                result.span = c.payload;
                result.node = c;
                result.offset = spanOffset;
                return result;
            }

            offset += c.payload.length;
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
            return first is null || first.next is null;
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
        length = 0;
        head = new Node;
        tail = new Node;
        head.payload = Span(&dummy, 0, dummy.length);
        tail.payload = Span(&dummy, 0, dummy.length);
        head.next = tail;
        tail.prev = head;
    }
}


class PieceTableTextArea : TextArea
{
    public:

        override @property size_t row() const { return m_caret.row; }
        override @property size_t col() const { return m_caret.col; }
        override @property size_t offset() { return m_caret.offset; }
        override @property size_t nLines() const { return m_totalNewLines + 1; }

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

        override void set(string s)
        {
            loadOriginal(s);
            m_caret = Caret(0,0,0);
        }

        override void clear()
        {
            m_caretUndoStack.clear;
            m_original.clear;
            m_edit.clear;
            m_currentLine = null;
            m_totalNewLines = 0;
            m_spans.clear;
        }

        /**
        * Text insertion...
        */

        override void insert(char s)
        {
            insertAt(&m_edit, m_caret.offset, s.to!string, true);
        }

        override void insert(string s)
        {
            insertAt(&m_edit, m_caret.offset, s, true);
        }

        /**
        * Text deletion...
        */

        override string del()
        {
            return remove(m_caret.offset, m_caret.offset);
        }

        override string backspace()
        {
            if (m_caret.offset > 0)
                return remove(m_caret.offset-1, m_caret.offset-1);
            else return "";
        }

        override string remove(size_t from, size_t to)
        in
        {
            //assert(from < to);
            //writeln("REMOVE: ", from, ", ", to);
            //assert(from == m_caret.offset || to == m_caret.offset);
        }
        body
        {
            m_caretUndoStack.push(m_caret);

            auto removed = m_spans.remove(from, to);

            if (removed.length == 0)
                return "";

            // Calculate new caret location
            auto totalDel = removed.count('\n');
            m_totalNewLines -= totalDel;
            auto length = to - from + 1; // this includes newlines
            m_totalChars -= length;

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

            m_seekColumn = m_caret.col;
            m_currentLine = byLine(m_caret.row).front; // optimize

            return removed;
        }

        /**
        * Text and caret retrieval...
        */

        override string getText()
        {
            char[] buffer;
            buffer.length = m_totalChars;

            size_t c;
            auto r = m_spans[];
            while(!r.empty)
            {
                buffer[c..c+r.front.length] = r.front.spannedText();
                c += r.front.length;
                r.popFront();
            }

            return cast(string)buffer;
        }

        override char leftText()
        {
            if (m_caret.offset == 0)
                return cast(char)0;
            else if (m_caret.col == 0)
                return '\n';
            else return m_currentLine[m_caret.col-1];
        }

        override char rightText()
        {
            if (m_caret.row == m_totalNewLines && m_caret.col == m_currentLine.length)
                return cast(char)0;
            else if (m_caret.col == m_currentLine.length)
                return '\n';
            else return m_currentLine[m_caret.col];
        }

        override string getLine(size_t line)
        {
            if (line == m_caret.row)
                return m_currentLine;
            else
                return byLine(line).front;
        }

        override string getCurrentLine()
        {
            return m_currentLine;
        }

        override string getTextLines(size_t from = 0, int n_lines = -1)
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

        override string getTextBetween(size_t from, size_t to)
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
        override Caret getCaret(size_t index)
        {
            Caret loc;

            auto r = m_spans[];
            while(!r.empty && loc.offset + r.front.length < index)
            {
                loc.offset += r.front.length;
                loc.row += r.front.newLines;
                r.popFront();
            }

            if (r.empty)
                return loc;

            int i = 0;
            auto text = r.front.spannedText();
            while(i < r.front.length && loc.offset != index)
            {
                if (text[i] == '\n')
                    loc.row ++;

                loc.offset ++;
                i++;
            }

            loc.col = loc.offset - byLine(loc.row).offset;
            return loc;
        }

        override Caret getCaret(ref const(Font) font, int x, int y)
        {
            Caret loc;

            if (m_spans.empty)
                return loc;

            // row is determined solely by font.m_lineHeight
            loc.row = cast(int) (y / font.m_lineHeight);
            loc.row = min(loc.row, m_totalNewLines);

            auto r = byLine(loc.row);
            loc.offset = r.offset;

            float _x = 0;
            foreach(char c; r.front)
            {
                if (_x > x || std.math.abs(_x - x) < 3)
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

        override int[2] getCaretPosition(ref const(Font) font)
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

        override int[2] getCaretPosition(ref const(Font) font, Caret caret)
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

        override bool moveLeft()
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

        override bool moveRight()
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

        override bool moveUp()
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

        override bool moveDown()
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

        override void jumpLeft()
        {
            if (isDelim(leftText) && !isBlank(leftText))
            {
                moveLeft();
                return;
            }

            while(isBlank(leftText) && moveLeft()){}
            while(!isDelim(leftText) && moveLeft()){}
        }

        override void jumpRight()
        {
            if (isDelim(rightText) && !isBlank(rightText))
            {
                moveRight();
                return;
            }

            while(!isDelim(rightText) && moveRight()){}
            while(isBlank(rightText) && moveRight()){}
        }

        override void home()
        {
            if (strip(m_currentLine[0..m_caret.col]).empty)
            {
                m_caret.offset -= m_caret.col;
                m_caret.col = 0;
                m_seekColumn = m_caret.col;
            }
            else
            {
                while(m_caret.col > 0 && !strip(m_currentLine[0..m_caret.col]).empty)
                    moveLeft();
            }
        }

        override void end()
        {
            m_caret.offset += m_currentLine.length - m_caret.col;
            m_caret.col = m_currentLine.length;
            m_seekColumn = m_caret.col;
        }

        override void gotoStartOfText()
        {
            setCaret(0);
        }

        override void gotoEndOfText()
        {
            while(moveDown()) {}
            while(moveRight()) {}
        }

        override void moveCaret(size_t newRow, size_t newCol)
        {
            if (newRow == m_caret.row && newCol == m_caret.col)
                return;

            size_t cCol = 0, cOff = 0, cRow = newRow;
            auto r = byLine(newRow);
            cOff = r.offset;
            int i;
            while(i < r.front.length && cCol != newCol)
            {
                cOff ++;
                cCol ++;
            }

            m_caret.col = cCol;
            m_caret.row = cRow;
            m_caret.offset = cOff;
            m_seekColumn = cCol;
            m_currentLine = r.front;
        }

        override int getLineWidth(ref const(Font) font, size_t line)
        {
            int width = font.width(' ');
            string _line = m_currentLine;
            if (line != m_caret.row)
                _line = byLine(line).front;
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
            size_t offset;
            bool finished;

            this(SpanList.Range list, size_t startLine)
            {
                r = list;
                size_t bufferStartRow = 0;
                while(!r.empty && bufferStartRow + r.front.newLines < startLine)
                {
                    bufferStartRow += r.front.newLines;
                    offset += r.front.length;
                    r.popFront();
                }

                if (r.empty)
                    return;

                int chomp = 0;
                buffer = r.front.spannedText();
                r.popFront();
                if (bufferStartRow != startLine)
                {
                    uint i = 0;
                    while(i < buffer.length && bufferStartRow != startLine)
                    {
                        if (buffer[i] == '\n')
                            bufferStartRow ++;
                        chomp ++;
                        i++;
                    }
                    buffer = buffer[chomp..$];
                    offset += chomp;
                }

                // Fill up the buffer with at least one line
                if (count(buffer, '\n') == 0)
                {
                    int gotNewlines = 0;
                    while(!r.empty && gotNewlines == 0)
                    {
                        buffer ~= r.front.spannedText();
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
                {
                    buffer = buffer[newAt+1..$];
                    offset += newAt + 1;
                }
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
                        buffer ~= r.front.spannedText();
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

        override void undo()
        {
            auto changes = m_spans.undo();
            if (changes.length == 0)
                return;

            foreach(change; changes)
            {
                final switch (change.action) with(SpanList.Change.Action)
                {
                    case INSERT: // undoing a previous insert
                        m_totalNewLines -= change.node.payload.newLines;
                        break;
                    case REMOVE: // undoing a previous remove
                        m_totalNewLines += change.node.payload.newLines;
                        break;
                    case GROW: // undoing a previous grow
                        m_totalNewLines -= change.n;
                        break;
                    case SHRINK_LEFT: // undoing a previous shrink_left
                        m_totalNewLines += change.n;
                        break;
                    case SHRINK_RIGHT: // undoing a previous shrink_right
                        m_totalNewLines += change.n;
                        break;
                }
            }

            m_caretRedoStack.push(m_caret);
            m_caret = m_caretUndoStack.pop();
            m_currentLine = byLine(m_caret.row).front;
        }

        override void redo()
        {
            auto changes = m_spans.redo();
            if (changes.length == 0)
                return;

            foreach(change; changes)
            {
                final switch (change.action) with(SpanList.Change.Action)
                {
                    case INSERT: // redoing a previous insert
                        m_totalNewLines += change.node.payload.newLines;
                        break;
                    case REMOVE: // redoing a previous remove
                        m_totalNewLines -= change.node.payload.newLines;
                        break;
                    case GROW: // redoing a previous grow
                        m_totalNewLines += change.n;
                        break;
                    case SHRINK_LEFT: // redoing a previous shrink_left
                        m_totalNewLines -= change.n;
                        break;
                    case SHRINK_RIGHT: // redoing a previous shrink_right
                        m_totalNewLines -= change.n;
                        break;
                }
            }

            m_caretUndoStack.push(m_caret);
            m_caret = m_caretRedoStack.pop();
            m_currentLine = byLine(m_caret.row).front;
        }

    private:

        void loadOriginal(string text)
        {
            clear();
            insertAt(&m_original, 0, text, false);
            m_currentLine = byLine(0).front;
            m_spans.clearUndoStack();
        }

        void setCaret(size_t index)
        {
            auto rc = getCaret(index);
            m_caret.row = rc.row;
            m_caret.col = rc.col;
            m_caret.offset = index;
            m_seekColumn = m_caret.col;
        }

        void insertAt(string* buf,
                      size_t index /** logical index **/,
                      string s,
                      bool allowMerge)
        {
            m_caretUndoStack.push(m_caret);
            auto begin = (*buf).length;
            (*buf) ~= s;

            // Split the span into managable chunks
            size_t newLines = 0;
            if (s.length > m_maxSpanSize)
            {
                size_t undoCount = 0;
                size_t grabbed = 0;
                while(grabbed != s.length)
                {
                    auto canGrab = min(s.length - grabbed, m_maxSpanSize); // elements left to take
                    auto loIndex = begin + grabbed;
                    auto hiIndex = begin + grabbed + canGrab;

                    auto newSpan = Span(buf, index + loIndex, canGrab);
                    auto newNode = m_spans.insertAt(index + grabbed, newSpan, allowMerge);
                    newLines += newSpan.newLines;
                    grabbed += canGrab;
                    undoCount ++;
                }

                m_spans.mergeUndoStack(undoCount);
            }
            else
            {
                auto newSpan = Span(buf, begin, s.length);
                auto newNode = m_spans.insertAt(index, newSpan, allowMerge);
                newLines += newSpan.newLines;
            }

            m_totalNewLines += newLines;
            m_totalChars += s.length;

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

        string m_original;
        string m_edit;
        SpanList m_spans;
        Caret m_caret;

        Stack!Caret m_caretUndoStack;
        Stack!Caret m_caretRedoStack;

        uint m_tabSpaces = 4;
        uint m_totalNewLines;
        uint m_totalChars;
        public string m_currentLine;
        size_t m_maxSpanSize = 2000;

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

