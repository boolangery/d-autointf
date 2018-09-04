import std.stdio;
import autointf;


class AutoJsonRpc(I) : I
{
    private int id;

    private RT executeMethod(I, RT, int n, ARGS...)(ref InterfaceInfo!I info, ARGS args)
    {
        import std.traits;
        import std.array : join;
        import std.conv : to;

        // retrieve some compile time informations
        alias Func  = info.Methods[n];
        alias RT    = ReturnType!Func;
        alias PTT   = ParameterTypeTuple!Func;
        auto method = info.methods[n];

        string[] params;
        foreach (i, PT; PTT)
            params ~= to!string(args[i]);

        return `{"jsonrpc": "2.0", "method": "` ~ method.name ~ `", "params": [`
            ~ params.join(",") ~ `], "id": ` ~ (id++).to!string() ~ "}";
    }

    mixin(autoImplementMethods!I());
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
