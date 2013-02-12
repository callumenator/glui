// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Summary: Simple threaded TimerPool.
*/

module glui.timer;

import
    std.container,
    std.range,
    std.stdio,
    core.thread,
    std.datetime,
    std.parallelism;

/**
* Creates a new thread which sleeps for msecs milliseconds and
* then calls the supplied delegate. The thread continues to call
* the supplied delegate until that delegate returns a value of false.
*/
void delayed(ulong msecs, bool delegate() callback)
{
    task!(
        (ulong _msecs, bool delegate() _callback)
        {
            do {
                Thread.sleep(dur!"msecs"(_msecs));
            } while(_callback());
        }
    )(msecs, callback).executeInNewThread();
}

/**
* Encapsulate a timer which runs in a separate thread. This class is intended
* to be used in conjuction with TimerPool.
*/
class Timer : Thread
{
    alias bool delegate() CallBack;
    alias void delegate(Timer) DoneFunc;

    this(DoneFunc done)
    {
        super(&wait);
        this.notifyDone = done;
    }

    this(DoneFunc done, ulong msecs, CallBack call)
    {
        this(done);
        set(msecs, call);
    }

    Timer set(ulong msecs, CallBack call) nothrow
    {
        this.call = call;
        this.msecs = msecs;
        return this;
    }

    void wait()
    {
        do {
            Thread.sleep(dur!"msecs"(msecs));
        } while(call());

        notifyDone(this);
    }

private:

    ulong msecs;
    CallBack call;
    DoneFunc notifyDone;
}

/**
* Manages a pool of re-usable Timers.
*/
class TimerPool
{
    /**
    * Optionally initialize the pool with a given number of timers.
    */
    this(uint poolSize = 2)
    {
        foreach(i; iota(poolSize))
            newTimer();
    }

    /**
    * Called by client to schedule a timer event.
    */
    void timer(ulong msecs, bool delegate() dg)
    {
        if (free.empty)
            (new Timer(&timerDone)).set(msecs, dg).start();
        else
            free.removeAny.set(msecs, dg).start();
    }

private:

    /**
    * Create a new Timer and put it on the free list.
    */
    void newTimer()
    {
        free.insertFront(new Timer(&timerDone));
    }

    /**
    * Called by a Timer to indicate that it is now free.
    */
    void timerDone(Timer t)
    {
        synchronized(this)
        {
            free.insertFront(t);
        }
    }

    SList!(Timer) free;
}
