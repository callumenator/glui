
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

	Font courier = createFont("../media/fonts/Courier_New.ttf", 11);
	Font lacuna = createFont("../media/fonts/lacuna.ttf", 14);

	glViewport(0,0,1000,700);
	glClearColor(0,0,0,1);

    WidgetRoot root = new WidgetRoot(Window("window1"));

    auto textl = root.create!WidgetText(null, courier, Flag!"Editable".yes, Flag!"Vscroll".yes, Flag!"Hscroll".no);
    textl.setDim(480, 680);
    textl.setPos(10, 10);
    textl.bgColor = RGBA(0,0,0,1);
    textl.borderColor = RGBA(1,1,1,1);
    textl.textBgColor = RGBA(0,.5,.5,.5);
    textl.texture = loadTexture("../media/images/dark1.png");
    textl.canDrag = true;

    auto layout = root.create!WidgetTree(null);
    layout.setDim(300, 400);
    layout.setPos(500, 10);
    layout.bgColor = RGBA(0,0.9,.3,.5);
    layout.borderColor = RGBA(1,1,1,1);
    layout.canDrag = true;

    foreach(i; 0..5)
    {
        auto branch = layout.root.create!WidgetText(null, lacuna);
        branch.setDim(200, 25);
        branch.bgColor = RGBA(97,48,145,255);
        branch.valign = WidgetText.VAlign.CENTER;
        branch.text.set("Level 0, Item " ~ i.to!string);
        layout.add(null, branch, Flag!"NoUpdate".yes);

        foreach(j; 0..5)
        {
            auto lab = layout.root.create!WidgetText(null, courier);
            lab.setDim(200, 20);
            lab.bgColor = RGBA(96,159,214,255);
            lab.valign = WidgetText.VAlign.CENTER;
            lab.text.set("Level 1, Item " ~ j.to!string);
            layout.add(branch, lab, Flag!"NoUpdate".yes);

            foreach(k; 0..5)
            {
                auto leaf = layout.root.create!WidgetText(null, lacuna);
                leaf.setDim(200, 25);
                leaf.bgColor = RGBA(153,31,131,255);
                leaf.valign = WidgetText.VAlign.CENTER;
                leaf.text.set("Level 2, Item " ~ k.to!string);
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
