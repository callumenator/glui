
module glui.widget.menu;

import std.stdio;

import
    glui.truetype,
    glui.widget.base,
    glui.widget.text;

class WidgetMenu: WidgetWindow
{
    package:

        this(WidgetRoot root, Widget parent)
        {
            super(root, parent);
        }

    public:

        void set(Font font, WidgetArgs args)
        {
            super.set(args);

            m_type = "WIDGETMENU";
            m_font = font;
        }

        struct MenuItem
        {
            string value;
            string id;
            MenuItem[] children;
        }

        MenuItem m_rootMenu = MenuItem("", "/", null)

        MenuItem addItem(string value, string id, string parent = null, Font font = null)
        {
            if (parent is null)
                parent = m_rootMenu;

            if (font is null)
                font = m_font;

            auto newItem = root.create!WidgetLabel(parent, m_font, widgetArgs("text", value));
            return newItem;
        }

        override void render(Flag!"RenderChildren" recurse = Flag!"RenderChildren".yes)
        {
            super.render(Flag!"RenderChildren".no);

            m_rootMenu.render(Flag!"RenderChildren".yes);

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
                    break;
                }

                case KEYPRESS:
                {
                    auto key = event.get!KeyPress.key;
                    break;
                }
                default: break;
            }
        }

        Font m_font;

}
