// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Summary: Tree widgets, Tree, Menu, etc.
*/

module glui.widget.tree;

import
    std.conv,
    std.range,
    std.algorithm,
    std.stdio,
    std.variant;

import
    derelict.opengl.gl;

import
    glui.truetype,
    glui.widget.base,
    glui.widget.text;

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

class WidgetTree : WidgetWindow
{
    alias Widget.set set;

    package:

        this(WidgetRoot root, Widget parent)
        {
            super(root, parent);
        }

    public:

        override WidgetTree set(Args args)
        {
            super.set(args);
            m_type = "WIDGETTREE";

            auto scrollBg = RGBA(0,0,0,1);
            auto scrollFg = RGBA(1,1,1,1);
            auto scrollBd = RGBA(0,0,0,0);
            bool scroll = false, fade = true;
            int scrollCr = 0;

            foreach(key, val; zip(args.keys, args.vals))
            {
                switch(key.toLower())
                {
                    case "gap": m_widgetGap.grab(val); break;
                    case "indent": m_widgetIndent.grab(val); break;
                    case "autoresize": m_autoResize.grab(val); break;
                    case "scroll": scroll.grab(val); break;
                    case "cliptoscrollbar": m_clipToScrollBar.grab(val); break;
                    case "scrollbackground": scrollBg.grab(val); break;
                    case "scrollforeground": scrollFg.grab(val); break;
                    case "scrollborder": scrollBd.grab(val); break;
                    case "scrollfade": fade.grab(val); break;
                    case "scrollcornerradius": scrollCr.grab(val); break;
                    default: break;
                }
            }

            if (scroll)
                m_vScroll = m_root.create!WidgetScroll(this,
                                "range", [0,1000], "fade", fade,
                                "slidercolor", scrollFg, "sliderborder", scrollBd,
                                "background", scrollBg, "orientation", Orientation.VERTICAL);

            return this;
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

        Widget add(Widget wparent, string label, Font font, Flag!"NoUpdate" noUpdate = Flag!"NoUpdate".no)
        {
            auto widget = root.create!WidgetLabel(this,
                                                  "font", font,
                                                  "text", label,
                                                  "textcolor", RGBA(1,1,1,1),
                                                  "background", RGBA(.5,.5,.5,.5),
                                                  "textbgcolor", RGBA(0,0,0,0));
            add(wparent, widget, noUpdate);
            return widget;
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

            foreach(node; m_tree)
                recurse(node);

            if (m_vScroll)
                m_vScroll.range = [0, yoffset];
            else if (m_autoResize)
                setDim(width, height);

            needRender();
        }

        Node[] m_tree;
        WidgetScroll m_vScroll;
        bool m_clipToScrollBar = true;
        bool m_autoResize = false; // resize to fit whole tree
        int  m_widgetGap = 5;
        int  m_widgetIndent = 20;
}


class WidgetMenu : WidgetTree
{
    import std.json;
    alias Widget.set set;
    alias WidgetTree.add add;

    package:

        this(WidgetRoot root, Widget parent)
        {
            super(root, parent);
        }

    public:

        override WidgetMenu set(Args args)
        {
            super.set(args);

            m_autoResize = true;
            m_widgetGap = 0;
            m_widgetIndent = 0;
            m_type = "WIDGETMENU";
            root.eventSignal.connect(&globalEvent);
            setColor(RGBA(0,0,0,0));
            setBorderColor(RGBA(0,0,0,0));

            // Look for font and size first, in case we are adding items
            auto fontsize = 12;
            auto index = args.keys.map!(a=>a.toLower()).countUntil("font");
            if (index != -1)
            {
                auto fontname = args.vals[index].get!string;
                index = args.keys.map!(a=>a.toLower()).countUntil("fontsize");
                if (index != -1)
                    fontsize = args.vals[index].get!int;
                m_font = loadFont(fontname, fontsize);
            }

            foreach(key, val; zip(args.keys, args.vals))
            {
                switch(key.toLower)
                {
                    case "items": parseJSONItems(val.get!(JSONValue[string][])); break;
                    default: break;
                }
            }

            return this;
        }

