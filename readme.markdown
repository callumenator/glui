This repo contains routines for creating and managing windows, handling window events,
loading and rendering truetype fonts using freetype, and drawing GUI elements in openGL.

###Windows:
Create a window:
```
Window("window1",/** handle for the window, so we can look for it later **/
       true, /** create the window is the handle does not exist **/
       WindowState(0,0,500,500) /** window star position and dimensions **/
       );
Window("window1").makeCurrent(); /// make this the current window **/
Window().setTitle("GLUI"); /// Window(), called without a handle, returns the current window **/
```
Windows are created with openGL render contexts (using the old way of creating contexts, I
haven't updated to openGL 3.0 yet...). Multiple windows can be created, and they will all
share the same context.

###Events:
The Window class has a PrioritySignal, which is the same as the phobos Signal mixin except it
allows listeners to connect with a specified priority, so some listeners will receive events 
before others with lower priority. To receive events, you need a class with an event handler
(really you need a delegate):
```
class Handler
{  
   int handleEvent(Event event)
   {
      /// do stuff here
      return 0; /// returning -1 for exampe will stop other listeners from getting events
   }
}
Handler hnd = new Handler();
Window().event.connect(&hnd.handleEvent, PRIORITY.NORMAL);
Window().poll(); 
```
Polling needs to happen recurrently of course. If you are using the widget code, then the 
WidgetRoot class will take care of polling automatically (and will also put the thread to 
sleep if the pollig frequency is too high).

###Widgets
__See example.d for widgets usage.__
Currently there are plain window widgets (a box with a background and a border, can be 
textured with a jpg or png image), text widgets (editable or not, with selectable fonts),
scroll widgets (for scroll bars, which can fade in and out when hovered), and tree widgets.
Again, see the example.d for usage.

Note that this code is very preliminary, and constantly changing.