// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: UI base elements.
*/

module glui.widget.base;

import
    std.datetime,
    std.conv,
    std.variant,
    std.algorithm,
    std.stdio,
    std.datetime,
    std.range,
    std.string,
    core.thread,
    std.math,
    std.format,
    std.array,
    std.traits;

public import /// import publicly so users can call Flag!
    std.typecons;

import
    derelict.freetype.ft,
    derelict.opengl.gl,
    derelict.util.exception;

import
    glui.window,
    glui.truetype;

public import
    glui.event,
    glui.widget.event,
    glui.widget.text,
    glui.widget.table;


// Treat 2-element static arrays as (x,y) pairs
T x(T)(T[2] v) { return v[0]; }
T y(T)(T[2] v) { return v[1]; } // ditto
ref T x(T)(ref T[2] v) { return v[0]; }
ref T y(T)(ref T[2] v) { return v[1]; } // ditto

// Treat 4-element static arrays as (r,g,b,a) colors
T r(T)(T[4] v) { return v[0]; }
T g(T)(T[4] v) { return v[1]; }
T b(T)(T[4] v) { return v[2]; }
T a(T)(T[4] v) { return v[3]; }
ref T r(T)(ref T[4] v) { return v[0]; }
ref T g(T)(ref T[4] v) { return v[1]; }
ref T b(T)(ref T[4] v) { return v[2]; }
ref T a(T)(ref T[4] v) { return v[3]; }

// Structure for storing RGBA colors
struct RGBA
{
    static RGBA opCall(float r, float g, float b, float a)
    {
        RGBA o;

        /**
        * If any of the values are greater than 1, assume we have been
        * given ints, which need to be converted to floats.
        */
        if (r > 1 || g > 1 || b > 1 || a > 1)
        {
            o.r = r/255.;
            o.g = g/255.;
            o.b = b/255.;
            o.a = a/255.;
        }
        else
        {
            o.r = r;
            o.g = g;
            o.b = b;
            o.a = a;
        }
        return o;
    }

    static RGBA opCall(float[4] v)
    {
        return RGBA(v[0], v[1], v[2], v[3]);
    }

    // Stored internally as floats [0..1]
    union
    {
        struct
        {
            float r = 0;
            float g = 0;
            float b = 0;
            float a = 0;
        }
        float[4] v;
    }

    alias v this;

}


// Number of points to include in rounded corners
enum arcResolution = 10;


// Distance between two points
float distance(int[2] p1, int[2] p2)
{
    return sqrt( cast(float)((p1.x - p2.x)*(p1.x - p2.x) + (p1.y - p2.y)*(p1.y - p2.y)));
}


// Check if a given point is within a widgets boundary
bool isInside(Widget w, int[2] point)
{
    int[4] clip = w.clip;

    if (w.parent) // Allow the widgets container to transform the clip box
    {
        w.parent.transformPos(w, point);
        w.parent.transformClip(w, clip);
    }

    auto radius = min(w.cornerRadius, w.dim.x/2, w.dim.y/2);  // TODO: is this a slow point?

    // First check for point inside one of the two sqaures which cover the non-rounded corners
    if (point.x >= clip[0] && point.x <= clip[0] + clip[2] &&
        point.y >= clip[1] + radius && point.y <= clip[1] + clip[3] - radius)
        return true;
    else if (point.x >= clip[0] + radius && point.x <= clip[0] + clip[2] - radius &&
             point.y >= clip[1] && point.y <= clip[1] + clip[3] )
        return true;
    // Check if we are in one of the corners
    else if ((distance([clip[0] + radius, clip[1] + clip[3] - radius], [point.x, point.y]) <= radius) ||
             (distance([clip[0] + clip[2] - radius, clip[1] + clip[3] - radius], [point.x, point.y]) <= radius) ||
             (distance([clip[0] + clip[2] - radius, clip[1] + radius], [point.x, point.y]) <= radius) ||
             (distance([clip[0] + radius, clip[1] + radius], [point.x, point.y]) <= radius))
            return true;
    else
        return false;
}


// Check if a given point is within a given box (this one won't account for rounded corners!)
bool isInside(int[2] scrPos, int[2] dim, int[2] point)
{
    return (point.x >= scrPos.x && point.x <= scrPos.x + dim.x &&
            point.y >= scrPos.y && point.y <= scrPos.y + dim.y );
}


/**
* Test to see if the bounding boxes of two widgets overlap
*/
bool overlap(Widget w1, Widget w2)
{
    auto p1 = w1.screenPos;
    auto d1 = w1.dim;

    if (w1.parent) // Allow widget container to transform geometry
    {
        w1.parent.transformPos(w1, p1);
        w1.parent.transformDim(w1, d1);
    }

    auto p2 = w2.screenPos;
    auto d2 = w2.dim;

    if (w2.parent) // Allow widget container to transform geometry
    {
        w2.parent.transformPos(w2, p2);
        w2.parent.transformDim(w2, d2);
    }

    if (p1.x + d1.x < p2.x) return false; // a is left of b
    if (p1.x > p2.x + d2.x) return false; // a is right of b
    if (p1.y + d1.y < p2.y) return false; // a is above b
    if (p1.y > p2.y + d2.y) return false; // a is below b
    return true; // boxes overlap
}


/**
* Calculate the smallest clipping box, given two boxes.
*/
void smallestBox(ref int[4] childbox, int[4] parentbox)
{
    int[4] cbox = [childbox[0], childbox[1], childbox[0] + childbox[2], childbox[1] + childbox[3]];
    int[4] pbox = [parentbox[0], parentbox[1], parentbox[0] + parentbox[2], parentbox[1] + parentbox[3]];

    if (cbox[0] <= pbox[0]) cbox[0] = pbox[0] + 1;
    if (cbox[1] <= pbox[1]) cbox[1] = pbox[1] + 1;
    if (cbox[2] >= pbox[2]) cbox[2] = pbox[2] - 1;
    if (cbox[3] >= pbox[3]) cbox[3] = pbox[3] - 1;

    childbox[0] = cbox[0];
    childbox[1] = cbox[1];
    childbox[2] = cbox[2] - cbox[0];
    childbox[3] = cbox[3] - cbox[1];

    if (childbox[2] < 0) childbox[2] = 0;
    if (childbox[3] < 0) childbox[3] = 0;
}


alias Variant[string] WidgetArgs;

void fill(T...)(WidgetArgs args, T fields)
{
    Variant* ptr = null;

    foreach(field; fields)
    {
        static if (is(typeof(field) dummy == KeyVal!U, U))
        {
            ptr = field.key in args;
            if (ptr !is null)
            {
                static if (is(U == int[2]))
                    *field.val = ptr.get!(int[]);
                else
                    *field.val = ptr.get!U;
            }
        }
    }
}

KeyVal!T arg(T)(string k, ref T t)
{
    KeyVal!T kv;
    kv.key = k.toLower;
    kv.val = &t;
    return kv;
}

struct KeyVal(T)
{
    string key;
    T* val;
}

WidgetArgs widgetArgs(T...)(T args)
{
    WidgetArgs out_args;
    string current = "";
    Variant holder;
    bool expectVal = false;

    foreach(arg; args)
    {
        static if (isTuple!(typeof(arg)))
        {
            auto sub_args = widgetArgs(arg.expand);
            foreach(key, val; sub_args)
                out_args[key] = Variant(val);
        }
        else
        {
            if (!expectVal)
            {
                static if (is(typeof(arg) == string))
                {
                    current = arg.toLower;
                    expectVal = true;
                }
                else
                {
                    // We don't really need to assert, but
                    assert(false, "Error: expected argument name, not " ~ arg.to!string);
                }
            }
            else
            {
                holder = arg;
                out_args[current] = holder;
                expectVal = false;
                current = "";
            }
        }
    }
    return out_args;
}


enum EdgeFlag
{
    NONE    = 0x00,
    TOP     = 0x01,
    BOTTOM  = 0x02,
    LEFT    = 0x04,
    RIGHT   = 0x08
}

enum ResizeFlag
{
    NONE    = 0x00,
    X       = 0x01,
    Y       = 0x02
}

