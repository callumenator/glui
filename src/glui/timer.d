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
    core.sync.condition,
    core.sync.mutex,
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

    this(TimerPool pool)
    {
        mutex = new Mutex();
        cond = new Condition(mutex);

        super(&wait);
        this.pool = pool;
    }

    this(TimerPool pool, ulong msecs, CallBack call)
    {
        this(pool);
        set(msecs, call);
    }

    Timer set(ulong msecs, CallBack call) nothrow
    {
        mutex.lock(); scope(exit) mutex.unlock();
        this.call = call;
        this.msecs = msecs;
        return this;
    }

    void term()
    {
        mutex.lock(); scope(exit) mutex.unlock();
        cond.notifyAll();
    }

    void wait()
    {
        mutex.lock(); scope(exit) mutex.unlock();

        do {
            cond.wait(dur!"msecs"(msecs));
        } while(!pool.term && call());

        pool.timerDone(this);
    }

private:

    ulong msecs;
    CallBack call;
    TimerPool pool;
    Mutex mutex;
    Condition cond;

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
    * Timers check this to see if they should terminate.
    */
    @property bool term() const
    {
        return _term;
    }

    /**
    * Teminate all timers in the pool.
    */
    void finalize()
    {
        foreach(timer; pool)
            timer.term();

        _term = true;
    }

    /**
    * Called by client to schedule a timer event.
    */
    void timer(ulong msecs, bool delegate() dg)
    {
        if (_term)
            return;

        if (free.empty)
            (new Timer(this)).set(msecs, dg).start();
        else
            free.removeAny.set(msecs, dg).start();
    }

private:

    /**
    * Create a new Timer and put it on the free list.
    */
    void newTimer()
    {
        free.insertFront(new Timer(this));
        pool ~= free.front;
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
    Timer[] pool;
    bool _term;
}
