
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

    auto textl = root.create!WidgetText(null, courier,
                                        arg("dim", [480, 680]),
                                        arg("pos", [10,10]),
                                        arg("texture", loadTexture("../media/images/dark1.png")),
                                        arg("border", RGBA(1,1,1,1)),
                                        arg("editable", true),
                                        arg("vscroll", true),
                                        arg("candrag", true));

    auto layout = root.create!WidgetTree(null,
                                         arg("dim", [300, 400]),
                                         arg("pos", [500,10]),
                                         arg("background", RGBA(0,.9,.3,.5)),
                                         arg("border", RGBA(1,1,1,1)),
                                         arg("candrag", true));

    foreach(i; 0..5)
    {
        auto branch = layout.root.create!WidgetLabel(null, lacuna,
                                                     arg("text", "Level 0, Item " ~ i.to!string),
                                                     arg("dim", [200,25]),
                                                     arg("background", RGBA(97,48,145,255)));
        layout.add(null, branch, Flag!"NoUpdate".yes);

        foreach(j; 0..5)
        {
            auto lab = root.create!WidgetLabel(null, courier,
                                               arg("text", "Level 1, Item " ~ j.to!string),
                                               arg("dim", [200,20]),
                                               arg("fixedwidth", true),
                                               arg("background", RGBA(96,159,214,255)));

            layout.add(branch, lab, Flag!"NoUpdate".yes);

            foreach(k; 0..5)
            {
                auto leaf = root.create!WidgetLabel(null, lacuna,
                                                          arg("text", "Level 2, Item " ~ k.to!string),
                                                          arg("dim", [200,25]),
                                                          arg("background", RGBA(153,31,131,255)));

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
