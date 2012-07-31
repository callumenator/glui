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
    glui.widget.text;


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

    if (w.container) // Allow the widgets container to transform the clip box
        clip = w.container.transformClip(w);

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

    if (w1.container) // Allow widget container to transform geometry
    {
        p1 = w1.container.transformScreenPos(w1);
        d1 = w1.container.transformDim(w1);
    }

    auto p2 = w2.screenPos;
    auto d2 = w2.dim;

    if (w2.container) // Allow widget container to transform geometry
    {
        p2 = w2.container.transformScreenPos(w2);
        d2 = w2.container.transformDim(w2);
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


/**
* Constrain a point to lie within the given box (x, y, w, h). GUI coords
*/
void constrainPoint(ref int[2] pos, int[4] box)
{
    if (pos[0] < box[0]) pos[0] = box[0];
    if (pos[0] > box[0] + box[2]) pos[0] = box[0] + box[2];
    if (pos[1] < box[1]) pos[1] = box[1];
    if (pos[1] > box[1] + box[3]) pos[1] = box[1] + box[3];
}


// Allow widgets to take a list of names params
KeyVal arg(T)(string k, T t)
{
    return KeyVal(k, t);
}


// The key/name backend
struct KeyVal
{
    this(T)(string k, T v)
    {
        key = k;
        val = v;
    }

    string key;
    Variant val;

    // Get the value from the variant
    T get(T)(string widgetname)
    {
        if (val.convertsTo!T)
            return val.get!T;
        else
            assert(false, "Incorrect argument type for " ~
                    widgetname ~ " : " ~ key ~ "\n" ~
                    "expected " ~ T.stringof ~ ", got " ~
                    (val.type()).to!string);
    }
}


// Unpack a tuple of mixed KeyVals/KeyVal[]'s
KeyVal[] unpack(T...)(T args)
{
    KeyVal[] o;

    foreach(arg; args)
    {
        static if (typeof(arg).stringof == "KeyVal")
            o ~= arg;
        else if (typeof(arg).stringof == "KeyVal[]")
        {
            foreach(arg_; arg)
            {
                o ~= arg_;
            }
        }
    }
    return o;
}


/**
* Anything which contains widgets must implement these functions
*/
interface WidgetContainer
{
    // Transforms on a widget's geometry
    int[2] transformScreenPos(Widget w);
    int[2] transformPos(Widget w);
    int[2] transformDim(Widget w);
    int[4] transformClip(Widget w);
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

        void set(KeyVal...)(KeyVal args)
        {
            foreach(arg; unpack(args))
            {
                switch(arg.key.toLower)
                {
                    case "pos":
                    case "position":
                        m_pos = arg.get!(int[])(m_type);
                        break;

                    case "dim":
                    case "dimension":
                    case "dimensions":
                        m_dim = arg.get!(int[])(m_type);
                        break;

                    case "cornerradius":
                        m_cornerRadius = arg.get!int(m_type);
                        break;

                    case "showing":
                        m_showing = arg.get!bool(m_type);
                        break;

                    case "clipped":
                        m_clipped = arg.get!bool(m_type);
                        break;

                    case "blocking":
                        m_blocking = arg.get!bool(m_type);
                        break;

                    case "candrag":
                        m_canDrag = arg.get!bool(m_type);
                        break;

                    case "canresize":
                        m_canResize = arg.get!bool(m_type);
                        break;

                    default:
                }
            }
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
        @property bool drawnByRoot() const { return m_drawnByRoot; }
        @property bool drawn() const { return m_drawn; }
        @property WidgetRoot root() { return m_root; }
        @property WidgetContainer container () { return m_container; }
        @property Widget parent() { return m_parent; }
        @property Widget[] children() { return m_children; }
        long lastFocused() const { return m_lastFocused; }
        @property string type() const { return m_type; }
        @property int cornerRadius() const { return m_cornerRadius; }

        // Set
        @property void canDrag(bool v) { m_canDrag = v; }
        @property void canResize(bool v) { m_canResize = v; }
        @property void clipped(bool v) { m_clipped = v; }
        @property void focusable(bool v) { m_focusable = v; }
        @property void drawnByRoot(bool v) { m_drawnByRoot = v; }
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
            setContainer(newParent.container);
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

        // Render this widget
        void render() {}

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
            // By default, widgets are not draggable
            return m_canDrag;
        }

        // Override this to provide customized drag logic
        void drag(int[2] pos, int[2] delta)
        {
            // By default, if a widget allows dragging, it drags in both x and y, unconstrained
            m_pos[] += delta[];

            /**
            * Note that root makes sure the geometryChanged method is called, and
            * fires the drag event signal, so be aware of this if overriding this
            * drag method for custom logic.
            */
        }

        // Override these to control resizing of your widget
        bool requestResize(int[2] pos)
        {
            // By default, widgets are not resizable
            return m_canResize;
        }

        // Need to override this to create resizing ability
        void resize(int[2] pos, int[2] delta) {}


        /**
        * Recursively find the focused widget. Return true if a focus was found,
        * and finalFocus will be the reference to the focused widget.
        */
        bool focus(int[2] pos, ref Widget finalFocus)
        {
            // If click was inside my bounds, list me as focused
            if (m_visible && this.isInside(pos) && m_focusable)
            {
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

            m_drawn = m_parent.drawnByRoot && m_drawnByRoot;

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
            /++
            return [m_screenPos.x - 1,
                    m_root.window.windowState.ypix - m_screenPos.y - m_dim.y,
                    m_dim.x + 1,
                    m_dim.y + 1];
            ++/
            return [m_screenPos.x - 1,
                    m_screenPos.y - 1,
                    m_dim.x + 1,
                    m_dim.y + 1];
        }

        // Override this to set a custom clip box for the widget's children
        int[4] getChildClipBox(Widget w)
        {
            if (m_cornerRadius == 0)
            {
                return getClipBox();
            }
            else
            {
                auto clip = getClipBox();
                clip[0] += m_cornerRadius;
                clip[1] += m_cornerRadius;
                clip[2] -= 2*m_cornerRadius;
                clip[3] -= 2*m_cornerRadius;
                return clip;
            }
        }

        // Set a new manager for this widget
        void setContainer(WidgetContainer w)
        {
            m_container = w;
            foreach(child; m_children)
                child.setContainer(w);
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
        bool m_drawnByRoot = true; // whether or not root _should_ draw this widget
        bool m_drawn = true; // whether or not root _will_ draw this widget
        bool m_canDrag = false;
        bool m_canResize = false;
        bool m_blocking = false; // blocking widgets don't lose focus
        long m_lastFocused = 0;
        int m_cornerRadius = 0;

        WidgetContainer m_container = null; // A non-null container will transform clicks etc.

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
            wnd.event.connect(&this.injectEvent, PRIORITY.NORMAL);
            m_eventTimer.start();
            setViewport();
        }

        // Poll for events, and put the current thread to sleep if needed
        void poll()
        {
            m_window.poll();

            if (m_needRender)
                render();

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
        void render()
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
            glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
            glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);

            /**
            * We need to render in reverse order (widgets are sorted
            * by increasing 'effective' z depth)
            */
            foreach(widget; retro(m_widgetList))
            {
                /**
                * TODO: sort widgets so that invisible widgets are at the bottom of the list,
                * and the first invisible widget can terminate this loop
                */
                if (!widget.visible)
                    continue;

                // Translate to parents coord, and set clip box
                glLoadIdentity();

                if (!widget.drawn && widget.container !is null)
                {
                    debug
                    {

                        // Draw a debug outline
                        auto _clip = widget.container.transformClip(widget);
                        auto _scrPos = widget.container.transformScreenPos(widget);
                        auto _dim = widget.container.transformDim(widget);

                        // Outline first
                        glScissor(0, 0, m_dim.x, m_dim.y);
                        glColor4f(1,.4,.1,1);
                        glBegin(GL_LINE_LOOP);
                        glVertex2f(_scrPos.x, _scrPos.y);
                        glVertex2f(_scrPos.x + _dim.x, _scrPos.y);
                        glVertex2f(_scrPos.x + _dim.x, _scrPos.y + _dim.y);
                        glVertex2f(_scrPos.x, _scrPos.y + _dim.y);
                        glEnd();

                        // Then clip window
                        glColor4f(0,1,.6,1);
                        glBegin(GL_LINE_LOOP);
                        glVertex2f(_clip[0], _clip[1]);
                        glVertex2f(_clip[0] + _clip[2], _clip[1]);
                        glVertex2f(_clip[0] + _clip[2], _clip[1] + _clip[3]);
                        glVertex2f(_clip[0], _clip[1] + _clip[3]);
                        glEnd();
                    }
                }
                else
                {
                    // Transform the clip box to screen coords
                    auto clip = widget.clip;
                    clipboxToScreen(clip);

                    glScissor(clip[0], clip[1], clip[2], clip[3]);
                    glTranslatef(widget.parent.screenPos.x, widget.parent.screenPos.y, 0);

                    // Draw the widget
                    widget.render();
                }
            }

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
                    render();
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
                    break;
                }
                case MOUSECLICK:
                {
                    auto pos = event.get!MouseClick.pos;

                    // Mouseclick could potentially change the focus, so check
                    checkFocus(pos);

                    // And check for dragging
                    if (m_focused !is null)
                    {
                        if (m_focused.isInside(pos))
                            m_dragging = m_focused.requestDrag(pos);
                    }

                    break;
                }
                case MOUSERELEASE:
                {
                    m_dragging = false;
                    m_resizing = false;
                }

                default:
            }

            // Sort the widget list.. prob dont need this every event!
            sortWidgetList();

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
            foreach(index, widget; m_widgetList) // note that the list is already sorted
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
                if (m_children[index].parent == this && m_children[index].visible &&
                    m_children[index].drawn)
                {
                    changeFocus(m_children[index]);
                    break;
                }

            }
        }

        // Give the focus to the new widget (use force when focusing non-root-managed widgets)
        void changeFocus(Widget newFocus, Flag!"force" force = Flag!"force".no)
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
            if (m_focused is null)
                return;

            if (m_dragging && m_window.mouseState.left == MouseState.STATE.PRESSED)
            {
                // Only keep dragging if mouse is within our window
                auto xpos = m_window.mouseState.xpos;
                auto ypos = m_window.mouseState.ypos;
                if (xpos >= 0 || xpos <= m_window.windowState.xpix ||
                    ypos >= 0 || ypos <= m_window.windowState.ypix )
                {
                    auto pos = event.get!MouseMove.pos;
                    auto delta = event.get!MouseMove.delta;
                    m_focused.drag(pos, delta);

                    // Flag the change in geometry
                    m_focused.geometryChanged(Widget.GeometryChangeFlag.POSITION);

                    // Signal event
                    eventSignal.emit(m_focused, WidgetEvent(Drag(pos, delta)));

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

        // Sort the widget list by scene depth
        void sortWidgetList()
        {
            sort!("a.lastFocused() > b.lastFocused()")(m_widgetList);
        }

        // Widgets can check if they have focus
        const bool isFocused(const Widget w) const { return m_focused is w; }

        // Widgets can check if one of their children has focus
        const bool isAChildFocused(const Widget w) const { return w.isAChildFocused; }

        // Widgets can check if they are being dragged
        const bool isDragging(const Widget w) const { return ( (m_focused is w) && m_dragging); }

        // Widgets can check if they are being resized
        const bool isResizing(const Widget w) const { return ( (m_focused is w) && m_resizing); }

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
        @property long timerMsecs() const { return m_eventTimer.peek().msecs; }

        // Get the platform window we are running in
        @property Window window() { return m_window; }

        // Return true if CTRL key is down
        @property bool ctrlIsDown() const
        {
            return (m_window.keyState.keys[KEY.KC_CTRL_LEFT] ||
                    m_window.keyState.keys[KEY.KC_CTRL_RIGHT]);
        }

        // Return true if SHIFT key is down
        @property bool shiftIsDown() const
        {
            return (m_window.keyState.keys[KEY.KC_SHIFT_LEFT] ||
                    m_window.keyState.keys[KEY.KC_SHIFT_RIGHT]);
        }

        // Flag that a widget needs to be rendered
        void needRender()
        {
            m_needRender = true;
        }

        // Convert a clip box (which is given in the upside down gui coords) to screen coords
        void clipboxToScreen(ref int[4] box)
        {
            box[1] = m_window.windowState.ypix - (box[1] + box[3]);
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

        void set(T...)(T args)
        {
            super.set(args);
            m_type = "WIDGETWINDOW";
            m_cacheId = glGenLists(1);

            foreach(arg; unpack(args))
            {
                switch(arg.key.toLower)
                {
                    case "bgcolor":
                    case "background":
                        setColor = arg.get!RGBA(m_type);
                        break;

                    case "border":
                    case "bordercolor":
                        setBorderColor = arg.get!RGBA(m_type);
                        break;

                    case "texture":
                        setTexture = arg.get!GLuint(m_type);
                        break;

                    default:
                }
            }
        }



        override void geometryChanged(Widget.GeometryChangeFlag flag)
        {
            if (flag & Widget.GeometryChangeFlag.DIMENSION)
                m_refreshCache = true;
        }

        override void render()
        {
            // r is used in a mixin, so don't change its name (this is not optimal, I know...)
            int r = min(m_cornerRadius, m_dim.x/2, m_dim.y/2);

            glTranslatef(m_pos.x, m_pos.y, 0);

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
                    glPushAttrib(GL_ENABLE_BIT | GL_TEXTURE_BIT);
                    glEnable(GL_TEXTURE_2D);
                    glBindTexture(GL_TEXTURE_2D, m_texture);

                    glColor4fv(m_color.ptr);

                    if (m_cornerRadius == 0) // textured square box
                    {
                        glBegin(GL_POLYGON);
                        mixin(squareBox(true));
                        glEnd();
                        glBindTexture(GL_TEXTURE_2D, 0);
                        glPopAttrib();

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
                        glPopAttrib();

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

            glTranslatef(-m_pos.x, -m_pos.y, 0);
        }

    package:

        RGBA m_color = {0,0,0,1};
        RGBA m_borderColor = {0,0,0,0};
        GLuint m_texture = 0;
        GLuint m_cacheId = 0; // glDisplayList for caching
        int m_cachedRadius = 0; // radius when list was cached
        bool m_refreshCache = true;
}



class WidgetPanWindow : WidgetWindow, WidgetContainer
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:

        void set(KeyVals...)(KeyVals args)
        {
            super.set(args);
            m_canDrag = true;
        }

        override void drag(int[2] pos, int[2] delta)
        {
            m_translation[] += delta[];
        }

        override void addChild(Widget child)
        {
            m_children ~= child;
            child.drawnByRoot = false;
            child.setContainer(this);
        }

        override void render()
        {
            super.render();

            foreach(child; m_children)
                renderChildren(child);
        }

        override void event(ref Event event)
        {
            if (!amIHovered && !isAChildHovered) return;

            if (event.type == EventType.MOUSEWHEEL)
            {
                m_zoom += event.get!MouseWheel.delta/1200.;
                needRender();
            }

        }

        int[2] transformScreenPos(Widget w)
        {
            return [w.screenPos.x + m_translation.x,
                    w.screenPos.y + m_translation.y];
        }

        int[2] transformPos(Widget w)
        {
            return [w.pos.x + m_translation.x,
                    w.pos.y + m_translation.y];
        }

        int[2] transformDim(Widget w)
        {
            return [cast(int)(w.dim.x * m_zoom),
                    cast(int)(w.dim.y * m_zoom)];
        }

        int[4] transformClip(Widget w)
        {
            return [w.clip[0] + m_translation[0],
                    w.clip[1] + m_translation[1],
                    cast(int)(w.clip[2] * m_zoom),
                    cast(int)(w.clip[3] * m_zoom)];
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

        void renderChildren(Widget w)
        {
            if (!overlap(w, this))
                return;

            glLoadIdentity();

            auto clip = transformClip(w);
            glTranslatef(w.parent.screenPos.x + m_translation[0],
                         w.parent.screenPos.y + m_translation[1], 0);

            // Account for change in scale of starting position
            glTranslatef(-w.pos.x*(m_zoom-1), -w.pos.y*(m_zoom-1), 0);

            glScalef(m_zoom, m_zoom, 1);
            smallestBox(clip, getChildClipBox(w));
            m_root.clipboxToScreen(clip);
            glScissor(clip[0], clip[1], clip[2], clip[3]);

            w.render();
            foreach(c; w.children)
                renderChildren(c);
        }

        int[2] m_translation;
        float m_zoom = 1;
}

enum Orientation
{
    VERTICAL, HORIZONTAL
}

class WidgetScroll : WidgetWindow
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:

        void set(KeyVals...)(KeyVals args)
        {
            super.set(args);
            m_type = "WIDGETSCROLL";

            int smin, smax;
            foreach(arg; unpack(args))
            {
                switch(arg.key.toLower)
                {
                    case "min":
                    case "slidermin":
                        smin = arg.get!int(m_type);
                        break;

                    case "max":
                    case "slidermax":
                        smax = arg.get!int(m_type);
                        break;

                    case "range":
                        auto rnge = arg.get!(int[])(m_type);
                        smin = rnge[0];
                        smax = rnge[1];
                        break;

                    case "orientation":
                        m_orient = arg.get!Orientation(m_type);
                        break;

                    case "fade":
                        m_hideWhenNotHovered = arg.get!bool(m_type);
                        break;

                    case "slidercolor":
                        m_slideColor = arg.get!RGBA(m_type);
                        break;

                    case "sliderborder":
                        m_slideBorder = arg.get!RGBA(m_type);
                        break;

                    case "sliderlength":
                        m_slideLength = arg.get!float(m_type);
                        break;

                    default:
                }
            }

            if (smin > smax)
                smin = smax = 0;

            m_range = [smin, smax];

            m_backgroundAlphaMax = m_color.a;
            m_slideAlphaMax = m_slideColor.a;
            m_slideBorderAlphaMax = m_slideBorder.a;

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
                m_current = v;
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
                m_slidePos = [m_pos.x + (m_dim.x - sw)/2, cast(int)(sf*m_dim.y)];
                m_slideDim = [sw, slen];
                m_slideLimit = [0, m_dim.y - slen];
            }
            else if (m_orient == Orientation.HORIZONTAL)
            {
                auto slen = cast(int)(m_dim.x * m_slideLength);
                int sw = cast(int)(m_dim.y*0.8);
                m_slidePos = [cast(int)(sf*m_dim.x), m_pos.y + (m_dim.y - sw)/2];
                m_slideDim = [slen, sw];
                m_slideLimit = [0, m_dim.x - slen];
            }

            m_refreshCache = true;
            needRender();

        }
        // Render, call super then render the slider and buttons
        override void render()
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

            super.render();

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
        }

        override void event(ref Event event)
        {
            if (!amIHovered && !m_parent.amIHovered && !m_parent.isAChildHovered) return;

            if (event.type == EventType.MOUSEWHEEL && m_orient == Orientation.VERTICAL)
            {
                gainedHover();
                m_lastScrollTime = timerMsecs;
                m_waitingForScrollDelay = true;

                int[2] pos = event.get!MouseWheel.pos;
                int[2] delta = [0,-event.get!MouseWheel.delta/120];
                drag(pos, delta);
            }
        }

        // Drag along the widget's orientation, within the limits
        override void drag(int[2] pos, int[2] delta)
        {
            if (m_orient == Orientation.VERTICAL)
            {
                m_slidePos[1] += delta[1];
                if (m_slidePos[1] < m_slideLimit[0])
                    m_slidePos[1] = m_slideLimit[0];
                if (m_slidePos[1] > m_slideLimit[1])
                    m_slidePos[1] = m_slideLimit[1];

                m_current = cast(int) ((m_range[1]-m_range[0]) * ((m_slidePos[1] - m_slideLimit[0]) /
                                        cast(float)(m_slideLimit[1] - m_slideLimit[0])));
            }
            else if (m_orient == Orientation.HORIZONTAL)
            {
                m_slidePos[0] += delta[0];
                if (m_slidePos[0] < m_slideLimit[0])
                    m_slidePos[0] = m_slideLimit[0];
                if (m_slidePos[0] > m_slideLimit[1])
                    m_slidePos[0] = m_slideLimit[1];

                m_current = cast(int) ((m_range[1]-m_range[0]) * ((m_slidePos[0] - m_slideLimit[0]) /
                                        cast(float)(m_slideLimit[1] - m_slideLimit[0])));
            }

            eventSignal.emit(this, WidgetEvent(Scroll(m_current)));
        }

        // Grant drag requests if mouse is within the slider part
        override bool requestDrag(int[2] pos)
        {
            // Allow drag if inside slider
            int[2] absPos = m_parent.screenPos[] + m_slidePos[];
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

        long m_lastScrollTime = 0; // last time a scroll event was handled
        long m_postScrollFadeDelay = 2000; // msecs after a scroll event to start fading out
        bool m_waitingForScrollDelay = false;

        bool m_hideWhenNotHovered = false;
        bool m_fadingIn = false;
        bool m_fadingOut = false;
        float m_fadeInc = .05;
}


class WidgetTree : WidgetWindow, WidgetContainer
{
    package this(WidgetRoot root, Widget parent)
    {
        super(root, parent);
    }

    public:

        void set(KeyVal...)(KeyVal args)
        {
            super.set(args);
            m_type = "WIDGETTREE";

            RGBA scrollBg = RGBA(0,0,0,1);
            RGBA scrollFg = RGBA(1,1,1,1);
            RGBA scrollBd = RGBA(0,0,0,1);
            bool scrollFade = true;
            int scrollCr = 0, scrollTh = 0; // corner radius and thickness
            foreach(arg; unpack(args))
            {
                switch(arg.key.toLower)
                {
                    case "gap":
                        m_widgetGap = arg.get!int(m_type);
                        break;

                    case "indent":
                        m_widgetIndent = arg.get!int(m_type);
                        break;

                    case "cliptoscrollbar":
                        m_clipToScrollBar = arg.get!bool(m_type);
                        break;

                    case "scrollbackground":
                        scrollBg = arg.get!RGBA(m_type);
                        break;

                    case "scrollforeground":
                        scrollFg = arg.get!RGBA(m_type);
                        break;

                    case "scrollborder":
                        scrollBd = arg.get!RGBA(m_type);
                        break;

                    case "scrollfade":
                        scrollFade = arg.get!bool(m_type);
                        break;

                    case "scrollcornerradius":
                        scrollCr = arg.get!int(m_type);
                        break;

                    case "scrollthick":
                    case "scrollthickness":
                        scrollTh = arg.get!int(m_type);
                        break;

                    default:
                }
            }

            m_vScroll = m_root.create!WidgetScroll(this,
                                    arg("dim", [scrollTh, m_dim.y - scrollTh]),
                                    arg("range", [0,1000]),
                                    arg("fade", scrollFade),
                                    arg("slidercolor", scrollFg),
                                    arg("sliderborder", scrollBd),
                                    arg("background", scrollBg),
                                    arg("cornerRadius", scrollCr),
                                    arg("orientation", Orientation.VERTICAL));

        }

        void add(Widget wparent,
                 Widget widget,
                 Flag!"NoUpdate" noUpdate = Flag!"NoUpdate".no)
        {
            widget.setParent(this);
            widget.setContainer(this);
            widget.drawnByRoot = false;
            widget.clipped = false;

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

        int[2] transformScreenPos(Widget w)
        {
            return [w.screenPos.x,
                    w.screenPos.y - m_vScroll.current];
        }

        int[2] transformPos(Widget w)
        {
            return [w.pos.x,
                    w.pos.y - m_vScroll.current];
        }

        int[2] transformDim(Widget w)
        {
            return w.dim;
        }

        int[4] transformClip(Widget w)
        {
            return [w.clip[0],
                    w.clip[1] - m_vScroll.current,
                    w.clip[2], w.clip[3]];
        }

        void update()
        {
            updateTree();
        }

        override void geometryChanged(Widget.GeometryChangeFlag flag)
        {
            super.geometryChanged(flag);

            if (flag & Widget.GeometryChangeFlag.DIMENSION)
            {
                m_vScroll.setDim(m_vScroll.dim.x, m_dim.y - m_vScroll.dim.x);
                m_vScroll.setPos(m_dim.x - m_vScroll.dim.x, 0);
            }
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
            if (w.type == "WIDGETSCROLL" || !m_clipToScrollBar)
            {
                return getClipBox();
            }
            else
            {
                auto clip = getClipBox();
                return [clip[0], clip[1], clip[2] - m_vScroll.dim.x, clip[3]];
            }
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


        override void render()
        {
            super.render();

            long maxFocus;
            foreach(child; m_children)
                if (child !is m_vScroll)
                    renderChildren(child, maxFocus);
        }

    private:

        void setVisibility(Node n)
        {
            n.shown = n.parent.expanded && n.parent.shown;
            n.widget.showing = n.shown;

            foreach(child; n.children)
                setVisibility(child);
        }

        void renderChildren(Widget w, ref long maxFocus)
        {
            if (!w.visible || !overlap(w, this))
                return;

            if (w.lastFocused > maxFocus)
                maxFocus = w.lastFocused;

            glLoadIdentity();

            auto clip = w.clip;
            clip[1] -= m_vScroll.current;
            smallestBox(clip, this.getChildClipBox(w));
            m_root.clipboxToScreen(clip);
            glScissor(clip[0], clip[1], clip[2], clip[3]);

            glTranslatef(w.parent.screenPos.x,
                         w.parent.screenPos.y - m_vScroll.current, 0);

            w.render();
            foreach(c; w.children)
                renderChildren(c, maxFocus);

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
























