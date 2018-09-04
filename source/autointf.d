/**
	Some tools to help to auto-generate interface implementation.

	Copyright: © 2018 Eliott Dumeix
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module autointf;

import std.traits : hasUDA;
import vibe.internal.meta.uda : onlyAsUda;

/// Methods marked with this attribute will not be auto implemented.
package struct NoAutoImplementMethod
{
}

NoAutoImplementMethod noAutoImplement() @safe
{
    if (!__ctfe)
        assert(false, onlyAsUda!__FUNCTION__);
    return NoAutoImplementMethod();
}

/// attributes utils
private enum isDisabledMethod(alias M) = !hasUDA!(M, NoAutoImplementMethod);

/// Base class for creating a context conserved during the invocation process.
class UserContext
{
}

struct SubInterface
{

}

/// Provides all necessary informations to implement an automated interface or class.
/// inspired by /web/vibe/web/internal/rest/common.d
struct InterfaceInfo(T)
        if (is(T == class) || is(T == interface))
{
@safe:

    import std.meta : anySatisfy, Filter;
    import std.traits : FunctionTypeOf, InterfacesTuple, MemberFunctionsTuple,
        ParameterIdentifierTuple, ParameterStorageClass,
        ParameterStorageClassTuple, ParameterTypeTuple, ReturnType;
    import std.typetuple : TypeTuple;
    import vibe.internal.meta.funcattr : IsAttributedParameter;
    import vibe.internal.meta.traits : derivedMethod;
    import vibe.internal.meta.uda;

    // determine the implementation interface I and check for validation errors
    private alias BaseInterfaces = InterfacesTuple!T;
    static assert(BaseInterfaces.length > 0 || is(T == interface),
            "Cannot register type '" ~ T.stringof ~ "' because it doesn't implement an interface");
    static if (BaseInterfaces.length > 1)
        pragma(msg, "Type '" ~ T.stringof
                ~ "' implements more than one interface: make sure the one describing the auto interface is the first one");

    // alias the base interface
    static if (is(T == interface))
        alias I = T;
    else
        alias I = BaseInterfaces[0];

    /// Get interface attributes
    enum attributes = __traits(getAttributes, T);

    /// The name of each interface member
    enum memberNames = [__traits(allMembers, I)];

    /// Aliases to all interface methods
    alias AllMethods = GetAllMethods!();

    /** Aliases for each route method
		This tuple has the same number of entries as `routes`.
	*/
    alias Methods = GetMethods!();

    enum methodCount = Methods.length;

    /** Information about each route
		This array has the same number of fields as `RouteFunctions`
	*/
    MethodInfo[methodCount] methods;

    /// Static (compile-time) information about each route
    static if (methodCount)
        static const StaticMethodInfo[methodCount] staticMethods = computeStaticRoutes();
    else
        static const StaticMethodInfo[0] staticMethods;

    /** Aliases for each sub interface method
		This array has the same number of entries as `subInterfaces` and
		`SubInterfaceTypes`.
	*/
    alias SubInterfaceFunctions = getSubInterfaceFunctions!();

    /** The type of each sub interface
		This array has the same number of entries as `subInterfaces` and
		`SubInterfaceFunctions`.
	*/
    alias SubInterfaceTypes = GetSubInterfaceTypes!();

    enum subInterfaceCount = SubInterfaceFunctions.length;

    /** Information about sub interfaces
		This array has the same number of entries as `SubInterfaceFunctions` and
		`SubInterfaceTypes`.
	*/
    SubInterface[subInterfaceCount] subInterfaces;

    /** Fills the struct with information.
		Params:
			settings = Optional settings object.
	*/
    this(int dummy)
    {
        computeMethods();
        computeSubInterfaces();
    }

    // copying this struct is costly, so we forbid it
    @disable this(this);

    private void computeMethods()
    {
        import std.algorithm.searching : any;

        foreach (si, RF; Methods)
        {
            enum smethod = staticMethods[si];

            MethodInfo route;
            route.name = smethod.name;

            route.parameters.length = smethod.parameters.length;

            bool prefix_id = false;

            alias PT = ParameterTypeTuple!RF;
            foreach (i, _; PT)
            {
                enum sparam = smethod.parameters[i];
                ParameterInfo pi;
                pi.name = sparam.name;

                route.parameters[i] = pi;
            }

            methods[si] = route;
        }
    }

    private void computeSubInterfaces()
    {
        foreach (i, func; SubInterfaceFunctions)
        {
            enum meta = extractHTTPMethodAndName!(func, false)();

            static if (meta.hadPathUDA)
                string url = meta.url;
            else
                string url = computeDefaultPath!func(meta.url);

            SubInterface si;
            si.context = context.dup;
            si.context.baseURL = URL(concatURL(this.baseURL, url, true));
            subInterfaces[i] = si;
        }

        assert(subInterfaces.length == SubInterfaceFunctions.length);
    }

    // ////////////////////////////////////////////////////////////////////////
    // compile time methods
    // ////////////////////////////////////////////////////////////////////////
    private template SubInterfaceType(alias F)
    {
        import std.traits : ReturnType, isInstanceOf;

        alias RT = ReturnType!F;
        static if (is(RT == interface))
            alias SubInterfaceType = RT;
        else
            alias SubInterfaceType = void;
    }

    private template GetAllMethods()
    {
        template Impl(size_t idx)
        {
            static if (idx < memberNames.length)
            {
                enum name = memberNames[idx];
                static if (name.length != 0)
                    alias Impl = TypeTuple!(Filter!(isDisabledMethod,
                            MemberFunctionsTuple!(I, name)), Impl!(idx + 1));
                else
                    alias Impl = Impl!(idx + 1);
            }
            else
                alias Impl = TypeTuple!();
        }

        alias GetAllMethods = Impl!0;
    }

    private template GetMethods()
    {
        template Impl(size_t idx)
        {
            static if (idx < AllMethods.length)
            {
                alias F = AllMethods[idx];
                alias SI = SubInterfaceType!F;
                static if (is(SI == void))
                    alias Impl = TypeTuple!(F, Impl!(idx + 1));
                else
                    alias Impl = Impl!(idx + 1);
            }
            else
                alias Impl = TypeTuple!();
        }

        alias GetMethods = Impl!0;
    }

    private static StaticMethodInfo[methodCount] computeStaticRoutes()
    {
        static import std.traits;
        import std.algorithm.searching : any, count;
        import std.algorithm : countUntil;
        import std.meta : AliasSeq;

        assert(__ctfe);

        StaticMethodInfo[methodCount] ret;

        foreach (fi, func; Methods)
        {
            StaticMethodInfo sroute;
            sroute.name = __traits(identifier, func);

            static if (!is(T == I))
                alias cfunc = derivedMethod!(T, func);
            else
                alias cfunc = func;

            alias FuncType = FunctionTypeOf!func;
            alias ParameterTypes = ParameterTypeTuple!FuncType;
            alias ReturnType = std.traits.ReturnType!FuncType;
            enum parameterNames = [ParameterIdentifierTuple!func];

            // get some meta
            enum name = __traits(identifier, func);

            sroute.name = name;

            foreach (i, PT; ParameterTypes)
            {
                enum pname = parameterNames[i];

                // Comparison template for anySatisfy
                // template Cmp(WebParamAttribute attr) { enum Cmp = (attr.identifier == ParamNames[i]); }
                // alias CompareParamName = GenCmp!("Loop"~func.mangleof, i, parameterNames[i]);
                // mixin(CompareParamName.Decl);
                StaticParameterInfo pi;
                pi.name = parameterNames[i];

                // determine in/out storage class
                enum SC = ParameterStorageClassTuple!func[i];
                static assert(!(SC & ParameterStorageClass.out_));

                sroute.parameters ~= pi;
            }

            ret[fi] = sroute;
        }

        return ret;
    }

    private template getSubInterfaceFunctions()
    {
        template Impl(size_t idx)
        {
            static if (idx < AllMethods.length)
            {
                alias SI = SubInterfaceType!(AllMethods[idx]);
                static if (!is(SI == void))
                {
                    alias Impl = TypeTuple!(AllMethods[idx], Impl!(idx + 1));
                }
                else
                {
                    alias Impl = Impl!(idx + 1);
                }
            }
            else
                alias Impl = TypeTuple!();
        }

        alias getSubInterfaceFunctions = Impl!0;
    }

    private template GetSubInterfaceTypes()
    {
        template Impl(size_t idx)
        {
            static if (idx < AllMethods.length)
            {
                alias SI = SubInterfaceType!(AllMethods[idx]);
                static if (!is(SI == void))
                {
                    alias Impl = TypeTuple!(SI, Impl!(idx + 1));
                }
                else
                {
                    alias Impl = Impl!(idx + 1);
                }
            }
            else
                alias Impl = TypeTuple!();
        }

        alias GetSubInterfaceTypes = Impl!0;
    }
}