enum AdaptX
{
    NONE,
    RESIZE,
    MAINTAIN_LEFT,
    MAINTAIN_RIGHT
}

enum AdaptY
{
    NONE,
    RESIZE,
    MAINTAIN_TOP,
    MAINTAIN_BOTTOM
}

enum Orientation
{
    VERTICAL, HORIZONTAL
}



/**
* Widget base class.
*/
abstract class Widget
{
    package this(WidgetRoot root, Widget parent)
    {
        m_root = root;
        this.setParent(parent);
    }

    public:

        // All widgets use this event signaler
        PrioritySignal!(Widget, WidgetEvent) eventSignal;

        void set(WidgetArgs args)
        {
            fill(args, arg("dim", m_dim),
                       arg("pos", m_pos),
                       arg("cornerradius", m_cornerRadius),
                       arg("showing", m_showing),
                       arg("clipped", m_clipped),
                       arg("blocking", m_blocking),
                       arg("candrag", m_canDrag),
                       arg("resize", m_resize));
        }


        // Get
        @property int[2] screenPos() const { return m_screenPos; }
        @property int[2] pos() const { return m_pos; }
        @property int[2] dim() const { return m_dim; }
        @property int[4] clip() const { return m_clip; }
        @property bool showing() const { return m_showing; }
        @property bool visible() const { return m_visible; }
        @property bool blocking() const { return m_blocking; }
        @property bool clipped() const { return m_clipped; }
        @property bool focusable() const { return m_focusable; }
        @property bool canDrag() const { return m_canDrag; }
        @property WidgetRoot root() { return m_root; }
        @property Widget parent() { return m_parent; }
        @property Widget[] children() { return m_children; }
        long lastFocused() const { return m_lastFocused; }
        @property string type() const { return m_type; }
        @property int cornerRadius() const { return m_cornerRadius; }

        // Set
        @property void canDrag(bool v) { m_canDrag = v; }
        @property void clipped(bool v) { m_clipped = v; }
        @property void focusable(bool v) { m_focusable = v; }
        @property void blocking(bool v) { m_blocking = v; }
        @property void showing(bool v) { m_showing = v; needRender(); }
        @property void root(WidgetRoot root) { m_root = root; }
        @property void cornerRadius(int v) { m_cornerRadius = v; }

        void setParent(Widget newParent)
        {
            if (newParent is this) // Cant be it's own parent! (inf loops!)
                return;

            if (m_parent !is null)
                m_parent.delChild(this);

            if (newParent is null)
                newParent = m_root;

            m_parent = newParent; // set new parent
            newParent.addChild(this); // add me to new parent's child list
            m_lastFocused = m_parent.lastFocused + 1;
        }

        // Set position
        void setPos(int[] pos)
        in
        {
            assert(pos.length == 2);
        }
        body
        {
            m_pos = pos;
            geometryChanged(GeometryChangeFlag.POSITION);
        }

        // Set position
        void setPos(int x, int y)
        {
            m_pos = [x, y];
            geometryChanged(GeometryChangeFlag.POSITION);
        }

        // Set dimension
        void setDim(int[] dim)
        in
        {
            assert(dim.length == 2);
        }
        body
        {
            m_dim = dim;
            geometryChanged(GeometryChangeFlag.DIMENSION);
        }

        // Set dimension
        void setDim(int w, int h)
        {
            m_dim = [w, h];
            geometryChanged(GeometryChangeFlag.DIMENSION);
        }

        // Print out the hierarchy
        void print(ref Appender!(char[]) buf, ref string prefix)
        {
            buf.put(prefix ~ this.to!string ~ "\n");
            prefix = "  " ~ prefix;

            foreach(child; m_children)
                child.print(buf, prefix);

            if (prefix.length > 2)
                prefix = prefix[2..$];
        }

        @property bool amIFocused() const { return m_root.isFocused(this); }

        @property bool isAChildFocused() const
        {
            bool focused = false;
            foreach(widget; m_children)
            {
                focused = widget.amIFocused() || widget.isAChildFocused();
                if (focused)
                    break;
            }
            return focused;
        }

        @property bool amIHovered() const { return m_root.isHovered(this); }

        @property bool isAChildHovered() const
        {
            bool hovered = false;
            foreach(widget; m_children)
            {
                hovered= widget.amIHovered() || widget.isAChildHovered();
                if (hovered)
                    break;
            }
            return hovered;
        }

        @property bool amIDragging() const { return m_root.isDragging(this); }
        @property bool amIResizing() const { return m_root.isResizing(this); }

        // Current elapsed time in milliseconds
        @property long timerMsecs() const { return m_root.timerMsecs; }

        // CTRL key is down
        @property bool ctrlIsDown() const { return m_root.ctrlIsDown; }

        // SHIFT key is down
        @property bool shiftIsDown() const { return m_root.shiftIsDown; }

        // Called when a widget requires rendering
        void needRender()
        {
            m_root.needRender();
        }

        //
        void preRender()
        {
            if (m_clipped)
            {
                auto clip = m_clip;
                clipboxToScreen(clip);
                glScissor(clip[0], clip[1], clip[2], clip[3]);
            }

            glPushMatrix();
            glTranslatef(m_pos.x, m_pos.y, 0);
        }

        void postRender()
        {
            glPopMatrix();
            glScissor(0, 0, m_root.dim.x, m_root.dim.y);
            //debug { renderClip(); }
        }

        // Render this widget
        void render(Flag!"RenderChildren" recurse)
        {
            if (recurse)
                renderChildren();
        }

        // Render this widget's children
        void renderChildren()
        {
            foreach(child; m_children)
            {
                if (!child.visible)
                    continue;

                child.preRender();
                child.render(Flag!"RenderChildren".yes);
                child.postRender();
            }
        }

        // Render the widget's clip box for debugging
        void renderClip()
        {
            // Draw a debug outline
            auto _clip = m_clip;

            // Then clip window
            glPushMatrix();
            glLoadIdentity();
            glColor4f(0,1,.6,1);
            glDisable(GL_SCISSOR_TEST);
            glBegin(GL_LINE_LOOP);
            glVertex2f(_clip[0], _clip[1]);
            glVertex2f(_clip[0] + _clip[2], _clip[1]);
            glVertex2f(_clip[0] + _clip[2], _clip[1] + _clip[3]);
            glVertex2f(_clip[0], _clip[1] + _clip[3]);
            glEnd();
            glEnable(GL_SCISSOR_TEST);

            glPopMatrix();
        }

        // Handle events
        void event(ref Event event) {}

        // Widget has gained focus
        void gainedFocus() {}

        // Widget has lost focus
        void lostFocus() {}

        // Mouse is now hovering over widget
        void gainedHover() {}

        // Mouse has stopped hovering over widget
        void lostHover() {}

        // Flag to indicate which aspects of geometry have changed
        enum GeometryChangeFlag
        {
            POSITION    = 0x01,
            DIMENSION   = 0x02
        }
        void geometryChanged(GeometryChangeFlag flag) {}

        // Schedule a timer event from WidgetRoot
        void requestTimer(long delay, void delegate(long) dgt, bool recurring = false)
        {
            m_root.requestTimer(this, delay, dgt, recurring);
        }

        // UnSchedule a timer event from WidgetRoot
        void removeTimer(long delay, void delegate(long) dgt, bool recurring = false)
        {
            m_root.removeTimer(this, delay, dgt, recurring);
        }

        // Override these to control dragging of your widget
        bool requestDrag(int[2] pos)
        {
            return ((pos.y - m_screenPos.y) < 20) && m_canDrag;
        }

        // Override this to provide customized drag logic
        void drag(int[2] pos, int[2] delta)
        {
            // By default, if a widget allows dragging, it drags in both x and y, unconstrained
            m_pos[] += delta[];

            // Flag the change in geometry
            geometryChanged(Widget.GeometryChangeFlag.POSITION);

            // Signal event
            eventSignal.emit(this, WidgetEvent(Drag(pos, delta)));
        }

