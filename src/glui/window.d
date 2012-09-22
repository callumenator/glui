// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: Module for creating windows on Linux/Windows
*/
module glui.window;

import
    std.conv,
    std.math,
    std.stdio,
    std.string,
    std.datetime,
    std.regex;

public import
    std.typecons;

import
    derelict.opengl.gl,
    derelict.opengl.wgl,
    derelict.opengl.gltypes,
    derelict.opengl.exttypes,
    derelict.opengl.extfuncs;

import
    glui.event,
    glui.osgl;



// Structure holding the state of a window.
struct WindowState
{
    int xpos = 0; // Window x-position (pixels).
    int ypos = 0; // Window y-position (pixels).
    uint xpix = 600; // Window x-size (pixels).
    uint ypix = 600; // Window y-size (pixels).

    this(in int ixpos, in int iypos, in uint ixpix, in uint iypix)
    {
        xpos = ixpos;
        ypos = iypos;
        xpix = ixpix;
        ypix = iypix;
    }
}


// The window class, which abstracts away the OS dependendent stuff.
abstract class Window
{
    private:

        string m_windowName = "";
        string m_title = "";
        static string m_driver; // The name of the underlying graphics driver will be stored here.
        bool m_softwareDriver = false; // Set to true if we think we are dealing with a software renderer (like Mesa)
        bool m_fullscreen = false;
        bool m_visible = true; // True if the window is visible.
        bool m_destroyed = false; // True if the window has been destroyed.

        // Store the current state of the keyboard, mouse, and window
        KeyState m_keyState;
        MouseState m_mouseState;
        WindowState m_windowState;

        static VideoProps m_videoProps = VideoProps(); // The video properties associated with the shared GL context.
        static bool m_haveContext = false; // Will be set to true once a context has been created.

        static Window[string] m_windows; // Store a list of all windows.
        static Window m_null = null; // Store a private null window.

        // Store the window associated with the current openGL context.
        static Window m_current = null;

    public:

        // Getters/Setters.
        @property const(KeyState)* keyState() const { return &m_keyState; }
        @property const(MouseState)* mouseState() const { return &m_mouseState; }
        @property const(WindowState)* windowState() const { return &m_windowState; }
        static const(Window[string]) windows() { return m_windows; }

        static VideoProps videoProps() { return m_videoProps; }
        static void videoProps(VideoProps p)
        {
            // Can only set new video properties if there is no render context.
            if (!m_haveContext)
                m_videoProps = p;
        }

        string driver() { return m_driver; }
        bool softwareDriver() { return m_softwareDriver; }
        string windowName() const { return m_windowName; }
        bool visible() { return m_visible; }

         // Event signal.
        PrioritySignal!(Event) event;

        // Create a window and OpenGL context.
        int create(in WindowState ws, in bool show);

        // Destroy the window.
        void destroy();

        // Drive window event processing.
        void poll();

        // Swap front and back drawing buffers.
        void swapBuffers();

        // Make the context associated with this window current.
        int makeCurrent();

        // Set the window caption/title.
        void setTitle(in string title);

        // Set the cursor position.
        void setCursorPos(in int x, in int y);

        // Hide/show the cursor.
        void showCursor(in bool show);

        /**
        * Static opCall for getting a Window from a windowName. If the windowName is
        * not found, and create = true, a new Window with that name will be created.
        * If the window is not found, and create = false, the null window will be returned.
        * Params:
        * name = handle to the window.
        * create = set to true to create a new window, if one with the given name was not found.
        * ws = create a new Window if the name is not found
        * show = if we need to create the Window, show or hide based on this flag
        */
        static opCall(in string name,
                      in WindowState ws = WindowState(),
                      in Flag!"Create" create = Flag!"Create".yes,
                      in Flag!"Show" show = Flag!"Show".yes,                      )
        {
            auto ptr = (name in m_windows);
            if (ptr is null) // Window was not found.
            {
                if (create)
                {
                    Window win = null;

                    version(Windows)
                    {
                        string className = "d_window_" ~ to!string(m_windows.length+1);
                        win = new Win32Window(name, className, m_videoProps);
                    }
                    version(Posix)
                    {
                        win = new NixWindow(name, m_videoProps);
                    }

                    // TODO : test for null window here
                    win.create(ws, show);
                    m_windows[name] = win;
                    return win;

                }
                else
                {
                    // If there is no null window stored yet, create one.
                    if (m_null is null)
                        m_null = new NullWindow;

                    // Return the null window so window ops will be quietly ignored.
                    return m_null;
                }
            }
            else
            {   // The window was found.
                return (*ptr);
            }
        }