/// Static informations about a method.
struct StaticMethodInfo
{
    string name; // D name of the function
    StaticParameterInfo[] parameters;
}

/// Static informations about a method parameter.
struct StaticParameterInfo
{
    string name;
}

/// Informations about a method.
struct MethodInfo
{
    string name; // D name of the function
    ParameterInfo[] parameters;
}

/// Informations about a method parameter.
struct ParameterInfo
{
    string name;
}

unittest
{
    import std.typecons : tuple;
    import std.traits;

    @("api")
    interface IAPI
    {
        @("value")
        string hello(int number);

        @noAutoImplement()
        void disabledMethod();
    }

    alias info = InterfaceInfo!IAPI;

    static assert(info.attributes.length == 1);
    static assert(info.attributes[0] == "api");

    static assert(info.memberNames.length == 2);
    static assert(info.memberNames[0] == "hello");
    static assert(info.memberNames[1] == "disabledMethod");

    static assert(info.Methods.length == 1);

    alias Func = info.Methods[0];
    alias RT = ReturnType!Func;
    alias PTT = ParameterTypeTuple!Func;

    static assert(is(RT == string));
    static assert(PTT.length == 1);
    static assert(is(PTT[0] == int));
}

string autoImplementMethods(I)(string globalMethodName = "executeMethod")
{
    import std.array : join;
    import std.string : format;
    import std.traits : fullyQualifiedName, isInstanceOf,
        ParameterIdentifierTuple;

    alias Info = InterfaceInfo!I;

    string ret = q{
		import vibe.internal.meta.codegen : CloneFunction;

		private alias __Info = InterfaceInfo!I;
		private InterfaceInfo!I* __infos = new __Info(0);
	};

    // generate sub interface methods
    foreach (i, SI; Info.SubInterfaceTypes)
    {
        alias F = Info.SubInterfaceFunctions[i];
        alias RT = ReturnType!F;
        alias ParamNames = ParameterIdentifierTuple!F;
        static if (ParamNames.length == 0)
            enum pnames = "";
        else
            enum pnames = ", " ~ [ParamNames].join(", ");
        static if (isInstanceOf!(Collection, RT))
        {
            ret ~= q{
					mixin CloneFunction!(__Info.SubInterfaceFunctions[%1$s], q{
						return Collection!(%2$s)(m_subInterfaces[%1$s]%3$s);
					});
				}.format(i, fullyQualifiedName!SI, pnames);
        }
        else
        {
            ret ~= q{
					mixin CloneFunction!(__Info.SubInterfaceFunctions[%1$s], q{
						return m_subInterfaces[%1$s];
					});
				}.format(i);
        }
    }

    // generate route methods
    foreach (i, F; Info.Methods)
    {
        alias ParamNames = ParameterIdentifierTuple!F;
        static if (ParamNames.length == 0)
            enum pnames = "";
        else
            enum pnames = [ParamNames].join(", ");

        ret ~= q{
			mixin CloneFunction!(__Info.Methods[%1$s], q{
				import std.traits : ReturnType;
        		alias RT = ReturnType!(__Info.Methods[%1$s]);
				return %3$s!(I, RT, %1$s)(*__infos, %2$s);
			});
		}.format(i, pnames, globalMethodName);
    }

    return ret;
}


unittest
{
    class AutoFunctionName(I) : I
    {
        RT executeMethod(I, RT, int n, ARGS...)(ref InterfaceInfo!I info, ARGS arg)
        {
            import std.traits;
            import std.conv : to;

            // retrieve some compile time informations
            alias Func = info.Methods[n];
            alias RT = ReturnType!Func;
            alias PTT = ParameterTypeTuple!Func;
            auto route = info.methods[n];

            string ret;

            foreach (i, PT; PTT)
            {
                ret ~= to!string(arg[i]);
            }

            return route.name ~ ret;
        }

        mixin(autoImplementMethods!I());
    }

    interface ISubAPi
    {
        string getNumber(int n);

        @noAutoImplement()
        final string foo()
        {
            return "foo";
        }
    }

    interface IAPI : ISubAPi
    {
        string hello(int number, string str);

        string helloWorld();
    }

    auto api = new AutoFunctionName!IAPI();

    assert(api.hello(42, "foo") == "hello42foo");
    assert(api.helloWorld() == "helloWorld");
    assert(api.getNumber(12) == "getNumber12");

}
