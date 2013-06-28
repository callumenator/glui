
module example;

import
    std.conv,
    std.stdio;

import
    imaged.jpeg,
    imaged.png,
    imaged.image;

import
    derelict.opengl.gl;

import
    glui.window,
    glui.event,
    glui.truetype,
    glui.widget.base,
    glui.widget.tree;



int main()
{
	Window("window1", WindowState(0,0,1000,700), Flag!"Create".yes, Flag!"Show".yes);
    Window.makeCurrent("window1");
	Window().setTitle("GLUI");

	auto droidFont = loadFont("../media/fonts/DroidSansMono.ttf", 12);

	glViewport(0,0,1000,700);
	glClearColor(0,0,0,1);


    WidgetRoot root = new WidgetRoot(Window("window1"));

    scope(exit)
        root.destroy();

    //auto highlighter = new DSyntaxHighlighter;

    auto textl = root.create!WidgetText(null,
                                        "font", droidFont,
                                        "dim", [480, 680],
                                        "pos", [10,10],
                                        "texture", loadTexture("../media/images/dark1.png"),
                                        "bordercolor", RGBA(1,1,1,1),
                                        "scrollBackground", RGBA(0,0,0,.2),
                                        "scrollForeground", RGBA(.6,.6,.6,.8),
                                        "editable", true,
                                        "vscroll", true,
                                        "drag", true);

    auto layout = root.create!WidgetTree(null,
                                          "dim", [300, 400],
                                          "pos", [500,10],
                                          "background", RGBA(207,169,219,255),
                                          "bordercolor", RGBA(1,1,1,1),
                                          "resize", ResizeFlag.X | ResizeFlag.Y,
                                          "clipToScrollBar", false,
                                          "scrollFade", false,
                                          "scrollforeground", RGBA(0,0,0,1),
                                          "scrollborder", RGBA(1,1,1,1));

    foreach(i; 0..5)
    {
        auto branch = layout.root.create!WidgetLabel(null,
                                                     "font", droidFont,
                                                     "text", "Level 0, Item " ~ i.to!string,
                                                     "dim", [200,25],
                                                     "background", RGBA(133,86,206,255));
        layout.add(null, branch, Flag!"NoUpdate".yes);

        foreach(j; 0..5)
        {
            auto lab = root.create!WidgetLabel(null,
                                               "font", droidFont,
                                               "text", "Level 1, Item " ~ j.to!string,
                                               "dim", [200,20],
                                               "fixedwidth", true,
                                               "cornerRadius", 15,
                                               "bordercolor", RGBA(0,0,0,1),
                                               "background", RGBA(86,123,204,255));

            layout.add(branch, lab, Flag!"NoUpdate".yes);

            foreach(k; 0..5)
            {
                auto leaf = root.create!WidgetLabel(null,
                                                    "font", droidFont,
                                                    "text", "Level 2, Item " ~ k.to!string,
                                                    "dim", [200,25],
                                                    "background", RGBA(153,31,131,255));

                layout.add(lab, leaf, Flag!"NoUpdate".yes);
            }
        }
    }
    layout.update();

    bool finish = false;
    while (!finish)
    {
        root.poll();

        if (Window().keyState().keys[KEY.KC_ESCAPE])
            finish = true;
    }

    return 0;

}
