
module glui.widget.table;

import
    glui.widget.base,
    glui.widget.text;

class WidgetTable : WidgetWindow
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:

        override void set(WidgetArgs args)
        {
            super.set(args);

            m_type = "WIDGETTABLE";

            fill(args, arg("columns", m_columns),
                       arg("bordercolor", m_rows));


        }

    private:

        size_t m_rows;
        size_t m_columns;

}
