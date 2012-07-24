// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: Functions for handling platform specific window creation and OpenL
* context creation.
*/
module glui.osgl;

import
    derelict.util.exception;

import
    glui.window;


// Structure containing video buffer properties
struct VideoProps
{
    align(1) union
    {
        struct
        {   // Default properties.
            int colorBits = 32;
            int redBits = 8;
            int greenBits = 8;
            int blueBits = 8;
            int alphaBits = 8;
            int depthBits = 32;
            int stencilBits = 8;
            int multisampleBuffers = 1;
            int multisampleSamples = 8;
        }
        int[9] v; // Convenience for reading attributes.
    }
}

// Create a list of attributes for pixel format selection
int[] fillAttribList(in VideoProps p, bool multiSample = false)
{
    version(Windows)
    {
        int[] attribList =
        [   WGL_DRAW_TO_WINDOW_ARB, GL_TRUE,
            WGL_SUPPORT_OPENGL_ARB, GL_TRUE,
            WGL_DOUBLE_BUFFER_ARB, GL_TRUE,
            WGL_ACCELERATION_ARB, WGL_FULL_ACCELERATION_ARB,
            WGL_PIXEL_TYPE_ARB, WGL_TYPE_RGBA_ARB,
            WGL_COLOR_BITS_ARB, p.colorBits,
            WGL_RED_BITS_ARB, p.redBits,
            WGL_GREEN_BITS_ARB, p.greenBits,
            WGL_BLUE_BITS_ARB, p.blueBits,
            WGL_ALPHA_BITS_ARB, p.alphaBits,
            WGL_DEPTH_BITS_ARB, p.depthBits,
            WGL_STENCIL_BITS_ARB, p.stencilBits];

        // If multisampling is supported, add it to the list.
        if (multiSample)
        {
            attribList ~= [ WGL_SAMPLE_BUFFERS_ARB, p.multisampleBuffers,
                            WGL_SAMPLES_ARB, p.multisampleSamples ];
        }
    }

    version(Posix)
    {
        int[] attribList =
        [   ];

        // If multisampling is supported, add it to the list.
        if (multiSample)
        {
            attribList ~= [ ];
        }
    }


    // Needs to be a null-terminated list.
    attribList ~= [0];
    return attribList.dup;
}


// Define an array of properties to query. This must match the VideoProps layout!
const(int[9]) queryAttribList()
{
    version(Windows)
    {
        const(int[9]) query =
        [   WGL_COLOR_BITS_ARB,
            WGL_RED_BITS_ARB,
            WGL_GREEN_BITS_ARB,
            WGL_BLUE_BITS_ARB,
            WGL_ALPHA_BITS_ARB,
            WGL_DEPTH_BITS_ARB,
            WGL_STENCIL_BITS_ARB,
            WGL_SAMPLE_BUFFERS_ARB,
            WGL_SAMPLES_ARB ];
    }

    version(Posix)
    {
        const(int[9]) query =
        [];
    }

    return query;
}


bool glMissingProcCallback(string libName, string procName)
{
	return false;
}

