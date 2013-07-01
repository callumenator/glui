
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
* This interface defines a TextArea, a class which manages text sequences,
* insertion, deletion, and caret operations.
*/
abstract class TextArea
{
    /**
    *The caret defines the input/operation point in the text sequence.
    */
    struct Caret { size_t line, col; }

    Caret caret;

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
    string remove(Caret from, Caret to);

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
    * Return the text between the given caret positions.
    */
    string getTextBetween(Caret s, Caret e);

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


class STextArea : TextArea
{
    import std.string, std.array, std.range, std.algorithm;

    /**
    * Return the current caret row.
    */
    override @property size_t line() const { return caret.line; }

    /**
    * Return the current caret column.
    */
    override @property size_t col() const { return caret.col; }

    /**
    * Return the number of lines in the text.
    */
    override @property size_t nLines() const { return lines.length; }

    /**
    * Set the text to the given string. This implies a clear().
    */
    override void set(string s)
    {
        lines = splitLines(s);
    }

    /**
    * Clear all current text, and reset the caret to 0,0,0.
    */
    override void clear()
    {
        lines.clear();
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
        auto preCaret = caret;
        if (s.length == 1 && s[0] == '\n')
        {
            breakLine();
        }
        else
        {
            auto newLines = s.splitLines();
            auto lastLineHasNewline = (s[$-1] == '\n' || s[$-1] == '\r' || (s.length >= 2 && s[$-2..$] == "\r\n"));

            lines[caret.line].insertInPlace(caret.col, newLines[0]);
            moveRight(newLines[0].length);

            if (newLines.length > 1)
            {
                foreach(l; newLines[1..$])
                {
                    newLine();
                    lines[caret.line].insertInPlace(caret.col, l);
                    moveRight(l.length);
                }
            }

            if (lastLineHasNewline)
                newLine();
        }

        if (!undoing)
            undoStack.push(Change(Change.Type.insert, preCaret, caret, ""));
    }

    /**
    * Apply the keyboard delete operation at the current caret location.
    */
    override string del()
    {
        string deleted;
        if (caret.col == lines[caret.line].length)
        {
            if (caret.line == lines.length - 1)
                return "";

            auto removed = lines[caret.line+1];
            lines = lines[0..caret.line+1] ~ lines[caret.line+2..$];

            if (removed.length > 0)
                insert(removed);

            deleted = "\n";
        }
        else
        {
            deleted = lines[caret.line][caret.col].to!string();
            lines[caret.line] = lines[caret.line][0..caret.col] ~ lines[caret.line][caret.col+1..$];
        }

        if (!undoing)
            undoStack.push(Change(Change.Type.remove, caret, caret, deleted));

        return deleted;
    }

    /**
    * Apply the keyboard backspace operation at the current caret location.
    */
    override string backspace()
    {
        string deleted;

        if (caret.col == 0) // remove a line from lines
        {
            if (caret.line == 0)
                return "";

            auto removed = lines[caret.line];
            lines = lines[0..caret.line] ~ lines[caret.line+1..$];

            if (caret.line > 0)
            {
                caret.line --;
                caret.col = lines[caret.line].length;
            }

            auto temp = caret;

            if (removed.length > 0)
                insert(removed);

            caret = temp;
            deleted = "\n";
        }
        else
        {
            deleted = lines[caret.line][caret.col-1].to!string();
            lines[caret.line] = lines[caret.line][0..caret.col-1] ~
                                lines[caret.line][caret.col..$];
            caret.col--;
        }

        saveColumn();

        if (!undoing)
            undoStack.push(Change(Change.Type.remove, caret, caret, deleted));

        return deleted;
    }