        // Static opCall for getting the current window.
        static opCall()
        {
            if (m_current is null)
            {
                if (m_null is null)
                {
                    m_null = new NullWindow;
                    m_current = m_null;
                }
            }
            return m_current;
        }

        // Make the window with the given name the current window.
        static makeCurrent(in string name)
        {
            auto ptr = (name in m_windows);
            if (ptr !is null)
            {
                if (!(*ptr).makeCurrent())
                    m_current = (*ptr);
            }
        }

        // Windows that have been closed should call this to be removed from the window list.
        void notifyDestroy(in string name)
        {
            auto ptr = (name in m_windows);
            if (ptr !is null)
            {
                m_windows.remove(name);
            }
        }
}


/**
* The null window is an empty window, which does nothing, but lets the static
* opCall to Window() succeed even if a window is requested that is not available.
*/
class NullWindow : Window
{
    override int create(in WindowState ws, in bool show)
    {  return 0;  }

    override void destroy() {}
    override void poll() {}
    override void swapBuffers() {}
    override int makeCurrent() { return 0; }
    override void setTitle(in string title) {}
    override void setCursorPos(in int x, in int y) {}
    override void showCursor(in bool show) {}
}



version(Windows)
{
    //---------------------------------//
    import win32.windef;
    import win32.winuser;
    import win32.wingdi;
    import win32.winbase;
    pragma(lib, "gdi32.lib");
    //---------------------------------//


    // Win32 Window.
    class Win32Window : Window
    {

    private:

        HWND m_hwnd = null; // Window handle.
        HDC m_hdc = null; // Window device context.
        string m_windowClass = "";

        static HKL m_layout; // Keyboard layout, used for getting ASCII form scancode
        static HGLRC m_glrc = null; // OpenGL render context, static to share amongst windows
        static int m_pixelFormat = -1; // Window pixel format, static to share amongst windows

    public:

        // List of handles handled, used to route wndProc calls
        static Win32Window[HWND] m_handles;

        // Getters
        HWND hwnd() { return m_hwnd; } // ditto
        HDC hdc() { return m_hdc; } // ditto

        // On creation, load OpenGL and create a context if we don't already have one
        this(in string windowName,
             in string windowClass,
             VideoProps props = VideoProps())
        {
            m_keyState.keys.length = KEY.max + 1;
            m_windowName = windowName;
            m_windowClass = windowClass;
            m_layout = GetKeyboardLayout(0);

            // Crate an openGL context to share among windows, if not already created
            if (m_glrc is null && m_haveContext == false)
            {
                DerelictGL.load();
                m_glrc = createGLContext(props, m_pixelFormat);
                m_videoProps = props; // props may have changed, depending on what is available
                m_haveContext = true; // TODO : error on null context

                // Query the underlying driver name.
                m_driver = to!string(glGetString(GL_RENDERER));
            }
        }

        // Create the window.
        override int create(in WindowState ws,
                            in bool show)
        {
            m_windowState = ws;
            m_visible = show;

            if (m_glrc is null)
            {
                writeln("Win32Window: No GL context. Failed.");
                return -1;
            }

            if (m_pixelFormat == -1)
            {
                writeln("Win32Window: No pixel format. Failed.");
                return -1;
            }

            createWindow(m_hwnd, m_hdc, m_windowClass, m_windowState, m_visible, m_pixelFormat);
            m_handles[m_hwnd] = this;
            return 0;
        }


        // Destroy the window.
        override void destroy()
        {
            if (!m_destroyed)
            {
                m_destroyed = true;

                if (derelict.opengl.wgl.wglGetCurrentDC() is m_hdc)
                    derelict.opengl.wgl.wglMakeCurrent(null, null);

                destroyWindow(m_hwnd, m_hdc);
                m_handles.remove(m_hdc);
                notifyDestroy(m_windowName);
            }
        }

        // Swap the buffers.
        override void swapBuffers()
        {
            SwapBuffers(m_hdc);
            Sleep(0);
        }

        // Make window current with the GL context.
        override int makeCurrent()
        {
            if (m_hdc !is null && m_glrc !is null)
            {
                derelict.opengl.wgl.wglMakeCurrent(m_hdc, m_glrc);
                return 0;
            }
            return -1;
        }

        // Poll for events.
        override void poll()
        {
            //writeln(m_keyState.keys[KEY.KC_BRACELEFT]);

            MSG msg;
            while (PeekMessageA(&msg, null, 0, 0, PM_REMOVE))
            {
                TranslateMessage(&msg);
                DispatchMessageA(&msg);
            }


            if (m_keyState.keysDown != 0)
                event.emit(Event(KeyHold(KEY.KC_NULL)));

            //if (m_mouseState.buttonsDown != 0)
                //mouseEvent.emit(EVENT_TYPE.BTN_HELD, &m_mouseState);

        }

        // Set the window title.
        override void setTitle(in string title)
        {
            SetWindowText(m_hwnd, cast(char*)(title~"\0"));
        }

        // Set the cursor position.
        override void setCursorPos(in int x,
                                   in int y)
        {
            SetCursorPos(x,y);
        }

        // Show/hide the cursor.
        override void showCursor(in bool show)
        {
            ShowCursor(show);
        }


    private:

        KEY[] downWithShift;

        KEY interpretKey(WPARAM wParam)
        {
            static ubyte state[256];

            if (GetKeyboardState(state.ptr)==FALSE)
                return KEY.KC_NULL;

            ushort ascii = 0;
            uint scode = MapVirtualKeyEx(wParam, 0, m_layout);
            uint vk = MapVirtualKeyEx(scode, 3, m_layout);
            ToAsciiEx(vk, scode, state.ptr, &ascii, 0, m_layout);

            /**
            * The CTRL key pressed can make ascii == 0, even when it should
            * return an actual ascii value (like CTRL + TAB).
            * The following is an ugly kludge to fix this.
            */
            if ((m_keyState.keys[KEY.KC_CTRL_LEFT] ||
                 m_keyState.keys[KEY.KC_CTRL_RIGHT]) &&
                vk < 127)
            {
                if (vk >= 65 && vk <= 122)
                    ascii = cast(ushort) (vk + 32);
                else
                    ascii = cast(ushort)vk;
            }

            if (ascii != 0)
                return cast(KEY)ascii;
            else
                return cast(KEY)(vk + nonAsciiOffset);
        }

        // Handle events.
        int windowProc(HWND hwnd,
                       uint message,
                       WPARAM wParam,
                       LPARAM lParam)
        {

            switch (message)
            {
                case WM_PAINT:
                {
                    event.emit(Event(WindowPaint()));
                    goto default;
                }

                case WM_KILLFOCUS:
                {
                    m_keyState.keysDown = 0;
                    m_mouseState.buttonsDown = 0;
                    break;
                }

                case WM_KEYDOWN:
                {
                    auto sym = interpretKey(wParam);

                    if (cast(uint) sym > KEY.max)
                        break;

                    if (m_keyState.keys[sym] != KeyState.STATE.PRESSED)
                    {
                        if (sym != KEY.KC_SHIFT_LEFT &&
                            sym != KEY.KC_SHIFT_RIGHT &&
                            sym != KEY.KC_CTRL_LEFT &&
                            sym != KEY.KC_CTRL_RIGHT ) // don't count shift and ctrl (for repeats)
                            m_keyState.keysDown ++;

                        m_keyState.keys[sym] = KeyState.STATE.PRESSED;
                        event.emit(Event(KeyPress(sym)));

                        if (m_keyState.keys[KEY.KC_SHIFT_LEFT] == KeyState.STATE.PRESSED ||
                            m_keyState.keys[KEY.KC_SHIFT_RIGHT] == KeyState.STATE.PRESSED )
                        {
                            downWithShift ~= sym;
                        }
                    }
                    break;
                }

                case WM_KEYUP:
                {
                    auto sym = interpretKey(wParam);

                    if (cast(uint) sym > KEY.max)
                        break;

                    if (sym != KEY.KC_SHIFT_LEFT &&
                        sym != KEY.KC_SHIFT_RIGHT &&
                        sym != KEY.KC_CTRL_LEFT &&
                        sym != KEY.KC_CTRL_RIGHT ) // don't count shift and ctrl (for repeats)
                    {
                        if (m_keyState.keysDown > 0)
                            m_keyState.keysDown --;
                    }
                    else if (sym == KEY.KC_SHIFT_LEFT ||
                             sym == KEY.KC_SHIFT_RIGHT )
                    {
                        foreach(k; downWithShift)
                        {
                            m_keyState.keys[k] = KeyState.STATE.RELEASED;
                            event.emit(Event(KeyRelease(k)));
                        }
                        downWithShift.clear;
                    }

                    m_keyState.keys[sym] = KeyState.STATE.RELEASED;
                    event.emit(Event(KeyRelease(sym)));

                    break;
                }

                case WM_LBUTTONDOWN:
                {
                    SetCapture(m_hwnd);

                    if (m_mouseState.button[0] != MouseState.STATE.PRESSED)
                    {
                        m_mouseState.buttonsDown ++;
                        m_mouseState.button[0] = MouseState.STATE.PRESSED;

                        event.emit(Event(MouseClick(m_mouseState.xpos,
                                                    m_mouseState.ypos,
                                                    MouseClick.Button.LEFT)));
                    }
                    break;
                }

                case WM_LBUTTONUP:
                {
                    ReleaseCapture();

                    m_mouseState.buttonsDown --;
                    m_mouseState.button[0] = MouseState.STATE.RELEASED;

                    event.emit(Event(MouseRelease(m_mouseState.xpos,
                                                  m_mouseState.ypos,
                                                  MouseRelease.Button.LEFT)));

                    break;
                }

                case WM_MBUTTONDOWN:
                {
                    if (m_mouseState.button[1] != MouseState.STATE.PRESSED)
                    {
                        m_mouseState.buttonsDown ++;
                        m_mouseState.button[1] = MouseState.STATE.PRESSED;

                        event.emit(Event(MouseClick(m_mouseState.xpos,
                                                    m_mouseState.ypos,
                                                    MouseClick.Button.MIDDLE)));
                    }
                    break;
                }

                case WM_MBUTTONUP:
                {
                    m_mouseState.buttonsDown --;
                    m_mouseState.button[1] = MouseState.STATE.RELEASED;

                    event.emit(Event(MouseRelease(m_mouseState.xpos,
                                                  m_mouseState.ypos,
                                                  MouseRelease.Button.MIDDLE)));
                    break;
                }

                case WM_RBUTTONDOWN:
                {
                    if (m_mouseState.button[2] != MouseState.STATE.PRESSED)
                    {
                        m_mouseState.buttonsDown ++;
                        m_mouseState.button[2] = MouseState.STATE.PRESSED;

                        event.emit(Event(MouseClick(m_mouseState.xpos,
                                                    m_mouseState.ypos,
                                                    MouseClick.Button.RIGHT)));
                    }
                    break;
                }

                case WM_RBUTTONUP:
                {
                    m_mouseState.buttonsDown --;
                    m_mouseState.button[2] = MouseState.STATE.RELEASED;

                    event.emit(Event(MouseRelease(m_mouseState.xpos,
                                                  m_mouseState.ypos,
                                                  MouseRelease.Button.RIGHT)));
                    break;
                }

                case WM_MOUSEMOVE:
                {
                    int xpos = LOWORD(lParam);
                    int ypos = HIWORD(lParam);

                    // If mouse has left our window, flag it
                    if (xpos < 0 || xpos > m_windowState.xpix ||
                        ypos < 0 || ypos > m_windowState.ypix )
                    {
                        event.emit(Event(WindowFocusLost()));
                    }
                    else
                    {
                        m_mouseState.xrel = xpos - m_mouseState.xpos;
                        m_mouseState.yrel = ypos - m_mouseState.ypos;
                        m_mouseState.xpos = xpos;
                        m_mouseState.ypos = ypos;

                        event.emit(Event(MouseMove(m_mouseState.xpos,
                                                   m_mouseState.ypos,
                                                   m_mouseState.xrel,
                                                   m_mouseState.yrel)));
                    }
                    break;
                }

                case WM_SIZE:
                {
                    m_windowState.xpix = LOWORD(lParam);
                    m_windowState.ypix = HIWORD(lParam);

                    event.emit(Event(WindowResize(m_windowState.xpix,
                                                  m_windowState.ypix)));

                    break;
                }

                case WM_MOUSEWHEEL:
                {
                    event.emit(Event(MouseWheel(m_mouseState.xpos,
                                                m_mouseState.ypos,
                                                GET_WHEEL_DELTA_WPARAM(wParam))));
                    break;
                }

                case WM_DESTROY:
                {
                    if (!m_destroyed)
                        destroy();
                    break;
                }

                default:
                {
                    return DefWindowProcA(hwnd, message, wParam, lParam);
                }
            }

            return 0;
        }
    }


    // External function to redirect events back to window class
    extern(Windows)
    int wndProc(HWND hwnd,
                uint message,
                WPARAM wParam,
                LPARAM lParam)
    {
        Win32Window* hnd = hwnd in Win32Window.m_handles;

        if(hnd !is null)
            return hnd.windowProc(hwnd, message, wParam, lParam);
        else
            return DefWindowProcA(hwnd, message, wParam, lParam);
    }


    /**
    * Create a Win32 window.
    * Params:
    * hwnd = returned window handle
    * dc = returned device context for the window
    * wndClass = the window class name
    * ws = the initial WindowState for this window
    * show = wether or not this window is visible upon creation
    * pixelFormat = the pixel format to use for this window
    * Returns: 0 on success, non-zero on failure.
    */
    int createWindow(out HWND hwnd,
                     out HDC dc,
                     in string wndClass,
                     in WindowState ws,
                     in bool show = false,
                     in int pixelFormat = -1)
    {
        // The the hinstance of this module.
        HINSTANCE hinst = GetModuleHandle(null);
        hwnd = null;
        dc = null;

        // Create a window class.
        WNDCLASS wc;
        wc.cbClsExtra = 0;
        wc.cbWndExtra = 0;
        wc.hbrBackground = null; // needs to be null for proper WM_SIZE redraw handling
        wc.hCursor = LoadCursorA(null, IDC_ARROW);
        wc.hIcon = LoadIconA(null, IDI_APPLICATION);
        wc.hInstance = hinst;
        wc.lpfnWndProc = &wndProc;
        wc.lpszClassName = cast(char*)(wndClass~"\0");
        wc.lpszMenuName = cast(char*)0;
        wc.style = CS_HREDRAW | CS_VREDRAW;

        // Register it.
        if (!RegisterClassA(&wc))
        {
            writeln("Failed to register window class in win32 createWindow!");
            return -1;
        }

        // Window style.
        DWORD wndStyle = WS_CAPTION | WS_THICKFRAME |
                         WS_SYSMENU | WS_MINIMIZEBOX |
                         WS_MAXIMIZEBOX;

        // Grab an adjusted window rectangle.
        RECT wndRect;
        wndRect.left = 0;
        wndRect.top = 0;
        wndRect.right = ws.xpix;
        wndRect.bottom = ws.ypix;
        AdjustWindowRect(&wndRect, wndStyle, false);

        // Create the window, and get the window handle. The handle is returned.
        hwnd = CreateWindowA(cast(char*)(wndClass~"\0"),
                             cast(char*)("\0"),
                             wndStyle | CS_OWNDC | (WS_CLIPCHILDREN | WS_CLIPSIBLINGS),
                             ws.xpos,
                             ws.ypos,
                             wndRect.right - wndRect.left,
                             wndRect.bottom - wndRect.top,
                             null,
                             null,
                             hinst,
                             null );

        if (hwnd is null)
        {
            debug
            {
                writeln("Failed to create a window handle in win32 createGLContext!!");
            }
            return -2;
        }

        // Get the device context for the window. This value is returned.
        dc = GetDC(hwnd);

        // If we are supplied with a pixel format, set it for this device context.
        if (pixelFormat != -1)
        {
            PIXELFORMATDESCRIPTOR pfd;
            SetPixelFormat(dc, pixelFormat, &pfd);
        }

        // If the window is to be visible, set that now.
        if (show)
        {
            ShowWindow(hwnd, show);
            UpdateWindow(hwnd);
        }

        return 0;
    }


    // Destroy a Win32 window
    int destroyWindow(ref HWND hwnd,
                      ref HDC hdc)
    {
        // Get the window class name so we can de-register this class
        char[128] buffer;
        int n = GetClassName(hwnd, buffer.ptr, buffer.length);
        string className = to!string(buffer[0..n]) ~ "\0";

        // Release the device context
        if (hdc !is null)
            ReleaseDC(hwnd, hdc);

        // Destroy the window
        if (hwnd !is null)
            DestroyWindow(hwnd);

        // Clear the context and handle, as these are refs
        hdc = null;
        hwnd = null;

        // Unregister the class.
        int pf = UnregisterClass(cast(char*)(className), GetModuleHandle(null));

        if (pf == 0)
        {
            debug
            {
                writeln("Unable to unregister class name: %s", className);
            }
        }

        return 0;
    }

} // End version(Windows)




