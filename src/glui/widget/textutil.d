
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