    /**
    * Remove all text between [from,to] (inclusive) offsets into the text sequence.
    */
    override string remove(Caret start, Caret end)
    in
    {
        assert(start.line < lines.length && end.line < lines.length);
        assert(start.col <= lines[start.line].length && end.col <= lines[end.line].length);
        if (start.line == end.line) assert(start.col <= end.col);
    }
    body
    {
        string deleted;

        if (start.line == end.line)
        {
            deleted = lines[start.line][start.col..end.col];
            lines[start.line] = lines[start.line][0..start.col] ~
                                lines[start.line][end.col..$];
        }
        else if (end.line - start.line == 1)
        {
            deleted = lines[start.line][start.col..$] ~ "\n" ~ lines[end.line][0..end.col];
            auto joined = lines[start.line][0..start.col] ~ lines[end.line][end.col..$];
            lines = lines[0..start.line] ~ joined ~ lines[end.line+1..$];
        }
        else // end.line > (start.line + 1)
        {
            deleted = lines[start.line][start.col..$] ~ "\n" ~
                      lines[start.line + 1..end.line].join("\n") ~ "\n" ~
                      lines[end.line][0..end.col];

            auto joined = lines[start.line][0..start.col] ~ lines[end.line][end.col..$];
            lines = lines[0..start.line] ~ joined ~ lines[end.line+1..$];
        }

        caret = start;
        saveColumn();

        if (!undoing)
            undoStack.push(Change(Change.Type.remove, start, start, deleted));

        return deleted;
    }

    /**
    * Return the entire text sequence.
    */
    override string getText()
    {
        return lines.join("\n");
    }

    /**
    * Return the text to the left of the caret.
    */
    override char leftText()
    {
        if (caret.col == 0 && caret.line > 0)
            return '\n';
        else if (caret.col == 0 && caret.line == 0)
            return '\0';
        else if (caret.col > 0)
            return lines[caret.line][caret.col-1];
        else
            assert(false);
    }

    /**
    * Return the text to the right of the caret (i.e. at the caret).
    */
    override char rightText()
    {
        if (caret.col == lines[caret.line].length && caret.line < lines.length - 1)
            return '\n';
        else if (caret.col == lines[caret.line].length && caret.line == lines.length - 1)
            return '\0';
        else if (caret.col < lines[caret.line].length)
            return lines[caret.line][caret.col];
        else
            assert(false);
    }

    /**
    * Get text in the given line as a string.
    */
    override string getLine(size_t line)
    {
        return lines[line];
    }

    /**
    * Get the text in the line at the current caret location.
    */
    override string getCurrentLine()
    {
        return lines[caret.line];
    }

    /**
    * Get all text between lines [from, from + n_lines] (inclusive). If
    * n_lines is not set, all lines beginning at from are returned. Text
    * is returned as a single string.
    */
    override string getTextLines(size_t from = 0, int n_lines = -1)
    {
        auto _from = min(from, lines.length - 1);
        auto _to = min(from + n_lines + 1, lines.length);

        if (n_lines == -1)
            return lines[_from..$].join("\n");
        else
            return lines[_from.._to].join("\n");
    }

    /**
    * Return the text between the given caret positions.
    */
    override string getTextBetween(Caret s, Caret e)
    {
        if (s.line == e.line)
        {
            return lines[s.line][s.col..e.col];
        }
        else
        {
            auto first = lines[s.line][s.col..$];
            auto last = lines[e.line][0..e.col];

            if (e.line - s.line == 1)
            {
                return first ~ "\n" ~ last;
            }
            else
            {
                auto middle = lines[s.line+1..e.line].join("\n");
                return first ~ "\n" ~ middle ~ "\n" ~ last;
            }
        }
    }

