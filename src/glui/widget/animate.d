// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Summary: Tree widgets, Tree, Menu, etc.
*/

module glui.widget.animate;

import
    std.stdio,
    std.range;

import
    derelict.opengl.gl;

import
    glui.widget.base;

class WidgetAnimator : Widget
{
    alias Widget.set set;

    package:

        this(WidgetRoot root, Widget parent)
        {
            super(root, parent);
        }

    public:

        override WidgetAnimator set(Args args)
        {
            super.set(args);
            m_type = "WIDGETANIMATOR";

            string id = "";

            foreach(key, val; zip(args.keys, args.vals))
            {
                switch(key.toLower())
                {
                    case "target": id.grab(val); break;
                    default: break;
                }
            }

            if (id != "")
            {
                m_target = root.findByID(id);
                if (m_target)
                {
                    m_target.setParent(this);
                    m_target.clipped = false;
                    root.requestTimer(10, &timer);
                }
            }

            setDim(root.dim);
            m_onParentResizeX = AdaptX.RESIZE;
            m_onParentResizeY = AdaptY.RESIZE;
            return this;
        }

        bool timer()
        {
            m_angle += 2;
            m_angle %= 360;
            needRender();
            return true;
        }

        override void render(Flag!"RenderChildren" recurse = Flag!"RenderChildren".yes)
        {
            glPushMatrix();
            auto dx = m_target.screenPos.x + (m_target.dim.x / 2.);
            auto dy = m_target.screenPos.y + (m_target.dim.y / 2.);
            glTranslatef(dx, dy, 0);
            glRotatef(m_angle, 0, 0, 1);
            glTranslatef(-dx, -dy, 0);

            if (recurse)
                renderChildren();

            glPopMatrix();
        }

        float m_angle = 0;
        Widget m_target;
}
