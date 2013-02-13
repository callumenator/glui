
module glui.widget.menu;

import
    std.stdio;

import
    derelict.opengl.gl;

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
            setDim(1000, 500);
        }

        WidgetTree createMenu(string label)
        {
            auto newTree = root.create!WidgetTree(this, widgetArgs(
                                            "autoresize", true,
                                            "scroll", false,
                                            "pos", [5,5],
                                            "background", RGBA(0,.9,.3,.3),
                                            "bordercolor", RGBA(1,1,1,1),
                                            "resize", ResizeFlag.X | ResizeFlag.Y,
                                            "clipToScrollBar", false,
                                            "scrollFade", false,
                                            "scrollforeground", RGBA(0,0,0,1),
                                            "scrollborder", RGBA(1,1,1,1)));

            auto branch =  root.create!WidgetLabel(null, m_font, widgetArgs(
                                            "text", label,
                                            "dim", [200,25],
                                            "background", RGBA(97,48,145,255)));
            newTree.add(null, branch);
            return newTree;
        }

        void add(WidgetTree parent, string label)
        {
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
        GLuint m_cacheId;

}
