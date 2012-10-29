
module glui.widget.table;

import std.stdio;

import
    glui.truetype,
    glui.widget.base,
    glui.widget.text;

class WidgetTable : WidgetWindow
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:

        void set(Font font, WidgetArgs args)
        {
            super.set(args);

            m_type = "WIDGETTABLE";
            m_font = font;
            int cols = 1, rows = 1;

            fill(args, arg("columns", cols),
                       arg("rows", rows));

            m_columns = cols;
            m_rows = rows;

            auto cell_x = m_dim.x / cols;
            auto cell_y = m_dim.y / rows;

            m_cells.length = m_rows;
            foreach(ridx, ref row; m_cells)
            {
                row.length = m_columns;
                foreach(cidx, ref cell; row)
                {
                    cell = root.create!WidgetText(this, font, widgetArgs(
                                    "dim", [cell_x, cell_y],
                                    "pos", cast(int[])[cidx * cell_x, ridx * cell_y],
                                    "bordercolor", RGBA(1,1,1,1)));
                }
            }


        }

        override void render(Flag!"RenderChildren" recurse = Flag!"RenderChildren".yes)
        {
            super.render(Flag!"RenderChildren".no);

            if (recurse)
                renderChildren();
        }

        override void event(ref Event event)
        {
            if (!amIFocused && !isAChildFocused) return;

            switch(event.type) with(EventType)
            {
                case MOUSECLICK:
                {
                    auto pos = event.get!MouseClick.pos;

                    auto cell_x = m_dim.x / m_columns;
                    auto cell_y = m_dim.y / m_rows;
                    auto col = (pos.x - m_screenPos.x) / cell_x;
                    auto row = (pos.y - m_screenPos.y) / cell_y;

                    if (col >= 0 && col < m_columns &&
                        row >= 0 && row < m_rows)
                    {
                        m_root.changeFocus(m_cells[row][col]);
                        m_cells[row][col].event(event);
                        m_currCell = [col,row];
                    }

                    break;
                }

                case KEYPRESS:
                {
                    auto key = event.get!KeyPress.key;

                    if (key == KEY.KC_TAB)
                    {

                        // Delete the tab from the currently focused cell
                        writeln(m_cells[m_currCell.y][m_currCell.x].textArea.col);
                        writeln(m_cells[m_currCell.y][m_currCell.x].textArea.del());
                        writeln(m_cells[m_currCell.y][m_currCell.x].textArea.col);

                        if (m_currCell.x < m_columns - 1)
                        {
                            m_currCell.x ++;
                            m_root.changeFocus(m_cells[m_currCell.y][m_currCell.x]);
                        }
                        else
                        {
                            if (m_currCell.y < m_rows - 1)
                            {
                                m_currCell.x = 0;
                                m_currCell.y ++;
                                m_root.changeFocus(m_cells[m_currCell.y][m_currCell.x]);
                            }
                        }
                    }

                    break;
                }

                default: break;
            }
        }

        /**
        * Intercept focus events
        */
        override bool stealFocus(int[2] pos, Widget child)
        {
            return true;
        }

        override bool requestDrag(int[2] pos)
        {
            return true;
        }


        override void drag(int[2] pos, int[2] delta)
        {
        }

    private:

        size_t m_rows;
        size_t m_columns;
        int[2] m_currCell;

        Font m_font;

        WidgetText[][] m_cells;

}