version(Posix)
{
    //---------------------------------//
    import X = deimos.X11.X;
    import Xlib = deimos.X11.Xlib;
    import Xutil = deimos.X11.Xutil;

    import dgl = derelict.opengl.glx;
    //---------------------------------//


    // Linux Window
    class NixWindow : Window
    {

    private:

        Xlib.Window m_win;

        static dgl.GLXContext m_glrc = null; // OpenGL render context, static to share amongst windows
        static Xlib.Display* m_display = null;
        derelict.opengl.glx.XVisualInfo* m_visualInfo;

    public:


        // On creation, load OpenGL and create a context if we don't already have one
        this(in string windowName,
             VideoProps props = VideoProps())
        {
            m_keyState.keys.length = KEY.max + 1;
            m_windowName = windowName;

             if (m_display is null)
                m_display = Xlib.XOpenDisplay(null);


            // Crate an openGL context to share among windows, if not already created
            if (m_glrc is null && m_haveContext == false)
            {
                DerelictGL.load();
                m_glrc = createGLContext(m_display, props, m_visualInfo);
                m_videoProps = props; // props may have changed, depending on what is available
                m_haveContext = true;
            }

            // Query the underlying driver name.
            m_driver = to!string(glGetString(GL_RENDERER));
            if (!match(m_driver.toLower, "mesa").empty)
                m_softwareDriver = true;

        }

        // Create the window.
        override int create(in WindowState ws,
                            in bool show)
        {
            m_windowState = ws;
            m_visible = show;
            createWindow(m_display, m_win, m_visualInfo, ws, show);

            return 0;
        }


        // Destroy the window.
        override void destroy()
        {
            if (!m_destroyed)
            {
                m_destroyed = true;

                if (dgl.glXGetCurrentContext() is m_glrc)
                    dgl.glXMakeCurrent(null, 0, null);

                destroyWindow(m_display, m_win);
                notifyDestroy(m_windowName);
            }
        }

        // Swap the buffers.
        override void swapBuffers()
        {
            dgl.glXSwapBuffers(m_display, cast(uint)m_win);
        }

        // Make window current with the GL context.
        override int makeCurrent()
        {
            dgl.glXMakeCurrent(m_display, cast(uint)m_win, m_glrc);
            return 0;
        }

    private:

        KEY[] downWithShift;

        KEY interpretKey(Xlib.XKeyEvent event)
        {
            char[6] buff;
            X.KeySym keysym;
            Xutil.XComposeStatus status;
            int count = Xutil.XLookupString(&event, buff.ptr, cast(int)buff.length, &keysym, &status);
            char ascii = buff[0];

            if (cast(uint)ascii == 0)
                return cast(KEY) (cast(uint)keysym + nonAsciiOffset);
            else
                return cast(KEY)ascii;
        }

        // Poll for events.
        override void poll()
        {
            Xlib.XEvent _event;

            while(Xlib.XPending(m_display))
            {
                Xlib.XNextEvent(m_display, &_event);

                switch (_event.type)
                {
                    case X.EventType.ExposeEvent:
                    {
                        event.emit(Event(WindowPaint()));
                        break;
                    }

                    case X.EventType.KeyPress:
                    {
                        auto sym = interpretKey(_event.xkey);

                        if (cast(uint) sym > KEY.max)
                            break;

                        if (m_keyState.keys[sym] != KeyState.STATE.PRESSED)
                        {
                            if (sym != KEY.KC_SHIFT_LEFT &&
                                sym != KEY.KC_SHIFT_RIGHT &&
                                sym != KEY.KC_CTRL_LEFT &&
                                sym != KEY.KC_CTRL_RIGHT ) // don't count shift and ctrl (for repeats)
                                m_keyState.keysDown ++;

                            m_keyState.keys[sym] = KeyState.STATE.PRESSED;
                            event.emit(Event(KeyPress(sym)));

                            if (m_keyState.keys[KEY.KC_SHIFT_LEFT] == KeyState.STATE.PRESSED ||
                            m_keyState.keys[KEY.KC_SHIFT_RIGHT] == KeyState.STATE.PRESSED )
                            {
                                downWithShift ~= sym;
                            }
                        }
                        break;
                    }

                    case X.EventType.KeyRelease:
                    {
                        auto sym = interpretKey(_event.xkey);

                        if (cast(uint) sym > KEY.max)
                            break;

                        if (sym != KEY.KC_SHIFT_LEFT &&
                            sym != KEY.KC_SHIFT_RIGHT &&
                            sym != KEY.KC_CTRL_LEFT &&
                            sym != KEY.KC_CTRL_RIGHT ) // don't count shift and ctrl (for repeats)
                        {
                            if (m_keyState.keysDown > 0)
                                m_keyState.keysDown --;
                        }
                        else if (sym == KEY.KC_SHIFT_LEFT ||
                             sym == KEY.KC_SHIFT_RIGHT )
                        {
                            foreach(k; downWithShift)
                            {
                                m_keyState.keys[k] = KeyState.STATE.RELEASED;
                                event.emit(Event(KeyRelease(k)));
                            }
                            downWithShift.clear;
                        }

                        m_keyState.keys[sym] = KeyState.STATE.RELEASED;
                        event.emit(Event(KeyRelease(sym)));
                        break;
                    }

                    case X.EventType.ButtonPress:
                    {
                        switch( _event.xbutton.button )
                        {
                            case X.ButtonName.Button1:   // left mouse button
                            {
                                if (m_mouseState.button[0] != MouseState.STATE.PRESSED)
                                {
                                    m_mouseState.buttonsDown ++;
                                    m_mouseState.button[0] = MouseState.STATE.PRESSED;

                                    event.emit(Event(MouseClick(m_mouseState.xpos,
                                                                m_mouseState.ypos,
                                                                MouseClick.Button.LEFT)));
                                }
                                break;
                            }

                            case X.ButtonName.Button2:   // middle
                            {
                                if (m_mouseState.button[1] != MouseState.STATE.PRESSED)
                                {
                                    m_mouseState.buttonsDown ++;
                                    m_mouseState.button[1] = MouseState.STATE.PRESSED;

                                    event.emit(Event(MouseClick(m_mouseState.xpos,
                                                                m_mouseState.ypos,
                                                                MouseClick.Button.MIDDLE)));
                                }
                                break;
                            }

                            case X.ButtonName.Button3:   // right
                            {
                                if (m_mouseState.button[2] != MouseState.STATE.PRESSED)
                                {
                                    m_mouseState.buttonsDown ++;
                                    m_mouseState.button[2] = MouseState.STATE.PRESSED;

                                    event.emit(Event(MouseClick(m_mouseState.xpos,
                                                                m_mouseState.ypos,
                                                                MouseClick.Button.RIGHT)));
                                }
                                break;
                            }

                            case X.ButtonName.Button4:   // mouse wheel up
                            {
                                event.emit(Event(MouseWheel(m_mouseState.xpos,
                                                            m_mouseState.ypos,
                                                            120)));
                                break;
                            }

                            case X.ButtonName.Button5:   // mouse wheel down
                            {
                                event.emit(Event(MouseWheel(m_mouseState.xpos,
                                                            m_mouseState.ypos,
                                                            -120)));
                                break;
                            }

                            default:
                                break;
                        }
                        break;
                    }

                    case X.EventType.ButtonRelease:
                    {
                        switch( _event.xbutton.button )
                        {
                            case X.ButtonName.Button1:   // left mouse button
                            {
                                if (m_mouseState.button[0] != MouseState.STATE.RELEASED)
                                {
                                    m_mouseState.buttonsDown --;
                                    m_mouseState.button[0] = MouseState.STATE.RELEASED;

                                    event.emit(Event(MouseRelease(m_mouseState.xpos,
                                                                  m_mouseState.ypos,
                                                                  MouseRelease.Button.LEFT)));
                                }
                                break;
                            }

                            case X.ButtonName.Button2:   // middle
                            {
                                if (m_mouseState.button[1] != MouseState.STATE.RELEASED)
                                {
                                    m_mouseState.buttonsDown --;
                                    m_mouseState.button[1] = MouseState.STATE.RELEASED;

                                    event.emit(Event(MouseRelease(m_mouseState.xpos,
                                                                  m_mouseState.ypos,
                                                                  MouseRelease.Button.MIDDLE)));
                                }
                                break;
                            }

                            case X.ButtonName.Button3:   // right
                            {
                                if (m_mouseState.button[2] != MouseState.STATE.RELEASED)
                                {
                                    m_mouseState.buttonsDown --;
                                    m_mouseState.button[2] = MouseState.STATE.RELEASED;

                                    event.emit(Event(MouseRelease(m_mouseState.xpos,
                                                                  m_mouseState.ypos,
                                                                  MouseRelease.Button.RIGHT)));
                                }
                                break;
                            }

                            default:
                                break;
                        }
                        break;
                    }

                    case X.EventType.MotionNotify:
                    {
                        int xpos = _event.xmotion.x;
                        int ypos = _event.xmotion.y;

                        // If mouse has left our window, flag it
                        if (xpos < 0 || xpos > m_windowState.xpix ||
                            ypos < 0 || ypos > m_windowState.ypix )
                        {
                            event.emit(Event(WindowFocusLost()));
                        }
                        else
                        {
                            m_mouseState.xrel = xpos - m_mouseState.xpos;
                            m_mouseState.yrel = ypos - m_mouseState.ypos;
                            m_mouseState.xpos = xpos;
                            m_mouseState.ypos = ypos;

                            event.emit(Event(MouseMove(m_mouseState.xpos,
                                                       m_mouseState.ypos,
                                                       m_mouseState.xrel,
                                                       m_mouseState.yrel)));
                        }
                        break;
                    }

                    case X.EventType.ConfigureNotify:
                    {
                        m_windowState.xpix = _event.xconfigure.width;
                        m_windowState.ypix = _event.xconfigure.height;

                        event.emit(Event(WindowResize(m_windowState.xpix,
                                                      m_windowState.ypix)));

                        break;
                    }

                    case X.EventType.DestroyNotify: // This is not called, see next case
                    {
                        if (!m_destroyed)
                            destroy();
                        break;
                    }

                    case X.EventType.ClientMessage: // Window destroy message
                    {
                        if (!m_destroyed)
                            destroy();
                        break;
                    }

                    default:
                        break;
                }

            }
        }

        // Set the window title.
        override void setTitle(in string title)
        {
            Xlib.XStoreName(m_display, m_win, cast(char*)(title.toStringz));
        }

        // Set the cursor position.case ClientMessage:
        override void setCursorPos(in int x,
                                   in int y)
        {
            Xlib.XWarpPointer(m_display, X.None, m_win,
                              0, 0, // src_x, src_y
                              0, 0, // src_width, src_height
                              x, y);
        }

        // Show/hide the cursor.
        override void showCursor(in bool show)
        {
            if (show)
            {
                // This will restore the default pointer
                Xlib.XUndefineCursor(m_display, m_win);
            }
            else
            {
                // Hiding the pointer is a bit involved under X11...
                Xlib.Cursor no_ptr;
                Xlib.Pixmap bm_no;
                Xlib.XColor black, dummy;
                Xlib.Colormap colormap;
                char no_data[] = [0,0,0,0,0,0,0,0];

                colormap = Xlib.DefaultColormap(*m_display, Xlib.DefaultScreen(*m_display));
                Xlib.XAllocNamedColor(m_display, colormap, cast(char*)"black\n".ptr, &black, &dummy);
                bm_no = Xlib.XCreateBitmapFromData(m_display, m_win, no_data.ptr, 8, 8);
                no_ptr = Xlib.XCreatePixmapCursor(m_display, bm_no, bm_no, &black, &black, 0, 0);

                Xlib.XDefineCursor(m_display, m_win, no_ptr);
                Xlib.XFreeCursor(m_display, no_ptr);
            }
        }

    }


    /**
    * Create an X11 Window.
    * Returns: 0 on success, non-zero otherwise
    * Params:
    * win = returned Xlib.WIndow
    * vi = returned XVisualInfo*
    * ws = WindowState
    * show = show or hide the window by default
    */
    int createWindow(Xlib.Display* display,
                     out Xlib.Window win,
                     dgl.XVisualInfo* vi,
                     in WindowState ws,
                     in bool show = false)
    {
        if(display is null)
            return 1;

        int screenNumber = Xlib.DefaultScreen(*display);

        Xlib.XSetWindowAttributes swa;
        swa.event_mask = (1 << 25) - 1; // we want most events...
        swa.event_mask = swa.event_mask ^ (1 << 7); // except for the motionnotifyhint mask

        swa.colormap = Xlib.XCreateColormap(display,
                                            Xlib.DefaultRootWindow(*display),
                                            cast(Xlib.Visual*)vi.visual,
                                            X.AllocType.AllocNone);

        win = Xlib.XCreateWindow(display,
                                 Xlib.DefaultRootWindow(*display),
                                 ws.xpos, ws.ypos, // position
                                 ws.xpix, ws.ypix, // size
                                 0,
                                 cast(Xlib.Visual*)vi.depth,
                                 X.WindowClass.InputOutput,
                                 cast(Xlib.Visual*)vi.visual,
                                 X.WindowAttribute.CWColormap | X.WindowAttribute.CWEventMask,
                                 &swa);

        Xlib.XMapWindow(display, win);

        Xlib.XEvent evt;
        while( evt.type != X.EventType.MapNotify )
        {
            Xlib.XNextEvent( display, &evt );   // calls XFlush
        }

        // This is to allow getting window destroy events
        Xlib.Atom wmDelete = Xlib.XInternAtom(display, cast(char*)("WM_DELETE_WINDOW".toStringz()), Xlib.Bool.True);
        Xlib.XSetWMProtocols(display, win, &wmDelete, 1);

        return 0;
    }


    /**
    * Destroy an X11 Window.
    * Returns: 0 on success.
    * Params:
    * display = the display the window is part of
    * win = the Xlib.Window to destroy
    */
    int destroyWindow(Xlib.Display* display,
                      Xlib.Window win)
    {
        Xlib.XDestroyWindow(display, win);
        Xlib.XCloseDisplay(display);
        return 0;
    }

} // End version(Posix)

