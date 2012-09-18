
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
    glui.widget.base;


int main()
{
	Window("window1", WindowState(0,0,1000,700), Flag!"Create".yes, Flag!"Show".yes);
    Window.makeCurrent("window1");
	Window().setTitle("GLUI");

	Font courier = loadFont("../media/fonts/Courier_New.ttf", 11);
	Font lacuna = loadFont("../media/fonts/lacuna.ttf", 14);

	glViewport(0,0,1000,700);
	glClearColor(0,0,0,1);


    WidgetRoot root = new WidgetRoot(Window("window1"));

    auto highlighter = new DSyntaxHighlighter;

    auto textl = root.create!WidgetText(null, courier, widgetArgs(
                                        "dim", [480, 680],
                                        "pos", [10,10],
                                        "texture", loadTexture("../media/images/dark1.png"),
                                        "bordercolor", RGBA(1,1,1,1),
                                        "editable", true,
                                        "vscroll", true,
                                        "candrag", true,
                                        "highlighter", highlighter));

    auto layout = root.create!WidgetTree(null, widgetArgs(
                                          "dim", [300, 400],
                                          "pos", [500,10],
                                          "background", RGBA(0,.9,.3,.3),
                                          "bordercolor", RGBA(1,1,1,1),
                                          "resize", ResizeFlag.X | ResizeFlag.Y,
                                          "clipToScrollBar", false,
                                          "scrollFade", false,
                                          "scrollforeground", RGBA(0,0,0,1),
                                          "scrollborder", RGBA(1,1,1,1)));

    foreach(i; 0..5)
    {
        auto branch = layout.root.create!WidgetLabel(null, lacuna, widgetArgs(
                                                      "text", "Level 0, Item " ~ i.to!string,
                                                      "dim", [200,25],
                                                      "background", RGBA(97,48,145,255)));
        layout.add(null, branch, Flag!"NoUpdate".yes);

        foreach(j; 0..5)
        {
            auto lab = root.create!WidgetLabel(null, courier, widgetArgs(
                                                "text", "Level 1, Item " ~ j.to!string,
                                                "dim", [200,20],
                                                "fixedwidth", true,
                                                "cornerRadius", 15,
                                                "bordercolor", RGBA(0,0,0,1),
                                                "background", RGBA(96,159,214,255)));

            layout.add(branch, lab, Flag!"NoUpdate".yes);

            foreach(k; 0..5)
            {
                auto leaf = root.create!WidgetLabel(null, lacuna, widgetArgs(
                                                           "text", "Level 2, Item " ~ k.to!string,
                                                           "dim", [200,25],
                                                           "background", RGBA(153,31,131,255)));

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