        // Override these to control resizing of your widget
        bool requestResize(int[2] pos)
        {
            if (!m_resize)
                return false;

            m_resizing = EdgeFlag.NONE;

            if (m_resize & ResizeFlag.X)
            {
                if (abs(pos.x - m_screenPos.x) < 4)
                    m_resizing |= EdgeFlag.LEFT;

                if (abs(pos.x - (m_screenPos.x + m_dim.x)) < 4)
                    m_resizing |= EdgeFlag.RIGHT;
            }

            if (m_resize & ResizeFlag.Y)
            {
                if (abs(pos.y - m_screenPos.y) < 4)
                    m_resizing |= EdgeFlag.TOP;

                if (abs(pos.y - (m_screenPos.y + m_dim.y)) < 4)
                    m_resizing |= EdgeFlag.BOTTOM;
            }

            return m_resizing != EdgeFlag.NONE;
        }

        // Need to override this to create resizing ability
        void resize(int[2] pos, int[2] delta, Flag!"TopLevel" top = Flag!"TopLevel".no)
        {
            int[2] preDim = m_dim, prePos = m_pos;

            with(EdgeFlag)
            {
                if (top)
                {
                    assert(m_resize);

                    if (m_resizing & LEFT)
                    {
                        m_pos[0] += delta.x;
                        m_dim[0] -= delta.x;
                    }

                    if (m_resizing & RIGHT)
                        m_dim[0] += delta.x;

                    if (m_resizing & TOP)
                    {
                        m_pos[1] += delta.y;
                        m_dim[1] -= delta.y;
                    }

                    if (m_resizing & BOTTOM)
                        m_dim[1] += delta.y;
                }
                else
                {

                    if (m_resizing & LEFT && m_onParentResizeX)
                    {
                        final switch(m_onParentResizeX) with(AdaptX)
                        {
                            case RESIZE:
                                m_dim[0] -= delta.x;
                                break;
                            case MAINTAIN_LEFT:
                                break;
                            case MAINTAIN_RIGHT:
                                m_pos[0] -= delta.x;
                                break;
                            case NONE:
                        }
                    }

                    if (m_resizing & RIGHT && m_onParentResizeX)
                    {
                        final switch(m_onParentResizeX) with(AdaptX)
                        {
                            case RESIZE:
                                m_dim[0] += delta.x;
                                break;
                            case MAINTAIN_LEFT:
                                break;
                            case MAINTAIN_RIGHT:
                                m_pos[0] += delta.x;
                                break;
                            case NONE:
                        }
                    }

                    if (m_resizing & TOP && m_onParentResizeY)
                    {
                        final switch(m_onParentResizeY) with(AdaptY)
                        {
                            case RESIZE:
                                m_dim[1] -= delta.y;
                                break;
                            case MAINTAIN_TOP:
                                break;
                            case MAINTAIN_BOTTOM:
                                m_pos[1] -= delta.y;
                                break;
                            case NONE:
                        }
                    }

                    if (m_resizing & BOTTOM && m_onParentResizeY)
                    {
                        final switch(m_onParentResizeY) with(AdaptY)
                        {
                            case RESIZE:
                                m_dim[1] += delta.y;
                                break;
                            case MAINTAIN_TOP:
                                break;
                            case MAINTAIN_BOTTOM:
                                m_pos[1] += delta.y;
                                break;
                            case NONE:
                        }
                    }

                    // These conditionals undo repositioning which occurs automatically
                    if (m_resizing & LEFT && !m_onParentResizeX)
                        m_pos[0] -= delta.x;

                    if (m_resizing & TOP && !m_onParentResizeY)
                        m_pos[1] -= delta.y;

                }

            } // with(EdgeFlag)

            geometryChanged(GeometryChangeFlag.POSITION |
                            GeometryChangeFlag.DIMENSION );

            // Signal event
            eventSignal.emit(this, WidgetEvent(Resize(prePos, preDim)));

            /**
            * Alert children
            */
            foreach(child; m_children)
            {
                child.m_resizing = m_resizing;
                child.resize(pos, delta, Flag!"TopLevel".no);
            }
        }


        /**
        * Recursively find the focused widget. Return true if a focus was found,
        * and finalFocus will be the reference to the focused widget.
        */
        bool focus(int[2] pos, ref Widget finalFocus)
        {
            // If click was inside my bounds, list me as focused
            if (m_visible && this.isInside(pos) && m_focusable)
            {
                // Give parent a chance to steal the focus
                if (m_parent)
                {
                    if (m_parent.stealFocus(pos, this))
                    {
                        finalFocus = m_parent;
                        return true;
                    }
                }

                finalFocus = this;

                // But if I have children, pass the focus on to one of them
                foreach(widget; m_children)
                    widget.focus(pos, finalFocus);

                return true;
            }
            return false;
        }

        /**
        * Find the lowest level (deepest) ancestor, and start the lastFocused
        * update from there, recursing down through children.
        */
        void applyFocus(long last)
        {
            // Find ultimate ancestor (lowest level parent)
            Widget ancestor = null, current = this;
            while(ancestor is null)
            {
                if (current.parent is null || current.parent is current.m_root)
                    ancestor = current;
                else
                    current = current.parent;
            }

            // Update my lastFocused, triggering a recursive descent
            ancestor.lastFocused(last);
        }

        /**
        * Set the lastFocused (widget depth), and update children.
        */
        void lastFocused(long last)
        {
            m_lastFocused = last;
            foreach(child; m_children)
                child.lastFocused(last + 1);
        }

        /**
        * Steal the focus from a child.
        */
        bool stealFocus(int[2] pos, Widget child)
        {
            return false;
        }

        /**
        * Recurse through the hierarchy to find the maximum lastFocused value
        */
        void maxLastFocused(ref long maxFocus) const
        {
            if (m_lastFocused > maxFocus)
                maxFocus = m_lastFocused;

            foreach(child; m_children)
                if (child.visible)
                    child.maxLastFocused(maxFocus);
        }

        // Add a child to this widget's list of children
        void addChild(Widget w)
        {
            m_children ~= w;
        }

        // Remove all children
        void clearChildren()
        {
            m_children.clear;
        }


        // Delete a child from this widget's list of children
        void delChild(Widget w)
        {
            foreach(index, child; m_children)
            {
                if (child is w)
                    m_children = m_children.remove(index);
            }
        }

        // Update the absolute screen position, visibility, and clipping of this widget
        void updateScreenInfo()
        {
            m_screenPos[] = m_parent.screenPos[] + m_pos[];
            m_clip = getClipBox();

            // Child can only be visible if parent is visible
            m_visible = m_parent.visible && m_showing;

            if (m_clipped)
                smallestBox(m_clip, m_parent.getChildClipBox(this));

            foreach(child; m_children)
                child.updateScreenInfo();
        }

        // Override this to set a custom clip box for the widget
        int[4] getClipBox()
        {
            int[4] clip = [m_screenPos.x - 1,
                           m_screenPos.y - 1,
                           m_dim.x + 1,
                           m_dim.y + 1];

            if (m_parent)
                m_parent.transformClip(this, clip);

            return clip;
        }

        // Override this to set a custom clip box for the widget's children
        int[4] getChildClipBox(Widget w)
        {
            auto clip = getClipBox();

            if (m_cornerRadius != 0)
            {
                clip[0] += m_cornerRadius;
                clip[1] += m_cornerRadius;
                clip[2] -= 2*m_cornerRadius;
                clip[3] -= 2*m_cornerRadius;
            }

            if (m_clipped && m_parent)
                smallestBox(clip, m_parent.getChildClipBox(this));

            return clip;
        }

        // Convert a clip box (which is given in the upside down gui coords) to screen coords
        void clipboxToScreen(ref int[4] box)
        {
            box[1] = m_root.m_window.windowState.ypix - (box[1] + box[3]);
        }

        // Sort the widget list by scene depth
        void sortChildren()
        {
            sort!("a.lastFocused() < b.lastFocused()")(m_children);
            foreach(child; m_children)
                child.sortChildren();
        }

        // Transform a position for a child
        void transformPos(Widget w, ref int[2] pos)
        {
            if (m_parent)
                m_parent.transformPos(this, pos);
        }

