
module glui.widget.textutil;

import
    std.algorithm,
    std.array,
    std.ascii,
    std.container,
    std.conv,
    std.range,
    std.string,
    std.typecons,
    std.stdio,
    std.utf;

import
    glui.widget.base,
    glui.truetype;



/**
*The caret defines the input/operation point in the text sequence.
*/
struct Caret
{
    size_t line, col;

    this(size_t _line, size_t _col)
    {
        line = _line;
        col = _col;
    }

    this(Caret _caret)
    {
        line = _caret.line;
        col = _caret.col;
    }
}


/**
* This interface defines a TextArea, a class which manages text sequences,
* insertion, deletion, and caret operations.
*/
abstract class TextArea
{

    Caret m_caret;

    /**
    * Return the current caret row.
    */
    @property size_t line() const;

    /**
    * Return the current caret column.
    */
    @property size_t col() const;

    /**
    * Return the number of lines in the text.
    */
    @property size_t lineCount() const;

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
    string remove(Caret from, Caret to);

    /**
    * Return the entire text sequence.
    */
    string getText();

    /**
    * Get all text between lines [from, from + n_lines] (inclusive). If
    * n_lines is not set, all lines beginning at from are returned. Text
    * is returned as a single string.
    */
    string getText(size_t from = 0, int n_lines = -1);

    /**
    * Return the text between the given caret positions.
    */
    string getText(Caret s, Caret e);

    /**
    * Return the text to the left of the m_caret.
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
    * Get the caret corresponding to the given (x,y) coordinates relative
    * to the first character in the text sequence, assuming the given font.
    */
    Caret caretAtXY(ref const(Font) font, int x, int y);

    /**
    * Assuming the given font, return the coordinates (x,y) of the current caret location.
    */
    int[2] xyAtCaret(ref const(Font) font);

    /**
    * Assuming the given font, return the coordinates (x,y) of the given m_caret.
    */
    int[2] xyAtCaret(ref const(Font) font, Caret caret);

    /**
    * Move the caret left one character.
    */
    bool moveLeft(uint thisMuch = 1);

    /**
    * Move the caret right one character.
    */
    bool moveRight(uint thisMuch = 1);

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
    * Calculate the screen width of a line, given a font, from startCol to end of line.
    */
    int getLineWidth(ref const(Font) font, size_t line, size_t startCol = 0);

    /**
    * Undo the previous action.
    */
    void undo();

    /**
    * Redo the previously undone action.
    */
    void redo();

    /**
    * Return true if char is considered a delimiter for text jumps.
    */
    bool isDelim(char c)
    {
        return isBlank(c) ||
               !isAlphaNum(c);
    }

    /**
    * Return true if char is considered a blank.
    */
    bool isBlank(char c)
    {
        return c == ' ' ||
               c == '\t' ;
    }
}


class SimpleTextArea : TextArea
{
    import std.string, std.array, std.range, std.algorithm;


    /**
    * Return the current caret row.
    */
    override @property size_t line() const { return m_caret.line; }


    /**
    * Return the current caret column.
    */
    override @property size_t col() const { return m_caret.col; }


    /**
    * Return the number of lines in the text.
    */
    override @property size_t lineCount() const { return m_lines.length; }


    /**
    * Set the text to the given string. This implies a clear().
    */
    override void set(string s)
    {
        m_lines = splitLines(s);
    }


    /**
    * Clear all current text, and reset the caret to 0,0,0.
    */
    override void clear()
    {
        m_lines.clear();
    }


    /**
    * Insert a char at the current caret location.
    */
    override void insert(char s)
    {
        insert([s]);
    }