    /**
    * Get the caret corresponding to the given (x,y) coordinates relative
    * to the first character in the text sequence, assuming the given font.
    */
    override Caret getCaret(ref const(Font) font, int x, int y)
    {
        Caret _loc;

        if (lines.length == 0)
            return _loc;

        // row is determined solely by font.m_lineHeight
        _loc.line = cast(int) (y / font.m_lineHeight);

        if (_loc.line > lines.length - 1)
            _loc.line = lines.length - 1;

        float _x = 0;
        foreach(char c; lines[_loc.line])
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
    override int[2] getCaretPosition(ref const(Font) font)
    {
        int x, y = font.m_lineHeight * caret.line;

        foreach(i, char c; lines[caret.line])
        {
            if (i == caret.col)
                break;

            if (c == '\t')
                x += 4*font.width(' '); // TODO: configurable tab spaces from parent text widget
            else
                x += font.width(c);
        }
        return [x,y];
    }

    /**
    * Assuming the given font, return the coordinates (x,y) of the given caret.
    */
    override int[2] getCaretPosition(ref const(Font) font, Caret thisCaret)
    {
        auto temp = caret;
        caret = thisCaret;
        auto result = getCaretPosition(font);
        caret = temp;
        return result;
    }

    /**
    * Move the caret left one character.
    */
    override bool moveLeft(uint thisMuch = 1)
    {
        if (caret.line == 0 && caret.col == 0)
            return false;

        while(thisMuch > 0)
        {
            auto shift = min(thisMuch, caret.col);

            caret.col -= shift;

            if (shift < thisMuch) // start of line
            {
                if (caret.line > 0)
                {
                    caret.line --;
                    caret.col = lines[caret.line].length;
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
        if (caret.line == lines.length - 1 && caret.col == lines[caret.line].length)
            return false;

        while(thisMuch > 0)
        {
            auto shift = min(thisMuch, lines[caret.line].length - caret.col);

            caret.col += shift;

            if (shift < thisMuch) // end of line
            {
                if (caret.line < lines.length - 1)
                {
                    caret.col = 0;
                    caret.line ++;
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
        if (caret.line > 0)
            caret.line --;
        seekColumn();
        return true;
    }


    /**
    * Move the caret down one line. Try to seek the same column as the current line.
    */
    override bool moveDown()
    {

        if (caret.line < lines.length - 1)
            caret.line ++;
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
        caret.col = 0;
        saveColumn();
    }

    /**
    * Place the caret at the end of the current line.
    */
    override void end()
    {
        caret.col = lines[caret.line].length;
        saveColumn();
    }

    /**
    * Place the caret at the start of the entire text sequence.
    */
    override void gotoStartOfText()
    {
        caret.col = 0;
        caret.line = 0;
        saveColumn();
    }

    /**
    * Place the caret at the end of the entire text sequence.
    */
    override void gotoEndOfText()
    {
        caret.line = lines.length - 1;
        caret.col = lines[caret.line].length;
        saveColumn();
    }

    /**
    * Move the caret to the given row and column.
    */
    override void moveCaret(size_t newRow, size_t newCol)
    {
        caret.line = min(newRow, lines.length - 1);
        caret.col = min(newCol, lines[caret.line].length);
        saveColumn();
    }

    /**
    * Calculate the screen width of a line, given a font, from startCol to end of line.
    */
    override int getLineWidth(ref const(Font) font, size_t line, size_t startCol = 0)
    in
    {
        assert(line < lines.length);
    }
    body
    {
        int width = font.width(' ');
        foreach(i, char c; lines[line])
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


    override void undo()
    {
        if (undoStack.empty)
            return;

        undoing = true;
        auto action = undoStack.pop();

        if (action.type == Change.Type.insert)
        {
            remove(action.caretStart, action.caretEnd);
        }
        else
        {
            caret = action.caretStart;
            insert(action.data);
        }
        undoing = false;
    }

    override void redo()
    {
        if (redoStack.empty)
            return;
    }

private:

    void newLine()
    {
        caret.line ++;
        caret.col = 0;
        if (caret.line >= lines.length)
            lines ~= iota(1 + (caret.line - lines.length)).map!(a => "").array();
        else
            lines.insertInPlace(caret.line, "");
    }

    /**
    * Break line at caret, move rest of line to newline
    */
    void breakLine()
    {
        if (caret.col < lines[caret.line].length)
        {
            auto rest = lines[caret.line][caret.col..$];
            lines[caret.line] = lines[caret.line][0..caret.col];
            newLine();
            insert(rest);
            caret.col = 0;
        }
        else
        {
            newLine();
        }
    }

    void adjustCursorColumn()
    {
        caret.col = min(caret.col, lines[caret.line].length);
    }

    void saveColumn()
    {
        if (!seeking)
            seekCol = caret.col;
    }

    void seekColumn()
    {
        seeking = true;
        caret.col = min(caret.col, lines[caret.line].length);

        if (caret.col > seekCol)
            moveLeft(caret.col - seekCol);
        else if (caret.col < seekCol)
        {
            auto rightShift = seekCol - caret.col;
            auto maxShift = lines[caret.line].length - caret.col;
            moveRight(min(rightShift, maxShift));
        }
        seeking = false;
    }


    struct Change
    {
        enum Type { insert, remove }
        Type type;
        Caret caretStart, caretEnd;
        string data;
    }

    string[] lines = [""];
    uint seekCol; // when moving up and down, seek this column
    bool seeking = false; // true if seeking a column

    UndoStack!(Change,100)  undoStack, redoStack;
    bool undoing = false; // if true, don't save action on undo stack
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
        writeln(top);
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






// Following are a very naive TextArea impl, plus a buggy PieceTable impl :)
version(none)
{

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

    string spannedText() in { assert(buffer !is null); } body
    {
        return (*buffer)[offset..offset+this.length];
    }

    /**
    * Create two new spans, by splitting this span at splitAt.
    * A left and right span are returned as a Tuple. The left
    * span contains the original span up to and including splitAt - 1,
    * the right span contains the original span from splitAt to length.
    */
    Tuple!(Span, Span) split(size_t splitAt) in { assert(splitAt > 0 && splitAt < length); }
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
        //writeln("TEST [xxx<xx][xx>xx]");
        l.insertAt(0, Span(&buffer, 0, 35));
        l.insertAt(-1, Span(&buffer, 35, buffer.length - 35));
        auto s = l[];
        assert(s.front.spannedText() == "this is a test buffer for running t");
        s.popFront();
        assert(s.front.spannedText() == "ests\non the functions found in the SpanList class blah blah");
        assert(l.remove(30, 40) == "ing tests\no");

        l.clear();

        // Remove all of left span and part of adjacent right span
        //writeln("TEST <xxxxx][xx>xx]");
        l.insertAt(0, Span(&buffer, 0, 35));
        l.insertAt(-1, Span(&buffer, 35, buffer.length - 35));
        assert(l.remove(0, 40) == "this is a test buffer for running tests\no");
        assert(l[].front.spannedText() == "n the functions found in the SpanList class blah blah");

        l.clear();

        // Remove part of left span and all of adjacent right span
        //writeln("TEST [xx<xxx][xxxx>");
        l.insertAt(0, Span(&buffer, 0, 35));
        l.insertAt(-1, Span(&buffer, 35, buffer.length - 35));
        assert(l.remove(30, 100) == "ing tests\non the functions found in the SpanList class blah blah");
        assert(l[].front.spannedText() == "this is a test buffer for runn");

        l.clear();

        // Remove part of left span, middle spans, and part of right span
        //writeln("TEST [xx<xxx][xxxx][xxxx][xx>xx]");
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
        //writeln("TEST <xxxxx][xxxx][xxxx][xx>xx]");
        l.insertAt(0, Span(&buffer, 0, 20));
        l.insertAt(-1, Span(&buffer, 20, 20));
        l.insertAt(-1, Span(&buffer, 40, 20));
        l.insertAt(-1, Span(&buffer, 60, 34));
        assert(l.remove(0, 65) == buffer[0..66]);
        assert(l[].front.spannedText() == buffer[66..$]);

        l.clear();

        // Remove part of left span, middle spans, and all of the right span
        //writeln("TEST [xx<xxx][xxxx][xxxx][xxxx>");
        l.insertAt(0, Span(&buffer, 0, 20));
        l.insertAt(-1, Span(&buffer, 20, 20));
        l.insertAt(-1, Span(&buffer, 40, 20));
        l.insertAt(-1, Span(&buffer, 60, 34));
        assert(l.remove(5, 94) == buffer[5..94]);
        assert(l[].front.spannedText() == buffer[0..5]);

        l.clear();

        // Remove one middle span
        //writeln("TEST [xxxxx]<xxxx>[xxxx][xxxx]");
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
            if (first.next is last)
            {
                first = null;
                last = null;
            }
            else
            {
                first = first.next;
            }
        }

        void popBack()
        {
            if (last.prev is first)
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
        override @property size_t offset() const { return m_caret.offset; }
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
                m_currentLine = byLine(m_caret.row).front;
                return removed;
            }

            m_caret.offset = from;

            if (totalDel > 0)
                setCaret(from);
            else
                m_caret.col -= (length - totalDel);

            m_seekColumn = m_caret.col;
            m_currentLine = byLine(m_caret.row).front;

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
            else
                return m_currentLine[m_caret.col-1];
        }

        override char rightText()
        {
            if (m_caret.row == m_totalNewLines && m_caret.col == m_currentLine.length)
                return cast(char)0;
            else if (m_caret.col == m_currentLine.length)
                return '\n';
            else
                return m_currentLine[m_caret.col];
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

        override string getTextBetween(size_t from, size_t to) in { assert(from < to); } body
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
                      size_t index, /** logical index **/
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
}