        // Transform a dimension for a child
        void transformDim(Widget w, ref int[2] dim)
        {
            if (m_parent)
                m_parent.transformDim(this, dim);
        }

        // Transform a screen position for a child
        void transformClip(Widget w, ref int[4] clipbox)
        {
            if (m_parent)
                m_parent.transformClip(this, clipbox);
        }


        Widget m_parent = null;
        Widget[] m_children = null;
        WidgetRoot m_root = null;

        int[2] m_pos = [0,0]; // position relative to parent
        int[2] m_dim = [10,10]; // absolute width currently...
        int[2] m_screenPos = [0,0]; // absolute screen position
        int[4] m_clip = [0,0,10,10]; // x, y, x-dim, y-dim, in screen coords

        bool m_showing = true; // this decides whether or not widget _should_ be shown
        bool m_visible = true; // this decides wether or not widget _will_ be shown, based on parent's visibility
        bool m_clipped = true;
        bool m_focusable = true; // can deactivate widgets this way
        bool m_canDrag = false;
        bool m_blocking = false; // blocking widgets don't lose focus
        long m_lastFocused = 0;
        int m_cornerRadius = 0;

        ResizeFlag m_resize = ResizeFlag.NONE;
        EdgeFlag m_resizing = EdgeFlag.NONE;
        AdaptX m_onParentResizeX = AdaptX.MAINTAIN_LEFT;
        AdaptY m_onParentResizeY = AdaptY.MAINTAIN_TOP;

        string m_type = "WIDGET";
}



/**
* The WidgetRoot is responsible for creating widgets, maintaining a depth-sorted
* list of all widgets for rendering, calling each widget's render method, checking
* for widget dragging/resizing and focus/hover changes, and injecting events recieved
* from the Window. There should be one WidgetRoot for every Window which contains
* GUI elements.
*/
class WidgetRoot : Widget
{
    public:

        this(Window wnd)
        {
            super(this, this);

            m_root = this;
            m_parent = null;
            m_type = "WIDGETROOT";
            m_window = wnd;
            wnd.event.connect(&this.injectEvent);
            m_eventTimer.start();
            setViewport();
        }

        // Poll for events, and put the current thread to sleep if needed
        void poll()
        {
            m_window.poll();

            if (m_needRender)
                render(Flag!"RenderChildren".yes);

            // Check to see if timer events need to be issued
            long ctime = m_eventTimer.peek().msecs;
            auto scope keys = m_timerCallbacks.keys;
            auto scope times = m_timerCallbacks.values;
            foreach(index, key; keys)
            {
                if (ctime >= times[index])
                {
                    if (!key.oneTimeOnly)
                        m_timerCallbacks[key] = times[index] + key.delay; // Event is recurrent, so update calltime
                    else
                        m_timerCallbacks.remove(key);

                    /**
                    * Event needs to be issued (remember: widgets might call requestTimer()
                    * or removeTimer() from key.dgt!)
                    */
                    key.dgt(key.delay);
                }
            }

            auto callTimeDiff = m_eventTimer.peek().msecs - m_lastPollTick;
            m_lastPollTick = m_eventTimer.peek().msecs;

            // Make the delay between polls equal to 30 msecs TODO: this rate should be configurable
            auto delay = 30 - callTimeDiff;
            if (delay > 0)
                Thread.sleep( dur!("msecs")( delay ) );
        }

