autointf
===============================================================================

An helper-library to auto-generate interface implementation from a
template function.


Installation:
------------------------------------------------------------------------------

TODO


Quickstart
==============================================================================


.. code-block:: d

	import std.stdio;


	RT returnString(I, RT, int n, ARGS...)(ref InterfaceInfo!I info)
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
			ret ~= "\t" ~ param.name ~ "(" ~ PT.stringof ~ ") = " ~ to!string(ARGS[i]) ~ "\n";
        }

		return method.name ~ ":\n" ~ ret;
	}


    interface IAPI
    {
        string hello(int number, string str);
    }

    auto api = new AutoInterfaceImpl!(IAPI, returnString)();


	writeln(api.hello(42, "foo"));


.. code-block::

	hello:
        number(int) = 42
        str(string) = foo