/** Win32 routines. **/
version(Windows)
{
    //---------------------------------//
    import std.conv;
    import std.stdio;

    import win32.windef;
    import win32.winuser;
    import win32.wingdi;
    import win32.winbase;
    pragma(lib, "gdi32.lib");

    import derelict.opengl.gl;
    import derelict.opengl.wgl;
    import derelict.opengl.gltypes;
    import derelict.opengl.exttypes;
    import derelict.opengl.extfuncs;
    //---------------------------------//

    /**
    * Create an OpenGL context.
    * Params: p = VideoProps structure. This structure contains the desired video properties,
    * and will be filled with the actual video properties on return.
    */
    HGLRC createGLContext(ref VideoProps p,
                          out int pixFormat)
    {
        // Create a dummy window.
        HWND hwnd;
        HDC dc;
        createWindow(hwnd, dc, "dscape_win32_dummy", WindowState(0,0,0,0));

        // Create a simple pixel format that shouldn't fail, so we can get a simple rendering context.
        PIXELFORMATDESCRIPTOR pfd =
        {
            PIXELFORMATDESCRIPTOR.sizeof,
            1,
            PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
            PFD_TYPE_RGBA,
            8, // Colordepth
            0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0,
            8, // Depthbuffer
            0, // Stencilbuffer
            0, // Aux buffs
            0, 0, 0, 0, 0
        };

        int iFormat = ChoosePixelFormat(dc, &pfd);

        if (iFormat == 0)
            throw new Exception("Failed to get simple pixel format in win32 createGLContext!");

        // Set the simple pixel format.
        SetPixelFormat(dc, iFormat, &pfd);

        // Create a dummy context to get function handles.
        HGLRC glrc = cast(HANDLE)derelict.opengl.wgl.wglCreateContext(dc);

        if (glrc is null)
            throw new Exception("Failed to get dummy context in win32 createGLContext!");

        derelict.opengl.wgl.wglMakeCurrent(dc, glrc);

        // Load OpenGL extensions now that we have a dummy context.
        Derelict_SetMissingProcCallback(&glMissingProcCallback);
        DerelictGL.loadExtendedVersions();
        DerelictGL.loadExtensions();

        // Check for multisample support.
        bool multiSample_support = DerelictGL.isExtensionLoaded("GL_ARB_multisample");

        // Destroy window and context, create a new window.
        destroyWindow(hwnd, dc);
        derelict.opengl.wgl.wglDeleteContext(glrc);
        glrc = null;
        createWindow(hwnd, dc, "dscape_win32_dummy", WindowState(0,0,0,0));

        // First see if we can get away with the selected video properties.
        int pixelFormat = -1;
        uint numFormats = 0;
        auto attribList = fillAttribList(p, multiSample_support);
        wglChoosePixelFormatARB(dc, attribList.ptr, null, 1, &pixelFormat, &numFormats);

        auto _query = queryAttribList();

        /**
        * If no format was found, some of our video minimums were set too high. Set them
        * lower, and pick the format with the best match
        */
        if (numFormats == 0)
        {
            int[50] _pixelFormat;
            uint _numFormats;

            VideoProps _p = p;
            _p.v = [0,0,0,0,0,0,0,0,0]; // Set them all low, but pick a multisample buffer.

            attribList = fillAttribList(_p, multiSample_support);
            wglChoosePixelFormatARB(dc, attribList.ptr, null, 50, _pixelFormat.ptr, &_numFormats);

            int _max = _numFormats <= 50 ? _numFormats : 50;

            if (_numFormats == 0)
                throw new Exception("No pixel formats found!");

            // Pick the most capable format of those returned, and get its attributes.
            int[9] _attribs;
            wglGetPixelFormatAttribivARB(dc, _pixelFormat[_max-1], 0, 9, _query.ptr, _attribs.ptr);

            // For each desired attribute, compare against what is actually achievable.
            foreach(idx; 0..9)
            {
                if (_attribs[idx] < p.v[idx])
                    p.v[idx] = _attribs[idx];
            }

            // Try again with the new values.
            numFormats = 0;
            attribList = fillAttribList(p, multiSample_support);
            wglChoosePixelFormatARB(dc, attribList.ptr, null, 1, &pixelFormat, &numFormats);

            // If we got a format, set the windows video attributes.
            VideoProps np;
            if (numFormats == 1)
            {
                wglGetPixelFormatAttribivARB(dc, pixelFormat, 0, 9, _query.ptr, np.v.ptr);
                p = np;
            }
        }

        // Check that we got a format.
        if (pixelFormat != -1)
        {
            SetPixelFormat(dc, pixelFormat, &pfd);
            glrc = cast(HANDLE)derelict.opengl.wgl.wglCreateContext(dc);

             if (glrc is null)
                throw new Exception("Failed to create OpenGL context!");

            // Make the context current.
            derelict.opengl.wgl.wglMakeCurrent(dc, glrc);

            // If multisampling is enabled, turn it on.
            if (multiSample_support)
                glEnable(GL_MULTISAMPLE);

            // Clear the current context.
            derelict.opengl.wgl.wglMakeCurrent(null, null);

            // Destroy the window.
            destroyWindow(hwnd, dc);

            // Return the pixel format.
            pixFormat = pixelFormat;

            return glrc;
        } else {
            writeln("Could not find a matching pixel format! No GL context created. Bad.");
            return cast(HGLRC)null;
        }
    }

} // Version windows


