
module glui.widget.tree;

import
    std.stdio;

import
    derelict.opengl.gl;

import
    glui.truetype,
    glui.widget.base,
    glui.widget.text;



class WidgetTree : WidgetWindow
{
    package:

        this(WidgetRoot root, Widget parent)
        {
            super(root, parent);
        }

    public:

        override void set(WidgetArgs args)
        {
            super.set(args);
            m_type = "WIDGETTREE";

            RGBA scrollBg = RGBA(0,0,0,1);
            RGBA scrollFg = RGBA(1,1,1,1);
            RGBA scrollBd = RGBA(0,0,0,1);
            bool scrollFade = true, scroll = true;
            int scrollCr = 0, scrollTh = 10; // corner radius and thickness

            fill(args, arg("gap", m_widgetGap),
                       arg("orientation", m_orient),
                       arg("indent", m_widgetIndent),
                       arg("autoresize", m_autoResize),
                       arg("scroll", scroll),
                       arg("cliptoscrollbar", m_clipToScrollBar),
                       arg("scrollbackground", scrollBg),
                       arg("scrollforeground", scrollFg),
                       arg("scrollborder", scrollBd),
                       arg("scrollfade", scrollFade),
                       arg("scrollcornerradius", scrollCr),
                       arg("scrollthick", scrollTh));

            if (scroll)
                m_vScroll = m_root.create!WidgetScroll(this,
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

        }

        void add(Widget wparent,
                 Widget widget,
                 Flag!"NoUpdate" noUpdate = Flag!"NoUpdate".no)
        {
            widget.setParent(this);

            if (wparent is null)
            {
                auto newNode = new Node(widget);
                newNode.shown = true;
                m_tree ~= newNode;
            }
            else
            {
                // Find the parent node
                Node n = null;
                foreach(node; m_tree)
                    if (findParentNode(node, wparent, n))
                        break;

                if (n is null) // couldn't find parent, put it at top level
                {
                    auto newNode = new Node(widget);
                    newNode.shown = true;
                    m_tree ~= newNode;
                }
                else
                {
                    widget.showing = false; // if it has a parent, it is initially invisible
                    auto newNode = new Node(widget);
                    newNode.parent = n;
                    n.children ~= newNode;
                }
            }

            if (!noUpdate)
                updateTree();
        }

        override void transformPos(Widget w, ref int[2] pos)
        {
            Widget.transformPos(this, pos);

            if (m_vScroll !is null && w != m_vScroll)
                pos[1] -= m_vScroll.current;
        }

        override void transformClip(Widget w, ref int[4] clipbox)
        {
            Widget.transformClip(this, clipbox);

            if (m_vScroll !is null && w != m_vScroll)
                clipbox[1] -= m_vScroll.current;
        }

        void update()
        {
            updateTree();
        }

        override void event(ref Event event)
        {
            // Look for mouse clicks on any of our branches
            if (event.type == EventType.MOUSECLICK &&
                (amIHovered || isAChildHovered) &&
                (m_vScroll is null || !m_root.isHovered(m_vScroll)) )
            {
                auto pos = event.get!MouseClick.pos;

                Widget focus = null;
                foreach(child; m_children)
                    if (child.focus(pos, focus))
                        break;

                if (focus !is null &&
                    focus.type != "WIDGETSCROLL") // we got a hit
                {
                    Node n = null;
                    foreach(node; m_tree)
                    if (findParentNode(node, focus, n))
                        break;

                    if (n !is null)
                    {
                        n.expanded = !n.expanded;

                        foreach(child; n.children)
                            setVisibility(child);

                        updateTree();
                    }
                }
            }

            if (event.type == EventType.MOUSEMOVE &&
                (amIHovered || isAChildHovered) )
            {
                auto pos = event.get!MouseMove.pos;

                Widget focus = null;
                foreach(child; m_children)
                    if (child.focus(pos, focus))
                        break;

                if (focus !is null &&
                    focus.type != "WIDGETSCROLL") // we got a hit
                {
                    Node n = null;
                    foreach(node; m_tree)
                    if (findParentNode(node, focus, n))
                        break;

                    if (n !is null && n !is m_lastHovered)
                    {
                        if (m_lastHovered !is null)
                        {
                            bool collapseOld = true;

                            if (n is m_lastHovered.parent) // child to parent
                                collapseOld = true;
                            else if (n.parent is m_lastHovered) // parent to child
                                collapseOld = false;
                            else if (n.isSibling(m_lastHovered)) // sibling to sibling
                                collapseOld = true;
                            else if (!n.isSibling(m_lastHovered)) // branch to branch
                            {
                                collapseBranch(m_lastHovered);
                                collapseOld = false;
                            }

                            if (collapseOld)
                            {
                                m_lastHovered.expanded = false;
                                foreach(child; m_lastHovered.children)
                                    setVisibility(child);
                            }
                        }

                        m_lastHovered = n;
                        n.expanded = true;
                        foreach(child; n.children)
                            setVisibility(child);

                        updateTree();
                    }
                }

            }
        }

        // Clip tree to include the scroll bar
        override int[4] getChildClipBox(Widget w)
        {
            auto clip = getClipBox();
            if (w.type != "WIDGETSCROLL" && m_vScroll !is null && m_clipToScrollBar)
                clip[2] -= m_vScroll.dim.x;

            if (m_parent)
                smallestBox(clip, m_parent.getChildClipBox(this));

            return clip;
        }

        bool transitionTimer()
        {
            m_transitionCalls ++;
            if (m_transitioning)
            {
                updateTree();
                return true;
            }
            else
            {
                m_transitionCalls = 0;
                return false;
            }
        }


        override void render(Flag!"RenderChildren" recurse)
        {
            super.render(Flag!"RenderChildren".no);

            if (m_vScroll)
                glTranslatef(0, -m_vScroll.current, 0);

            long maxFocus;
            foreach(child; m_children)
                if (child !is m_vScroll)
                    renderChild(child, maxFocus);

            if (m_vScroll)
            {
                glTranslatef(0, m_vScroll.current, 0);
                m_vScroll.preRender();
                m_vScroll.render(Flag!"RenderChildren".yes);
                m_vScroll.postRender();
            }
        }

        override void lostHover()
        {
            writeln(isAChildHovered);
            if (!isAChildHovered && m_lastHovered !is null)
            {
                writeln("LOST HOVER");
                collapseBranch(m_lastHovered);
                m_lastHovered = null;
            }
        }

    private:

        void setVisibility(Node n)
        {
            n.shown = n.parent.expanded && n.parent.shown;
            n.widget.showing = n.shown;

            foreach(child; n.children)
                setVisibility(child);
        }

        void collapseBranch(Node n)
        {
            Node base = n;
            while(base.parent !is null)
            {
                base.expanded = false;
                base = base.parent;
            }
            base.expanded = false;
            foreach(child; base.children)
                setVisibility(child);
        }

        void renderChild(Widget w, ref long maxFocus)
        {
            if (!w.visible || !overlap(w, this))
                return;

            if (w.lastFocused > maxFocus)
                maxFocus = w.lastFocused;

            w.preRender();
            w.render(Flag!"RenderChildren".yes);
            w.postRender();
        }

        bool findParentNode(Node n, Widget w, ref Node parent)
        {
            if (n.widget is w)
            {
                parent = n;
                return true;
            }

            foreach(child; n.children)
                if (findParentNode(child, w, parent))
                    return true;

            return false;
        }

        void updateTree()
        {
            updateScreenInfo();
            int xoffset = 10, yoffset = 10, width = 0, height = 0;

            uint depth = 0;
            void recurseHorizontal(Node node)
            {
                ++depth;

                if (node.widget.dim.x + xoffset > width)
                    width = node.widget.dim.x + xoffset;

                if (node.widget.dim.y + yoffset > height)
                    height = node.widget.dim.y + yoffset;

                node.widget.setPos(xoffset, yoffset);
                node.widget.updateScreenInfo();

                // See if widget is still visible inside the clipping area
                node.widget.showing = true && node.shown;

                if (node.shown)
                {
                    if (depth == 1)
                    {
                        auto y = yoffset;
                        foreach(child; node.children)
                        {
                            yoffset += node.widget.dim.y + m_widgetGap;
                            recurseHorizontal(child);
                        }
                        yoffset = y;
                        xoffset += node.widget.dim.x + m_widgetGap;
                    }
                    else
                    {
                        auto y = yoffset;
                        auto x = xoffset;
                        xoffset += node.widget.dim.x + m_widgetGap;
                        foreach(child; node.children)
                        {
                            recurseHorizontal(child);
                            yoffset += node.widget.dim.y + m_widgetGap;
                        }
                        yoffset = y;
                        xoffset = x;
                    }
                }

                --depth;
            }



            void recurse(Node node)
            {
                xoffset += m_widgetIndent;

                if (node.widget.dim.x + xoffset > width)
                    width = node.widget.dim.x + xoffset;
                if (node.widget.dim.y + yoffset > height)
                    height = node.widget.dim.y + yoffset;

                node.widget.setPos(xoffset, yoffset);
                node.widget.updateScreenInfo();

                // See if widget is still visible inside the clipping area
                node.widget.showing = true && node.shown;

                if (node.shown)
                {
                    yoffset += node.widget.dim.y + m_widgetGap;

                    foreach(child; node.children)
                        recurse(child);
                }

                xoffset -= m_widgetIndent;
            }

            void delegate(Node) dg;
            if (m_orient == Orientation.VERTICAL)
                dg = &recurse;
            else
                dg = &recurseHorizontal;

            foreach(node; m_tree)
                dg(node);

            if (m_vScroll)
                m_vScroll.range = [0, yoffset];
            else if (m_autoResize)
                setDim(width, height);

            needRender();
        }

        class Node
        {
            this(Widget w) { widget = w; }
            Widget widget = null;
            Node parent = null;
            Node[] children = null;
            bool shown = false;
            bool expanded = false;

            bool isSibling(Node n) {
                return (parent !is null && parent.children.canFind!"a is b"(n));
            }

            bool isParent(Node n) {
                return n is parent;
            }
        }

        Node[] m_tree;

        WidgetScroll m_vScroll;
        Orientation m_orient = Orientation.VERTICAL;

        Node m_lastHovered;

        bool m_clipToScrollBar = true;
        bool m_transitioning = false;
        int m_transitionCalls = 0;
        int m_transitionInc = 1;
        int m_widgetGap = 5;
        int m_widgetIndent = 20;
        bool m_autoResize = false; // resize to fit whole tree
}