    /**
    * Insert a string at the current caret location.
    */
    override void insert(string s)
    {
        if (s.length == 0)
            return;

        auto preCaret = m_caret;
        if (s.length == 1 && s[0] == '\n')
        {
            breakLine();
        }
        else
        {
            auto newLines = s.splitLines();
            auto lastLineHasNewline = (s[$-1] == '\n' || s[$-1] == '\r' || (s.length >= 2 && s[$-2..$] == "\r\n"));

            m_lines[m_caret.line].insertInPlace(m_caret.col, newLines[0]);
            moveRight(newLines[0].length);

            if (newLines.length > 1)
            {
                foreach(l; newLines[1..$])
                {
                    newLine();
                    m_lines[m_caret.line].insertInPlace(m_caret.col, l);
                    moveRight(l.length);
                }
            }

            if (lastLineHasNewline)
                newLine();
        }

        if (!m_undoing)
            m_undoStack.push(Change(Change.Type.insert, preCaret, m_caret, s));
    }


    /**
    * Apply the keyboard delete operation at the current caret location.
    */
    override string del()
    {
        string deleted;
        if (m_caret.col == m_lines[m_caret.line].length)
        {
            if (m_caret.line == m_lines.length - 1)
                return "";

            auto removed = m_lines[m_caret.line+1];
            m_lines = m_lines[0..m_caret.line+1] ~ m_lines[m_caret.line+2..$];

            if (removed.length > 0)
                insert(removed);

            deleted = "\n";
        }
        else
        {
            deleted = m_lines[m_caret.line][m_caret.col].to!string();
            m_lines[m_caret.line] = m_lines[m_caret.line][0..m_caret.col] ~ m_lines[m_caret.line][m_caret.col+1..$];
        }

        if (!m_undoing)
            m_undoStack.push(Change(Change.Type.remove, m_caret, m_caret, deleted));

        return deleted;
    }


    /**
    * Apply the keyboard backspace operation at the current caret location.
    */
    override string backspace()
    {
        string deleted;

        if (m_caret.col == 0) // remove a line from lines
        {
            if (m_caret.line == 0)
                return "";

            auto removed = m_lines[m_caret.line];
            m_lines = m_lines[0..m_caret.line] ~ m_lines[m_caret.line+1..$];

            if (m_caret.line > 0)
            {
                m_caret.line --;
                m_caret.col = m_lines[m_caret.line].length;
            }

            auto temp = m_caret;

            if (removed.length > 0)
                insert(removed);

            m_caret = temp;
            deleted = "\n";
        }
        else
        {
            deleted = m_lines[m_caret.line][m_caret.col-1].to!string();
            m_lines[m_caret.line] = m_lines[m_caret.line][0..m_caret.col-1] ~
                                m_lines[m_caret.line][m_caret.col..$];
            m_caret.col--;
        }

        saveColumn();

        if (!m_undoing)
            m_undoStack.push(Change(Change.Type.remove, m_caret, m_caret, deleted));

        return deleted;
    }


    /**
    * Remove all text between [from,to] (inclusive) offsets into the text sequence.
    */
    override string remove(Caret start, Caret end)
    in
    {
        assert(start.line < m_lines.length && end.line < m_lines.length);
        assert(start.col <= m_lines[start.line].length && end.col <= m_lines[end.line].length);
        if (start.line == end.line) assert(start.col <= end.col);
    }
    body
    {
        string deleted;

        if (start.line == end.line)
        {
            deleted = m_lines[start.line][start.col..end.col];
            m_lines[start.line] = m_lines[start.line][0..start.col] ~
                                m_lines[start.line][end.col..$];
        }
        else if (end.line - start.line == 1)
        {
            deleted = m_lines[start.line][start.col..$] ~ "\n" ~ m_lines[end.line][0..end.col];
            auto joined = m_lines[start.line][0..start.col] ~ m_lines[end.line][end.col..$];
            m_lines = m_lines[0..start.line] ~ joined ~ m_lines[end.line+1..$];
        }
        else // end.line > (start.line + 1)
        {
            deleted = m_lines[start.line][start.col..$] ~ "\n" ~
                      m_lines[start.line + 1..end.line].join("\n") ~ "\n" ~
                      m_lines[end.line][0..end.col];

            auto joined = m_lines[start.line][0..start.col] ~ m_lines[end.line][end.col..$];
            m_lines = m_lines[0..start.line] ~ joined ~ m_lines[end.line+1..$];
        }

        m_caret = start;
        saveColumn();

        if (!m_undoing)
            m_undoStack.push(Change(Change.Type.remove, start, end, deleted));

        return deleted;
    }


