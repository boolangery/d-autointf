import std.stdio;
import autointf;


class AutoJsonRpc(I) : I
{
    private int id;

    private ReturnType!Func executeMethod(alias Func, ARGS...)(ARGS args)
    {
        import std.traits;
        import std.array : join;
        import std.conv : to;

        // retrieve some compile time informations
        alias RT    = ReturnType!Func;
        alias PTT   = ParameterTypeTuple!Func;
        enum  Name  = __traits(identifier, Func);

        string[] params;
        foreach (i, PT; PTT)
            params ~= to!string(args[i]);

        return `{"jsonrpc": "2.0", "method": "` ~ Name ~ `", "params": [`
            ~ params.join(",") ~ `], "id": ` ~ (id++).to!string() ~ "}";
    }

    mixin(autoImplementMethods!(I, executeMethod)());
}


interface IAPI
{
    string helloWorld(int number, string str);

    @noAutoImplement()
    final string foo() { return "foo"; }
}

void main()
{
	auto api = new AutoJsonRpc!IAPI();

	writeln(api.helloWorld(42, "foo"));
	// > {"jsonrpc": "2.0", "method": "helloWorld", "params": [42,foo], "id": 0}

	writeln(api.foo());
	// > foo
}
