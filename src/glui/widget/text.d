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
    glui.widget.textutil,
    glui.widget.base;

/**
* Prototypes for clipboard copy/paste operations
*/
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
* Text box. This is a (possibly) editable box for rendering text.
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
            if (m_editable) root.requestTimer(m_caretBlinkDelay, &this.timerEvent);

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
        bool timerEvent()
        {
            m_drawCaret = !m_drawCaret;
            needRender();
            return m_alive;
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
            m_editable = false; // set this here, to avoid allocating a caret timer
            m_type = "WIDGETLABEL";
            super.set(font, args);

            // Alignment is vertically centered by default:
            m_vAlign = WidgetText.VAlign.CENTER;

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