        // Render all widgets which have this root
        override void render(Flag!"RenderChildren" recurse)
        {
            // Update screen positions
            foreach(child; m_children)
                child.updateScreenInfo();

            glClear( GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT );

            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();

            glPushAttrib(GL_LIST_BIT|GL_CURRENT_BIT|GL_ENABLE_BIT|GL_TRANSFORM_BIT);
            glMatrixMode(GL_MODELVIEW);
            glEnable(GL_TEXTURE_2D);
            glEnable(GL_BLEND);
            glEnable(GL_SCISSOR_TEST);
            glBindTexture(GL_TEXTURE_2D, 0);
            glDisable(GL_DEPTH_TEST);
            glDisable(GL_LIGHTING);
            float[4] envColor = [1.0,1.0,1.0,1.0];
            glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, envColor.ptr); // Set this, so we can use GL_BLEND with LUMINANCE textures
            glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);

            glScissor(0, 0, m_dim[0], m_dim[1]);
            renderChildren();

            glPopAttrib();
            m_window.swapBuffers();
            m_needRender = false;
        }

        // Update the viewport and root clip box to reflect current window size
        void setViewport()
        {
            glViewport(0,0,m_window.windowState.xpix, m_window.windowState.ypix);
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            glOrtho(0, m_window.windowState.xpix, m_window.windowState.ypix, 0, -1.0, 1.0);
            glMatrixMode(GL_MODELVIEW);
            m_dim = [window.windowState.xpix, window.windowState.ypix];
            m_clip = [0,0, m_dim[0], m_dim[1]];
        }

        // Inject an event into the heirarchy
        int injectEvent(Event event)
        {
            switch(event.type) with(EventType)
            {
                case WINDOWPAINT:
                {
                    // Check for window paint message, need to rerender
                    render(Flag!"RenderChildren".yes);
                    return 0;
                }
                case KEYPRESS:
                {
                    // Check for CTRL-TAB to change focus
                    if (event.get!KeyPress.key == KEY.KC_TAB && ctrlIsDown)
                    {
                        // Can't cycle focus away from a blocking widget
                        if (m_focused !is null && !m_focused.blocking)
                            cycleFocus();
                    }
                    break;
                }
                case WINDOWRESIZE:
                {
                    setViewport();
                    break;
                }
                case MOUSEMOVE:
                {
                    checkHover(event.get!MouseMove.pos);
                    checkDrag(event);
                    checkResize(event);
                    break;
                }
                case MOUSECLICK:
                {
                    if (event.get!MouseClick.button == MouseClick.Button.LEFT)
                    {
                        auto pos = event.get!MouseClick.pos;

                        // Mouseclick could potentially change the focus, so check
                        checkFocus(pos);

                        // Check for resize and drag
                        Widget current = m_focused;
                        while(current)
                        {
                            if (current.requestResize(pos))
                            {
                                m_recieveResize = current;
                                break;
                            }
                            else if (current.requestDrag(pos))
                            {
                                m_recieveDrag = current;
                                break;
                            }
                            current = current.parent;
                        }
                    }
                    break;
                }
                case MOUSERELEASE:
                {
                    m_recieveDrag = null;
                    m_recieveResize = null;
                }

                default:
            }

            // Sort the widget list.. prob dont need this every event!
            //sortWidgetList();

            // Pass events on to widgets, starting with topmost
            foreach(w; m_widgetList)
            {
                w.event(event);
                if (event.consumed) break; // A widget can consume an event, terminating this loop
            }

            return 0;
        }

        // Check for a change of focus
        void checkFocus(int[2] pos)
        {
            if (m_focused !is null && m_focused.blocking)
                return;

            Widget newFocus = null;
            foreach(widget; m_widgetList)
            {
                if (widget.focus(pos, newFocus))
                {
                    changeFocus(newFocus);
                    return;
                }
            }

            // If we get to here, no widget was clicked on, set m_focused to null
            changeFocus(null);
        }

        // Cycle the focus amongst top level children !! TODO this doesn't respect visibility
        void cycleFocus()
        {
            if (m_children.length <= 1)
                return;

            // First find the currently focused widget in the list
            uint index = 0;
            foreach(i, widget; m_children)
            {
                if (widget is m_focused)
                {
                    index = i;
                    break;
                }
            }

            while(true)
            {
                ++index;

                // Go back to start of the list if necessary
                if (index >= m_children.length - 1)
                    index = 0;

                /**
                * If we have cycled back to the currently focused widget,
                * there are no more widgets which could be focused, so
                * don't change focus.
                */
                if (m_children[index] is m_focused)
                    break;

                // We only want top-level widgets (widgets with root as parent)
                if (m_children[index].parent == this && m_children[index].visible)
                {
                    changeFocus(m_children[index]);
                    break;
                }

            }
        }

        // Give the focus to the new widget
        void changeFocus(Widget newFocus)
        {
            if (newFocus is m_focused)
                return;

            Widget oldFocus = m_focused;

            // Set the newly focused widget and alert it
            m_focused = newFocus;
            if (newFocus !is null)
            {
                m_focused.applyFocus(Clock.currSystemTick.length);
                m_focused.gainedFocus();
                m_focused.eventSignal.emit(m_focused, WidgetEvent(GainedFocus()));
            }

            // Got a new focus, so alert the previously focused widget
            if (oldFocus !is null)
            {
                oldFocus.lostFocus();
                oldFocus.eventSignal.emit(oldFocus, WidgetEvent(LostFocus()));
            }

            // Fire a global focus change event
            eventSignal.emit(this, WidgetEvent(GlobalFocusChange(newFocus, oldFocus)));

            sortWidgetList();
            sortChildren();
            needRender();
        }

        // Check for change of hovering
        void checkHover(int[2] pos)
        {
            // Dont change hover if mouse button is down
            if (m_window.mouseState.buttonsDown != 0)
                return;

            // Only give hover to topmost widget
            foreach(widget; m_widgetList)
            {
                if (!widget.visible)
                    continue;

                if (m_hovered !is null && (widget is m_hovered) && m_hovered.isInside(pos))
                    return; // currently hovered widget is still hovered

                if (widget.isInside(pos))
                {
                    if (m_hovered !is null)
                        m_hovered.lostHover();

                    m_hovered = widget;
                    m_hovered.gainedHover();
                    return;
                }
            }

            // If we get to here, no widget is hovered, set m_hovered to null
            if (m_hovered !is null)
                m_hovered.lostHover();

            m_hovered = null;
        }

        // Check for dragging
        void checkDrag(Event event)
        {
            if (m_recieveDrag !is null &&
                m_window.mouseState.left == MouseState.STATE.PRESSED)
            {
                // Only keep dragging if mouse is within our window
                auto xpos = m_window.mouseState.xpos;
                auto ypos = m_window.mouseState.ypos;
                if (xpos >= 0 || xpos <= m_window.windowState.xpix ||
                    ypos >= 0 || ypos <= m_window.windowState.ypix )
                {
                    auto pos = event.get!MouseMove.pos;
                    auto delta = event.get!MouseMove.delta;
                    m_recieveDrag.drag(pos, delta);
                    needRender();
                }
            }
        }

        void checkResize(Event event)
        {
            if (m_recieveResize !is null &&
                m_window.mouseState.left == MouseState.STATE.PRESSED)
            {
                // Only keep resizing if mouse is within our window
                auto xpos = m_window.mouseState.xpos;
                auto ypos = m_window.mouseState.ypos;
                if (xpos >= 0 || xpos <= m_window.windowState.xpix ||
                    ypos >= 0 || ypos <= m_window.windowState.ypix )
                {
                    auto pos = event.get!MouseMove.pos;
                    auto delta = event.get!MouseMove.delta;
                    m_recieveResize.resize(pos, delta, Flag!"TopLevel".yes);
                    needRender();
                }
            }
        }

        // Create a widget under this root
        T create(T : Widget, KeyVal...)(Widget parent, KeyVal args)
        {
            T newWidget = new T(this, parent);
            assert (newWidget !is null);

            newWidget.set(args);
            newWidget.geometryChanged(Widget.GeometryChangeFlag.POSITION |
                                      Widget.GeometryChangeFlag.DIMENSION);

            m_widgetList ~= newWidget;
            newWidget.applyFocus(Clock.currSystemTick.length);

            if (!m_focused)
                m_focused = newWidget;
            else
                m_focused.applyFocus(Clock.currSystemTick.length + 1);

            sortWidgetList();
            needRender();
            return newWidget;
        }

        // Destroy a widget, recursively destroying its child hierarchy
        void destroy(Widget w)
        {
            destroyRecurse(w);

            if (m_focused is w)
                m_focused = null;

            if (m_hovered is w)
                m_hovered = null;

            if (w.parent !is null)
                w.parent.delChild(w);

            sortWidgetList();
            needRender();
        }

        void destroyRecurse(Widget w)
        {
            foreach(i, wid; m_widgetList)
            {
                if (wid is w)
                {
                    m_widgetList = m_widgetList.remove(i);
                    break;
                }
            }

            foreach(i, child; w.children)
                destroyRecurse(child);

            w.clearChildren();
        }

        // Print out the widget hierarchy
        void print()
        {
            Appender!(char[]) buf;
            buf.put(this.to!string ~ "\n");
            string prefix = "|_";
            foreach(child; m_children)
                child.print(buf, prefix);

            writeln(buf.data);
        }

        // Sort the widget list
        void sortWidgetList()
        {
            sort!("a.lastFocused() > b.lastFocused()")(m_widgetList);
        }

        // Widgets can check if they have focus
        const bool isFocused(const Widget w) const { return m_focused is w; }

        // Widgets can check if one of their children has focus
        const bool isAChildFocused(const Widget w) const { return w.isAChildFocused; }

        // Widgets can check if they are being dragged
        const bool isDragging(const Widget w) const { return m_recieveDrag is w; }

        // Widgets can check if they are being resized
        const bool isResizing(const Widget w) const { return m_recieveResize is w; }

        // Widgets can check if they hovered
        const bool isHovered(const Widget w) const { return m_hovered is w; }

        // Widgets can register for timer callbacks. By default they are one-off.
        void requestTimer(Widget widget, long delay_msecs, void delegate(long) callback, bool recurring = false)
        {
            long ctime = m_eventTimer.peek().msecs;
            m_timerCallbacks[TimerCallback(widget, callback, delay_msecs, !recurring)] = ctime + delay_msecs;
        }

        // Widgets can remove a previously requested timer
        void removeTimer(Widget widget, long delay_msecs, void delegate(long) callback, bool recurring = false)
        {
            TimerCallback key = TimerCallback(widget, callback, delay_msecs, !recurring);
            if (key in m_timerCallbacks)
                m_timerCallbacks.remove(key);
        }

        // Get the current elapsed time in milliseconds from the stopwatch
        override @property long timerMsecs() const { return m_eventTimer.peek().msecs; }

        // Get the platform window we are running in
        @property Window window() { return m_window; }

        // Get the mouse state
        @property const(MouseState)* mouse() { return m_window.mouseState; }

        // Return true if CTRL key is down
        override @property bool ctrlIsDown() const
        {
            return (m_window.keyState.keys[KEY.KC_CTRL_LEFT] ||
                    m_window.keyState.keys[KEY.KC_CTRL_RIGHT]);
        }

        // Return true if SHIFT key is down
        override @property bool shiftIsDown() const
        {
            return (m_window.keyState.keys[KEY.KC_SHIFT_LEFT] ||
                    m_window.keyState.keys[KEY.KC_SHIFT_RIGHT]);
        }

        // Flag that a widget needs to be rendered
        override void needRender()
        {
            m_needRender = true;
        }

    private:
        Window m_window;
        Widget[] m_widgetList;
        Widget m_focused = null;
        Widget m_hovered = null;

        long m_lastPollTick = 0; // For calculating framerate, deciding when to sleep

        // Widgets can register for timer events
        struct TimerCallback
        {
            Widget widget;
            void delegate(long) dgt;
            long delay;
            bool oneTimeOnly = true;
        }
        long[TimerCallback] m_timerCallbacks; // AA value is the time event should be called

        StopWatch m_eventTimer;

        bool m_dragging = false; // are we dragging the focused widget?
        bool m_resizing = false; // are we resizing the focused widget?
        bool m_needRender = false; // are there widgets that need to be rendered next poll?

        Widget m_recieveDrag = null;
        Widget m_recieveResize = null;
}