    /**
    * Return the entire text sequence.
    */
    override string getText()
    {
        return m_lines.join("\n");
    }


    /**
    * Get all text between lines [from, from + n_lines] (inclusive). If
    * n_lines is not set, all lines beginning at from are returned. Text
    * is returned as a single string.
    */
    override string getText(size_t from = 0, int n_lines = -1)
    {
        auto _from = min(from, m_lines.length - 1);
        auto _to = min(from + n_lines + 1, m_lines.length);

        if (n_lines == -1)
            return m_lines[_from..$].join("\n");
        else
            return m_lines[_from.._to].join("\n");
    }


    /**
    * Return the text between the given caret positions.
    */
    override string getText(Caret s, Caret e)
    {
        if (s.line == e.line)
        {
            return m_lines[s.line][s.col..e.col];
        }
        else
        {
            auto first = m_lines[s.line][s.col..$];
            auto last = m_lines[e.line][0..e.col];

            if (e.line - s.line == 1)
            {
                return first ~ "\n" ~ last;
            }
            else
            {
                auto middle = m_lines[s.line+1..e.line].join("\n");
                return first ~ "\n" ~ middle ~ "\n" ~ last;
            }
        }
    }


    /**
    * Return the text to the left of the m_caret.
    */
    override char leftText()
    {
        if (m_caret.col == 0 && m_caret.line > 0)
            return '\n';
        else if (m_caret.col == 0 && m_caret.line == 0)
            return '\0';
        else if (m_caret.col > 0)
            return m_lines[m_caret.line][m_caret.col-1];
        else
            assert(false);
    }


    /**
    * Return the text to the right of the caret (i.e. at the caret).
    */
    override char rightText()
    {
        if (m_caret.col == m_lines[m_caret.line].length && m_caret.line < m_lines.length - 1)
            return '\n';
        else if (m_caret.col == m_lines[m_caret.line].length && m_caret.line == m_lines.length - 1)
            return '\0';
        else if (m_caret.col < m_lines[m_caret.line].length)
            return m_lines[m_caret.line][m_caret.col];
        else
            assert(false);
    }


    /**
    * Get text in the given line as a string.
    */
    override string getLine(size_t line)
    {
        return m_lines[line];
    }


    /**
    * Get the text in the line at the current caret location.
    */
    override string getCurrentLine()
    {
        return m_lines[m_caret.line];
    }


    /**
    * Get the caret corresponding to the given (x,y) coordinates relative
    * to the first character in the text sequence, assuming the given font.
    */
    override Caret caretAtXY(ref const(Font) font, int x, int y)
    {
        Caret _loc;

        if (m_lines.length == 0)
            return _loc;

        // row is determined solely by font.m_lineHeight
        _loc.line = cast(int) (y / font.m_lineHeight);

        if (_loc.line > m_lines.length - 1)
            _loc.line = m_lines.length - 1;

        float _x = 0;
        foreach(char c; m_lines[_loc.line])
        {
            if ((_x + font.width(c)/2.) > x)
                break;

            if (c == '\t')
                _x += 4*font.width(' '); // TODO: configurable tab spaces from parent text widget
            else
                _x += font.width(c);

            _loc.col ++;
        }
        return _loc;
    }


    /**
    * Assuming the given font, return the coordinates (x,y) of the current caret location.
    */
    override int[2] xyAtCaret(ref const(Font) font)
    {
        int x, y = font.m_lineHeight * m_caret.line;

        foreach(i, char c; m_lines[m_caret.line])
        {
            if (i == m_caret.col)
                break;

            if (c == '\t')
                x += 4*font.width(' '); // TODO: configurable tab spaces from parent text widget
            else
                x += font.width(c);
        }
        return [x,y];
    }