version(Posix)
{
    //---------------------------------//
    import std.conv;
    import std.stdio;

    import deimos.X11.X;
    import deimos.X11.Xlib;
    import deimos.X11.Xutil;

    import derelict.opengl.gl;
    import derelict.opengl.glx;
    import derelict.opengl.gltypes;
    import derelict.opengl.exttypes;
    import derelict.opengl.extfuncs;
    //---------------------------------//

    // These should be in derelict, but they don't seem to be...
    // got them from Moonglide
    const GLuint GLX_USE_GL                 = 1;
    const GLuint GLX_BUFFER_SIZE            = 2;
    const GLuint GLX_LEVEL                  = 3;
    const GLuint GLX_RGBA                   = 4;
    const GLuint GLX_DOUBLEBUFFER           = 5;
    const GLuint GLX_STEREO                 = 6;
    const GLuint GLX_AUX_BUFFERS            = 7;
    const GLuint GLX_RED_SIZE               = 8;
    const GLuint GLX_GREEN_SIZE             = 9;
    const GLuint GLX_BLUE_SIZE              = 10;
    const GLuint GLX_ALPHA_SIZE             = 11;
    const GLuint GLX_DEPTH_SIZE             = 12;
    const GLuint GLX_STENCIL_SIZE           = 13;
    const GLuint GLX_ACCUM_RED_SIZE         = 14;
    const GLuint GLX_ACCUM_GREEN_SIZE       = 15;
    const GLuint GLX_ACCUM_BLUE_SIZE        = 16;
    const GLuint GLX_ACCUM_ALPHA_SIZE       = 17;

    //Error return values from glXGetConfig. Success is indicated by a value of 0.
    const GLuint GLX_BAD_SCREEN             = 1;
    const GLuint GLX_BAD_ATTRIBUTE          = 2;
    const GLuint GLX_NO_EXTENSION           = 3;
    const GLuint GLX_BAD_VISUAL             = 4;
    const GLuint GLX_BAD_CONTEXT            = 5;
    const GLuint GLX_BAD_VALUE              = 6;
    const GLuint GLX_BAD_ENUM               = 7;

    /**
    * Create an OpenGL context.
    * Params: p = VideoProps structure. This structure contains the desired video properties,
    * and will be filled with the actual video properties on return.
    */
    GLXContext createGLContext(Display* dpy,
                               ref VideoProps p,
                               out derelict.opengl.glx.XVisualInfo* vi)
    {
        // TODO: implement the non-hardcoded version of this
        GLint att[] = [
            GLX_RGBA,
            GLX_DOUBLEBUFFER,
            GLX_RED_SIZE, 8,
            GLX_GREEN_SIZE, 8,
            GLX_BLUE_SIZE, 8,
            GLX_DEPTH_SIZE, 16,
            None ];

        GLXContext glc = null;
        vi = glXChooseVisual(dpy, 0, att.ptr);

        if (vi is null)
            throw new Exception("createGLContext: Could not generate visual");

        glc = glXCreateContext(dpy, vi, null, GL_TRUE);

        glXMakeCurrent(cast(void*)XOpenDisplay(null), cast(uint)(DefaultRootWindow(*cast(_XDisplay*)dpy)), glc);

        // Load OpenGL extensions now that we have a dummy context.
        Derelict_SetMissingProcCallback(&glMissingProcCallback);
        DerelictGL.loadExtendedVersions();
        DerelictGL.loadExtensions();

        if (glc is null)
            throw new Exception("createGLContext: Could not get GL context");

        return glc;

    }

} // Version(Posix)





