/**
* CTFE
* This code gets mixed in to create a square box, plain or textured.
*/
string squareBox(bool textured = false)
{
    if (!textured)
    {
        return "
               glVertex2i(0, 0);
               glVertex2i(width, 0);
               glVertex2i(width, height);
               glVertex2i(0, height);";
    }
    else
    {
        return "
               glTexCoord2i(0, 1);
               glVertex2i(0, 0);
               glTexCoord2i(1, 1);
               glVertex2i(width, 0);
               glTexCoord2i(1, 0);
               glVertex2i(width, height);
               glTexCoord2i(0, 0);
               glVertex2i(0, height); ";
    }
}


/**
* CTFE
* This code gets mixed in to produce a box with rounded corners. The
* resolution of the arc is set by the global enum arcResolution at
* the top of this module.
*/
string roundedBox(int resolution = arcResolution, /** enum defined at top of module **/
                  bool textured = false)
{
    string s = "";
    string sx, sy;

    // Do the four corners separately, easier for my brain
    foreach(n; 0..4)
    {
        foreach(i; 1..resolution)
        {
            float angle = 0;
            string px, py;
            if (n == 0) // 180..90
            {
                angle = (3.1415926575/2.) * (2.0 - (cast(float)i)/(cast(float)resolution));
                px = "r";
                py = "r";
            }
            else if (n == 1) // 90..180
            {
                angle = (3.1415926575/2.) * (1.0 - (cast(float)i)/(cast(float)resolution));
                px = "width - r";
                py = "r";
            }
            else if (n == 2) // 360..270
            {
                angle = (3.1415926575/2.) * (4.0 - (cast(float)i)/(cast(float)resolution));
                px = "width - r";
                py = "height - r";
            }
            else if (n == 3) // 270..180
            {
                angle = (3.1415926575/2.) * (3.0 - (cast(float)i)/(cast(float)resolution));
                px = "r";
                py = "height - r";
            }

            int fx = cast(int) (cos(angle)*1000000.);
            int fy = cast(int) (-sin(angle)*1000000.);

            string fsx = fx.to!string;
            string fsy = fy.to!string;

            string xprefix, yprefix;
            if (fsx[0] == '-')
            {
                xprefix = "-";
                fsx = fsx[1..$];
            }

            if (fsy[0] == '-')
            {
                yprefix = "-";
                fsy = fsy[1..$];
            }

            if (fsx.length == 7)
                sx = xprefix ~ fsx[0] ~ "." ~ fsx[1..$];
            else
                sx = xprefix ~ "0." ~ fsx;

            if (fsy.length == 7)
                sy = yprefix ~ fsy[0] ~ "." ~ fsy[1..$];
            else
                sy = yprefix ~ "0." ~ fsy;

            if (textured)
                s ~= "glTexCoord2f( (" ~ px ~ "+ r*(" ~ sx ~ ")) / width, 1 - (" ~ py ~ "+ r*(" ~ sy ~ ")) / height);\n";

            s ~= "glVertex2f(" ~ px ~ "+ r*(" ~ sx ~ ")," ~ py ~ "+ r*(" ~ sy ~ "));\n";
        }
    }
    return s;

} // roundedBox


/**
* Basic window, a box with optional outline. This forms the base-class
* most widgets.
*/
class WidgetWindow : Widget
{

    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:

        // Background color
        @property RGBA color() const { return m_color; }

        // Border line color
        @property RGBA borderColor() const { return m_borderColor; }

        // Setters
        void setColor(RGBA v)
        {
            m_color = v;
            m_refreshCache = true;
            needRender();
        }

        void setBorderColor(RGBA v)
        {
            m_borderColor = v;
            m_refreshCache = true;
            needRender();
        }

        void setTexture(GLuint v)
        {
            m_texture = v;
            m_refreshCache = true;
            needRender();
        }

        override void set(WidgetArgs args)
        {
            super.set(args);

            m_type = "WIDGETWINDOW";
            m_cacheId = glGenLists(1);

            fill(args, arg("background", m_color),
                       arg("bordercolor", m_borderColor),
                       arg("texture", m_texture));
        }

        override void geometryChanged(Widget.GeometryChangeFlag flag)
        {
            if (flag & Widget.GeometryChangeFlag.DIMENSION)
                m_refreshCache = true;
        }

        override void render(Flag!"RenderChildren" recurse)
        {
            // r is used in a mixin, so don't change its name (this is not optimal, I know...)
            int r = min(m_cornerRadius, m_dim.x/2, m_dim.y/2);

            if (m_refreshCache || r != m_cachedRadius) // need to refresh our display lists
            {
                m_refreshCache = false;
                m_cachedRadius = r;
                glNewList(m_cacheId, GL_COMPILE_AND_EXECUTE);

                // These idents are used by the mixins
                auto width = m_dim.x;
                auto height = m_dim.y;

                if (m_texture != 0)
                {
                    glBindTexture(GL_TEXTURE_2D, m_texture);

                    glColor4fv(m_color.ptr);

                    if (m_cornerRadius == 0) // textured square box
                    {
                        glBegin(GL_POLYGON);
                        mixin(squareBox(true));
                        glEnd();
                        glBindTexture(GL_TEXTURE_2D, 0);

                        glColor4fv(m_borderColor.ptr);
                        glBegin(GL_LINE_LOOP);
                        mixin(squareBox(false));
                        glEnd();
                    }
                    else // textured rounded box
                    {
                        glBegin(GL_POLYGON);
                        mixin(roundedBox(arcResolution, true));
                        glEnd();
                        glBindTexture(GL_TEXTURE_2D, 0);

                        glColor4fv(m_borderColor.ptr);
                        glBegin(GL_LINE_LOOP);
                        mixin(roundedBox(arcResolution, false));
                        glEnd();
                    }

                }
                else
                {
                    glColor4fv(m_color.ptr);

                    if (m_cornerRadius == 0) // non-textured square box
                    {
                        glBegin(GL_POLYGON);
                        mixin(squareBox(false));
                        glEnd();

                        glColor4fv(m_borderColor.ptr);
                        glBegin(GL_LINE_LOOP);
                        mixin(squareBox(false));
                        glEnd();
                    }
                    else // non-textured rounded box
                    {
                        glBegin(GL_POLYGON);
                        mixin(roundedBox(arcResolution, false));
                        glEnd();

                        glColor4fv(m_borderColor.ptr);
                        glBegin(GL_LINE_LOOP);
                        mixin(roundedBox(arcResolution, false));
                        glEnd();
                    }
                }

                glEndList(); // the above stuff is cached in a display list
            }
            else // Have cached display list already
            {
                glCallList(m_cacheId);
            }

            if (recurse)
                renderChildren();
        }

    package:

        RGBA m_color = {0,0,0,1};
        RGBA m_borderColor = {0,0,0,0};
        GLuint m_texture = 0;
        GLuint m_cacheId = 0; // glDisplayList for caching
        int m_cachedRadius = 0; // radius when list was cached
        bool m_refreshCache = true;
}


