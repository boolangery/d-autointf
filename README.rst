autointf
===============================================================================

.. image:: https://img.shields.io/dub/v/autointf.svg
    :target: https://code.dlang.org/packages/autointf


An helper-library to auto-generate interface implementation from a
template function.


Installation:
------------------------------------------------------------------------------

TODO


Quickstart
==============================================================================

To start you must define a class like below:

.. code-block:: d

    import std.stdio;

    class AutoDescribe(I) : AutoInterfaceImpl!I
    {
        RT executeMethod(I, TCtx, RT, int n, ARGS...)(ref InterfaceInfo!(I, TCtx) info, ARGS args)
        {
            import std.traits;
            import std.conv : to;

            // retrieve some compile time informations
            alias Func  = info.Methods[n];
            alias RT    = ReturnType!Func;
            alias PTT   = ParameterTypeTuple!Func;
            auto method = info.methods[n];

            string ret;
            import std.stdio;

            foreach (i, PT; PTT) {
                auto param = method.parameters[i];
                ret ~= "\t" ~ param.name ~ "(" ~ PT.stringof ~ ") = " ~ to!string(args[i]) ~ "\n";
            }

            return method.name ~ ":\n" ~ ret;
        }

        mixin(autoImplementMethods!I());
    }

    interface IAPI
    {
        string hello(int number, string str);
    }

    auto api = new AutoDescribe!IAPI();


    writeln(api.hello(42, "foo"));
    // hello:
    //     number(int) = 42
    //     str(string) = foo


The class must inherits from AutoInterfaceImpl (it contains some compile time things).

Then you must declare the method "executeMethod" with this signature:

.. code-block:: d

    /**
    Params:
        I = The interface to implement type.
        TCtx = Context type.
        TR = Method return type.
        n = Method index inside info argument.
        ARGS... = method arguments type.

        info = An InterfaceInfo object.
        args = Args value.
    **/
    RT executeMethod(I, TCtx, RT, int n, ARGS...)(ref InterfaceInfo!(I, TCtx) info, ARGS args)

This method is used as implementation in auto-implemented interface.

Finally you must call:

.. code-block:: d

    mixin(autoImplementMethods!I());

to implement your interface with the given "executeMethod".