    /**
    * Assuming the given font, return the coordinates (x,y) of the given m_caret.
    */
    override int[2] xyAtCaret(ref const(Font) font, Caret thisCaret)
    {
        auto temp = m_caret;
        m_caret = thisCaret;
        auto result = xyAtCaret(font);
        m_caret = temp;
        return result;
    }


    /**
    * Move the caret left one character.
    */
    override bool moveLeft(uint thisMuch = 1)
    {
        if (m_caret.line == 0 && m_caret.col == 0)
            return false;

        while(thisMuch > 0)
        {
            auto shift = min(thisMuch, m_caret.col);

            m_caret.col -= shift;

            if (shift < thisMuch) // start of line
            {
                if (m_caret.line > 0)
                {
                    m_caret.line --;
                    m_caret.col = m_lines[m_caret.line].length;
                    shift ++;
                }
                else
                {
                    break;
                }
            }
            thisMuch -= shift;
        }
        saveColumn();
        return true;
    }


    /**
    * Move the caret right one character.
    */
    override bool moveRight(uint thisMuch = 1)
    {
        if (m_caret.line == m_lines.length - 1 && m_caret.col == m_lines[m_caret.line].length)
            return false;

        while(thisMuch > 0)
        {
            auto shift = min(thisMuch, m_lines[m_caret.line].length - m_caret.col);

            m_caret.col += shift;

            if (shift < thisMuch) // end of line
            {
                if (m_caret.line < m_lines.length - 1)
                {
                    m_caret.col = 0;
                    m_caret.line ++;
                    shift ++;
                }
                else
                {
                    break;
                }
            }
            thisMuch -= shift;
        }
        saveColumn();
        return true;
    }


    /**
    * Move the caret up one line. Try to seek the same column as the current line.
    */
    override bool moveUp()
    {
        if (m_caret.line > 0)
            m_caret.line --;
        seekColumn();
        return true;
    }


    /**
    * Move the caret down one line. Try to seek the same column as the current line.
    */
    override bool moveDown()
    {

        if (m_caret.line < m_lines.length - 1)
            m_caret.line ++;
        seekColumn();
        return true;
    }


    /**
    * Jump the caret left to the next word/symbol.
    */
    override void jumpLeft()
    {
        if (isDelim(leftText) && !isBlank(leftText))
        {
            moveLeft();
            saveColumn();
            return;
        }

        while(moveLeft() && isBlank(leftText)) {}
        while(moveLeft() && !isDelim(leftText)) {}
        saveColumn();
    }


    /**
    * Jump the caret right to the next word/symbol.
    */
    override void jumpRight()
    {
        if (isDelim(rightText))
        {
            while(moveRight() && isDelim(rightText)){}
        }
        else
        {
            while(moveRight() && !isDelim(rightText)){}
            while(moveRight() && isBlank(rightText)){}
        }
        saveColumn();
    }


    /**
    * Place the caret at the start of the current line.
    */
    override void home()
    {
        m_caret.col = 0;
        saveColumn();
    }


    /**
    * Place the caret at the end of the current line.
    */
    override void end()
    {
        m_caret.col = m_lines[m_caret.line].length;
        saveColumn();
    }


    /**
    * Place the caret at the start of the entire text sequence.
    */
    override void gotoStartOfText()
    {
        m_caret.col = 0;
        m_caret.line = 0;
        saveColumn();
    }


    /**
    * Place the caret at the end of the entire text sequence.
    */
    override void gotoEndOfText()
    {
        m_caret.line = m_lines.length - 1;
        m_caret.col = m_lines[m_caret.line].length;
        saveColumn();
    }


    /**
    * Move the caret to the given row and column.
    */
    override void moveCaret(size_t newRow, size_t newCol)
    {
        m_caret.line = min(newRow, m_lines.length - 1);
        m_caret.col = min(newCol, m_lines[m_caret.line].length);
        saveColumn();
    }