class WidgetPanWindow : WidgetWindow
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:

        override void set(WidgetArgs args)
        {
            super.set(args);
            m_canDrag = true;
        }

        override bool requestDrag(int[2] pos)
        {
            return true;
        }

        override void drag(int[2] pos, int[2] delta)
        {
            m_translation[] += delta[];
        }

        override void addChild(Widget child)
        {
            m_children ~= child;
            child.canDrag = false;
        }

        override void render(Flag!"RenderChildren" recurse)
        {
            super.render(Flag!"RenderChildren".no);

            foreach(child; m_children)
                renderChild(child);
        }

        override void event(ref Event event)
        {
            if (!amIHovered && !isAChildHovered) return;

            if (event.type == EventType.MOUSEWHEEL)
            {
                auto delta = event.get!MouseWheel.delta/1200.;
                m_zoom += delta;

                // First time through we store the orignial widget positions
                if (m_setPositions)
                {
                    m_setPositions = false;
                    foreach(child; m_children)
                        m_opositions[child] = child.pos;
                }

                // Apply zoom to original positions to avoid creep
                foreach(child; m_children)
                {
                    auto pos = *(child in m_opositions);
                    writeln(pos);
                    child.setPos(cast(int)round(pos.x * m_zoom),
                                 cast(int)round(pos.y * m_zoom));
                }

                needRender();
            }
        }

        override void transformPos(Widget w, ref int[2] pos)
        {
            Widget.transformPos(this, pos);

            pos[0] += m_translation.x;
            pos[1] += m_translation.y;
        }

        override void transformDim(Widget w, ref int[2] dim)
        {
            Widget.transformDim(this, dim);

            dim[0] *= m_zoom;
            dim[1] *= m_zoom;
        }

        override void transformClip(Widget w, ref int[4] clipbox)
        {
            Widget.transformClip(this, clipbox);

            clipbox[0] += m_translation[0];
            clipbox[1] += m_translation[1];
            clipbox[2] *= m_zoom;
            clipbox[3] *= m_zoom;
        }

        // Override this so that we don't give focus to child (contained) widgets
        override bool focus(int[2] pos, ref Widget finalFocus)
        {
            // If click was inside my bounds, list me as focused
            if (m_visible && this.isInside(pos) && m_focusable)
            {
                finalFocus = this;
                return true;
            }
            return false;
        }

    private:

        void renderChild(Widget w)
        {
            if (!overlap(w, this))
                return;

            glTranslatef(m_translation.x, m_translation.y, 0);
            w.preRender();
            glScalef(m_zoom, m_zoom, 1);
            w.render(Flag!"RenderChildren".no);
            w.postRender();
            glTranslatef(-m_translation.x, -m_translation.y, 0);

            foreach(c; w.children)
                renderChild(c);
        }

        int[2] m_translation;
        float m_zoom = 1;
        int[2][Widget] m_opositions;
        bool m_setPositions = true;
}


class WidgetScroll : WidgetWindow
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:

        override void set(WidgetArgs args)
        {
            super.set(args);
            m_type = "WIDGETSCROLL";

            int smin, smax;
            fill(args, arg("min", smin),
                       arg("max", smax),
                       arg("orientation", m_orient),
                       arg("fade", m_hideWhenNotHovered),
                       arg("scrolldelta", m_scrollDelta),
                       arg("slidercolor", m_slideColor),
                       arg("sliderborder", m_slideBorder),
                       arg("sliderlength", m_slideLength));

            if ("range" in args)
            {
                auto rnge = ("range" in args).get!(int[]);
                smin = rnge[0];
                smax = rnge[1];
            }

            if (smin > smax)
                smin = smax = 0;

            m_range = [smin, smax];
            m_backgroundAlphaMax = m_color.a;
            m_slideAlphaMax = m_slideColor.a;
            m_slideBorderAlphaMax = m_slideBorder.a;
            m_resize = ResizeFlag.NONE;

            if (m_orient == Orientation.VERTICAL)
            {
                m_onParentResizeX = AdaptX.MAINTAIN_RIGHT;
                m_onParentResizeY = AdaptY.RESIZE;
            }

            if (m_orient == Orientation.HORIZONTAL)
            {
                m_onParentResizeX = AdaptX.RESIZE;
                m_onParentResizeY = AdaptY.MAINTAIN_BOTTOM;
            }

            fadeInAndOut = m_hideWhenNotHovered;
            updateSlider();
        }

        // Get
        @property bool fadeInAndOut() const { return m_hideWhenNotHovered; }
        @property int[2] range() const { return m_range; }
        @property int current() const { return m_current; }

        // Set
        @property void range(int[2] v)
        {
            m_range[] = v[];

            if (m_orient == Orientation.VERTICAL)
            {
                m_current = cast(int) ((m_range[1]-m_range[0]) * ((m_slidePos[1] - m_slideLimit[0]) /
                                       cast(float)(m_slideLimit[1] - m_slideLimit[0])));
            }
            else if (m_orient == Orientation.HORIZONTAL)
            {
                m_current = cast(int) ((m_range[1]-m_range[0]) * ((m_slidePos[0] - m_slideLimit[0]) /
                                       cast(float)(m_slideLimit[1] - m_slideLimit[0])));
            }
        }

        @property void fadeInAndOut(bool b)
        {
            m_hideWhenNotHovered = b;
            if (b && !m_fadingIn && !m_fadingOut)
            {
                m_color.a = 0;
                m_slideColor.a = 0;
                m_slideBorder.a = 0;
            }
            else
            {
                m_color.a = m_backgroundAlphaMax;
                m_slideColor.a = m_slideAlphaMax;
                m_slideBorder.a = m_slideBorderAlphaMax;
            }

            m_refreshCache = true;
            needRender();
        }

        @property void current(int v)
        {
            if (v >= m_range[0] && v <= m_range[1])
            {
                m_current = v;
                updateSlider();
            }
        }

        // If the geometry has changed, update
        override void geometryChanged(Widget.GeometryChangeFlag flag)
        {
            super.geometryChanged(flag);
            updateSlider();
        }

        void updateSlider()
        {
            float sf = m_current / cast(float)(m_range[1] - m_range[0]);

            if (m_orient == Orientation.VERTICAL)
            {
                auto slen = cast(int)(m_dim.y * m_slideLength);
                int sw = cast(int)(m_dim.x*0.8);
                m_slidePos = [(m_dim.x - sw)/2, cast(int)(sf*m_dim.y)];
                m_slideDim = [sw, slen];
                m_slideLimit = [0, m_dim.y - slen];
            }
            else if (m_orient == Orientation.HORIZONTAL)
            {
                auto slen = cast(int)(m_dim.x * m_slideLength);
                int sw = cast(int)(m_dim.y*0.8);
                m_slidePos = [cast(int)(sf*m_dim.x), (m_dim.y - sw)/2];
                m_slideDim = [slen, sw];
                m_slideLimit = [0, m_dim.x - slen];
            }

            m_refreshCache = true;
            needRender();

        }
        // Render, call super then render the slider and buttons
        override void render(Flag!"RenderChildren" recurse)
        {
            // If enough time has elapsed since the last scroll event, start fading out
            if (timerMsecs - m_lastScrollTime > m_postScrollFadeDelay &&
                m_waitingForScrollDelay &&
                !amIDragging &&
                !amIHovered)
            {
                lostHover();
                m_waitingForScrollDelay = false;
            }

            super.render(Flag!"RenderChildren".no);

            // r is used in a mixin, so don't change its name (this is not optimal, I know...)
            int r = min(m_cornerRadius, m_dim.x/2, m_dim.y/2);

            // These idents are used by the mixins
            auto width = m_slideDim.x;
            auto height = m_slideDim.y;

            glTranslatef(m_slidePos.x, m_slidePos.y, 0);

                if (m_cornerRadius == 0) // non-textured square box
                {
                    glColor4fv(m_slideColor.ptr);
                    glBegin(GL_POLYGON);
                    mixin(squareBox(false));
                    glEnd();

                    glColor4fv(m_slideBorder.ptr);
                    glBegin(GL_LINE_LOOP);
                    mixin(squareBox(false));
                    glEnd();
                }
                else // non-textured rounded box
                {
                    glColor4fv(m_slideColor.ptr);
                    glBegin(GL_POLYGON);
                    mixin(roundedBox(5, false));
                    glEnd();

                    glColor4fv(m_slideBorder.ptr);
                    glBegin(GL_LINE_LOOP);
                    mixin(roundedBox(5, false));
                    glEnd();
                }

            glTranslatef(-m_slidePos.x, -m_slidePos.y, 0);

            if (recurse)
                renderChildren();
        }

        override void event(ref Event event)
        {
            if (ctrlIsDown || (!amIHovered && !m_parent.amIHovered && !m_parent.isAChildHovered))
                return;

            if (event.type == EventType.MOUSEWHEEL && m_orient == Orientation.VERTICAL)
            {
                gainedHover();
                m_lastScrollTime = timerMsecs;
                m_waitingForScrollDelay = true;

                m_current += -1 * m_scrollDelta * (event.get!MouseWheel.delta/120);

                // Check bounds
                if (m_current < m_range[0])
                    m_current = m_range[0];
                if (m_current > m_range[1])
                    m_current = m_range[1];

                if (m_orient == Orientation.VERTICAL)
                {
                    m_slidePos[1] = cast(int) (m_range[0] + ((m_current / cast(float)(m_range[1] - m_range[0])) *
                                              (m_slideLimit[1] - m_slideLimit[0])));
                }
                eventSignal.emit(this, WidgetEvent(Scroll(m_current)));
                needRender();
            }
        }

        // Drag along the widget's orientation, within the limits
        override void drag(int[2] pos, int[2] delta)
        {
            int index;

            if (m_orient == Orientation.VERTICAL)
                index = 1;
            else if (m_orient == Orientation.HORIZONTAL)
                index = 0;

            m_slidePos[index] += delta[index];
            if (m_slidePos[index] < m_slideLimit[0])
                m_slidePos[index] = m_slideLimit[0];
            if (m_slidePos[index] > m_slideLimit[1])
                m_slidePos[index] = m_slideLimit[1];

            m_current = cast(int) ((m_range[1]-m_range[0]) * ((m_slidePos[index] - m_slideLimit[0]) /
                                    cast(float)(m_slideLimit[1] - m_slideLimit[0])));

            eventSignal.emit(this, WidgetEvent(Scroll(m_current)));
        }

        // Grant drag requests if mouse is within the slider part
        override bool requestDrag(int[2] pos)
        {
            // Allow drag if inside slider
            int[2] absPos;
            absPos[0] = m_parent.screenPos().x + m_pos[0] + m_slidePos[0];
            absPos[1] = m_parent.screenPos().y + m_pos[1] + m_slidePos[1];
            if (isInside(absPos, m_slideDim, pos))
            {
                // Make sure we are visible, or at least fading in
                gainedHover();
                return true;
            }
            return false;
        }

        // Gained the mouse hover, start fading in
        override void gainedHover()
        {
            if (!m_hideWhenNotHovered || m_fadingIn)
                return;

            if (m_fadingOut)
            {
                m_fadingOut = false;
                removeTimer(10, &this.fadeTimer, true);
            }

            m_fadingIn = true;
            requestTimer(10, &this.fadeTimer, true);
        }

        // Lost the mouse hover, start fading out
        override void lostHover()
        {
            if (!m_hideWhenNotHovered || m_fadingOut)
                return;

            if (m_fadingIn)
            {
                m_fadingIn = false;
                removeTimer(10, &this.fadeTimer, true);
            }

            m_fadingOut = true;
            requestTimer(10, &this.fadeTimer, true);
        }

        // This is used for fade-in/fade-out
        void fadeTimer(long delay)
        {
            if (m_fadingIn)
            {
                m_alpha += m_fadeInc;

                m_color.a = m_backgroundAlphaMax * m_alpha;
                m_slideColor.a = m_slideAlphaMax * m_alpha;
                m_slideBorder.a = m_slideBorderAlphaMax * m_alpha;

                // Check if we have finished fading
                if (m_alpha >= 1)
                {
                    m_alpha = 1;
                    m_color.a = m_backgroundAlphaMax;
                    m_slideColor.a = m_slideAlphaMax;
                    m_slideBorder.a = m_slideBorderAlphaMax;
                    m_fadingIn = false;
                    removeTimer(10, &this.fadeTimer, true);
                }
            }
            else if (m_fadingOut)
            {
                m_alpha -= m_fadeInc;

                m_color.a = m_backgroundAlphaMax * m_alpha;
                m_slideColor.a = m_slideAlphaMax * m_alpha;
                m_slideBorder.a = m_slideBorderAlphaMax * m_alpha;

                // Check if we have finished fading
                if (m_alpha <= 0)
                {
                    m_alpha = 0;
                    m_color.a = 0;
                    m_slideColor.a = 0;
                    m_slideBorder.a = 0;
                    m_fadingOut = false;
                    removeTimer(10, &this.fadeTimer, true);
                }
            }

            m_refreshCache = true;
            needRender();
        }

    private:
        int[2] m_range;
        int m_current;
        float m_slideLength = 0.1;

        int[2] m_slideLimit;
        int[2] m_slidePos;
        int[2] m_slideDim;

        float m_slideAlphaMax = 0;
        float m_slideBorderAlphaMax = 0;
        float m_backgroundAlphaMax = 0;
        float m_alpha = 0;

        RGBA m_slideColor = {1,1,1,1};
        RGBA m_slideBorder = {0,0,0,1};

        Orientation m_orient;

        int m_scrollDelta = 1;
        long m_lastScrollTime = 0; // last time a scroll event was handled
        long m_postScrollFadeDelay = 2000; // msecs after a scroll event to start fading out
        bool m_waitingForScrollDelay = false;

        bool m_hideWhenNotHovered = false;
        bool m_fadingIn = false;
        bool m_fadingOut = false;
        float m_fadeInc = .05;
}