        void parseJSONItems(JSONValue[string][] items)
        {
            import glui.widget.loader;
            foreach(obj; items)
            {
                auto id = "", label = "", fontname = "";
                auto fontsize = 12;
                Widget parent = null;
                int[] padding = [0,0];

                if ("label" in obj)
                    label = obj["label"].str;
                if ("parent" in obj)
                    parent = root.findByID(obj["parent"].str);
                if ("id" in obj)
                    id = obj["id"].str;
                if ("font" in obj)
                    fontname = obj["font"].str;
                if ("fontsize" in obj)
                    fontsize = obj["fontsize"].integer.to!int;
                if ("padding" in obj)
                    padding = getArr(obj["padding"].array).get!(int[]);

                Font font = m_font;
                if (fontname != "")
                    font = loadFont(fontname, fontsize);
                else
                    font = loadFont(font, fontsize);

                auto widget = root.create!WidgetLabel(this,
                                                  "id", id,
                                                  "font", font,
                                                  "text", label,
                                                  "padding", padding,
                                                  "clipped", m_clipped,
                                                  "halign", WidgetText.HAlign.CENTER,
                                                  "textcolor", RGBA(1,1,1,1),
                                                  "background", RGBA(.5,.5,.5,.5),
                                                  "textbgcolor", RGBA(0,0,0,0));

                add(parent, widget, Flag!"NoUpdate".yes);
            }
            updateTree();
        }

        override Widget add(Widget wparent, string label, Font font, Flag!"NoUpdate" noUpdate = Flag!"NoUpdate".no)
        {
            auto widget = root.create!WidgetLabel(this,
                                                  "font", font,
                                                  "text", label,
                                                  "clipped", m_clipped,
                                                  "textcolor", RGBA(1,1,1,1),
                                                  "background", RGBA(.5,.5,.5,.5),
                                                  "textbgcolor", RGBA(0,0,0,0));
            add(wparent, widget, noUpdate);
            return widget;
        }

        override void event(ref Event event)
        {
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
                                while(n.parent !is null)
                                    n = n.parent;
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

        /**
        * Look for global hover changes, to collapse children when Tree base loses hover.
        */
        void globalEvent(Widget w, WidgetEvent e)
        {
            if (e.type == WidgetEventType.GLOBALHOVERCHANGE)
            {
                auto change = e.get!GlobalHoverChange;
                if (isMyChild(change.oldHover) && !isMyChild(change.newHover))
                {
                    lostHover();
                    return;
                }
            }
        }

        /**
        * Collapse children if we lose hover.
        */
        override void lostHover()
        {
            if (!isAChildHovered && m_lastHovered !is null)
            {
                collapseBranch(m_lastHovered);
                updateTree();
                m_lastHovered = null;
            }
        }

        override void updateTree()
        {
            updateScreenInfo();
            int xoffset = 0, yoffset = 0, width = 0, height = 0;

            uint depth = 0;
            void recurseHorizontal(Node node)
            {
                ++depth;

                // See if widget is still visible inside the clipping area
                node.widget.showing = true && node.shown;

                if (node.shown)
                {
                    if (node.widget.dim.x + xoffset > width)
                        width = node.widget.dim.x + xoffset;

                    if (node.widget.dim.y + yoffset > height)
                        height = node.widget.dim.y + yoffset;

                    node.widget.setPos(xoffset, yoffset);
                    node.widget.updateScreenInfo();

                    if (depth == 1)
                    {
                        auto y = yoffset;
                        foreach(child; node.children)
                        {
                            yoffset += node.widget.dim.y;
                            recurseHorizontal(child);
                        }
                        yoffset = y;
                        xoffset += node.widget.dim.x;
                    }
                    else
                    {
                        auto y = yoffset;
                        auto x = xoffset;
                        xoffset += node.widget.dim.x;
                        foreach(index, child; node.children)
                        {
                            if (index == 0)
                                yoffset += (node.widget.dim.y - child.widget.dim.y)/2.0;

                            recurseHorizontal(child);
                            yoffset += child.widget.dim.y;
                        }
                        yoffset = y;
                        xoffset = x;
                    }
                }

                --depth;
            }

            foreach(node; m_tree)
                recurseHorizontal(node);

            if (m_autoResize)
                setDim(width+1, height+1);

            needRender();
        }

        Node m_lastHovered;
        Font m_font;
        int m_xpad, m_ypad;
}