    /**
    * Calculate the screen width of a line, given a font, from startCol to end of line.
    */
    override int getLineWidth(ref const(Font) font, size_t line, size_t startCol = 0)
    in
    {
        assert(line < m_lines.length);
    }
    body
    {
        int width = font.width(' ');
        foreach(i, char c; m_lines[line])
        {
            if (i < startCol)
                continue;

            if (c == '\t')
                width += 4 * font.width(' '); // TODO: configurable tabs
            else
                width += font.width(c);
        }
        return width;
    }


    /**
    * Undo the previous action.
    */
    override void undo()
    {
        if (m_undoStack.empty)
            return;

        m_undoing = true;
        auto action = m_undoStack.pop();

        if (action.type == Change.Type.insert)
        {
            remove(action.caretStart, action.caretEnd);
        }
        else if (action.type == Change.Type.remove)
        {
            m_caret = action.caretStart;
            insert(action.data);
        }
        m_redoStack.push(action);
        m_undoing = false;
    }


    /**
    * Redo the previously undone action.
    */
    override void redo()
    {
        if (m_redoStack.empty)
            return;

        auto action = m_redoStack.pop();

        if (action.type == Change.Type.remove)
        {
            remove(action.caretStart, action.caretEnd);
        }
        else if (action.type == Change.Type.insert)
        {
            m_caret = action.caretStart;
            insert(action.data);
        }
    }


private:


    /**
    * Insert a newline at the m_caret.
    */
    void newLine()
    {
        m_caret.line ++;
        m_caret.col = 0;
        if (m_caret.line >= m_lines.length)
            m_lines ~= iota(1 + (m_caret.line - m_lines.length)).map!(a => "").array();
        else
            m_lines.insertInPlace(m_caret.line, "");
    }


    /**
    * Break line at caret, move rest of line to newline
    */
    void breakLine()
    {
        if (m_caret.col < m_lines[m_caret.line].length)
        {
            auto rest = m_lines[m_caret.line][m_caret.col..$];
            m_lines[m_caret.line] = m_lines[m_caret.line][0..m_caret.col];
            newLine();
            insert(rest);
            m_caret.col = 0;
        }
        else
        {
            newLine();
        }
    }


    void adjustCursorColumn()
    {
        m_caret.col = min(m_caret.col, m_lines[m_caret.line].length);
    }


    void saveColumn()
    {
        if (!m_seeking)
            m_seekCol = m_caret.col;
    }


    void seekColumn()
    {
        m_seeking = true;
        m_caret.col = min(m_caret.col, m_lines[m_caret.line].length);

        if (m_caret.col > m_seekCol)
            moveLeft(m_caret.col - m_seekCol);
        else if (m_caret.col < m_seekCol)
        {
            auto rightShift = m_seekCol - m_caret.col;
            auto maxShift = m_lines[m_caret.line].length - m_caret.col;
            moveRight(min(rightShift, maxShift));
        }
        m_seeking = false;
    }


    struct Change
    {
        enum Type { insert, remove }
        Type type;
        Caret caretStart, caretEnd;
        string data;
    }

    string[] m_lines = [""];
    uint m_seekCol; // when moving up and down, seek this column
    bool m_seeking = false; // true if m_seeking a column

    UndoStack!(Change,100)  m_undoStack, m_redoStack;
    bool m_undoing = false; // if true, don't save action on undo stack
}


/**
* Fixed size stack supporting unlimited push, utilizing
* a circular buffer. Old items fall off the bottom of the stack.
*/
struct UndoStack(T, size_t size)
{
    T[size] _buffer;
    int top = -1, used = 0;

    void push(T item)
    {
        top++;
        top = top % size;

        if (used < size)
            used++;

        _buffer[top] = item;
    }

    T pop()
    {
        assert(!empty, "Trying to pop empty stack");

        auto item = _buffer[top];

        used--;
        if (top == 0 && used > 0)
            top = size - 1;
        else
            top--;

        return item;
    }

    @property bool empty()
    {
        return used == 0;
    }
}