class WidgetTree : WidgetWindow
{
    package this(WidgetRoot root, Widget parent)
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
            bool scrollFade = true;
            int scrollCr = 0, scrollTh = 10; // corner radius and thickness

            fill(args, arg("gap", m_widgetGap),
                       arg("indent", m_widgetIndent),
                       arg("cliptoscrollbar", m_clipToScrollBar),
                       arg("scrollbackground", scrollBg),
                       arg("scrollforeground", scrollFg),
                       arg("scrollborder", scrollBd),
                       arg("scrollfade", scrollFade),
                       arg("scrollcornerradius", scrollCr),
                       arg("scrollthick", scrollTh));

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

            if (w != m_vScroll)
                pos[1] -= m_vScroll.current;
        }

        override void transformClip(Widget w, ref int[4] clipbox)
        {
            Widget.transformClip(this, clipbox);

            if (w != m_vScroll)
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
                !m_root.isHovered(m_vScroll))
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
            if (w.type != "WIDGETSCROLL" && m_clipToScrollBar)
                clip[2] -= m_vScroll.dim.x;

            if (m_parent)
                smallestBox(clip, m_parent.getChildClipBox(this));

            return clip;
        }

        void transitionTimer(long delay)
        {
            m_transitionCalls ++;
            if (m_transitioning)
            {
                updateTree();
            }
            else
            {
                m_transitionCalls = 0;
                removeTimer(10, &transitionTimer, true);
            }
        }


        override void render(Flag!"RenderChildren" recurse)
        {
            super.render(Flag!"RenderChildren".no);

            glTranslatef(0, -m_vScroll.current, 0);

            long maxFocus;
            foreach(child; m_children)
                if (child !is m_vScroll)
                    renderChild(child, maxFocus);

            glTranslatef(0, m_vScroll.current, 0);

            m_vScroll.preRender();
            m_vScroll.render(Flag!"RenderChildren".yes);
            m_vScroll.postRender();
        }

    private:

        void setVisibility(Node n)
        {
            n.shown = n.parent.expanded && n.parent.shown;
            n.widget.showing = n.shown;

            foreach(child; n.children)
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
            int xoffset = 10, yoffset = 10, width = m_dim.x;

            foreach(node; m_tree)
                updateTreeRecurse(node, xoffset, yoffset, width);

            m_vScroll.range = [0, yoffset];
            needRender();
        }

        void updateTreeRecurse(Node node, ref int xoffset, ref int yoffset, ref int width)
        {
            xoffset += m_widgetIndent;
            width = node.widget.dim.x + xoffset;
            node.widget.setPos(xoffset, yoffset);
            node.widget.updateScreenInfo();

            // See if widget is still visible inside the clipping area
            node.widget.showing = true && node.shown;

            if (node.shown)
            {
                yoffset += node.widget.dim.y + m_widgetGap;

                foreach(child; node.children)
                    updateTreeRecurse(child, xoffset, yoffset, width);
            }

            xoffset -= m_widgetIndent;
        }

        class Node
        {
                this(Widget w)
                {
                    widget = w;
                }

                Widget widget = null;
                Node parent = null;
                Node[] children = null;

                bool shown = false;
                bool expanded = false;
        }

        Node[] m_tree;

        WidgetScroll m_vScroll;

        bool m_clipToScrollBar = true;
        bool m_transitioning = false;
        int m_transitionCalls = 0;
        int m_transitionInc = 1;
        int m_widgetGap = 5;
        int m_widgetIndent = 20;
}
























