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
private enum isEnabledMethod(alias M) = !hasUDA!(M, NoAutoImplementMethod);

/// Base class for creating a context conserved during the invocation process.
class UserContext
{
}

struct SubInterface
{

}

/// Provides all necessary informations to implement an automated interface or class.
/// inspired by /web/vibe/web/internal/rest/common.d
struct InterfaceInfo(T) if (is(T == class) || is(T == interface))
{
@safe:

    import std.meta : Filter;
    import std.traits : FunctionTypeOf, InterfacesTuple, MemberFunctionsTuple,
        ParameterIdentifierTuple, ParameterStorageClass,
        ParameterStorageClassTuple, ParameterTypeTuple, ReturnType;
    import std.typetuple : TypeTuple;
    import vibe.internal.meta.funcattr : IsAttributedParameter;
    import vibe.internal.meta.traits : derivedMethod;
    import vibe.internal.meta.uda;

    // determine the implementation interface I and check for validation errors
    alias BaseInterfaces = InterfacesTuple!T;

    // some static checks
    static assert(BaseInterfaces.length > 0 || is(T == interface),
        "Cannot get interface infos for type '" ~ T.stringof ~ "' because it doesn't implement an interface");
    static if (BaseInterfaces.length > 1)
        pragma(msg, "Type '" ~ T.stringof
            ~ "' implements more than one interface: make sure the one describing the auto interface is the first one");

    // alias the base interface
    static if (is(T == interface))
        alias I = T;
    else
        alias I = BaseInterfaces[0];

    /// The name of each interface member (Runtime).
    enum memberNames = [__traits(allMembers, I)];

    /// Aliases to all interface methods (Compile-time).
    alias Members = GetMembers!();

    /** Aliases for each method (Compile-time).
    This tuple has the same number of entries as `methods`. */
    alias Methods = GetMethods!();

    /// Number of methods (Runtime).
    enum methodCount = Methods.length;

    /** Information about each route (Runtime).
    This array has the same number of fields as `RouteFunctions`. */
    MethodInfo[methodCount] methods;

    /// Static information about each route (Compile-time).
    static if (methodCount)
        static const StaticMethodInfo[methodCount] staticMethods = computeStaticRoutes();
    else
        static const StaticMethodInfo[0] staticMethods;

    /// Fills the struct with information.
    this(int dummy)
    {
        computeMethods();
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

    private template GetMembers()
    {
        template Impl(size_t idx)
        {
            static if (idx < memberNames.length)
            {
                enum name = memberNames[idx];
                static if (name.length != 0)
                    alias Impl = TypeTuple!(MemberFunctionsTuple!(I, name), Impl!(idx + 1));
                else
                    alias Impl = Impl!(idx + 1);
            }
            else
                alias Impl = TypeTuple!();
        }

        alias GetMembers = Impl!0;
    }

    private template GetMethods()
    {
        template Impl(size_t idx)
        {
            static if (idx < Members.length)
            {
                alias F = Members[idx];
                alias SI = SubInterfaceType!F;
                static if (is(SI == void) && isEnabledMethod!F)
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
}

///
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

    alias Info = InterfaceInfo!IAPI; // Compile-time infos
    auto info = new Info(0); // Runtime infos

    // Runtime infos
    assert(info.memberNames.length == 2);
    assert(info.memberNames[0] == "hello");
    assert(info.memberNames[1] == "disabledMethod");
    assert(info.methodCount == 1 );
    assert(info.methods.length == 1);
    assert(info.methods[0].name == "hello");
    assert(info.methods[0].parameters.length == 1);
    assert(info.methods[0].parameters[0].name == "number");

    // Compile time
    static assert(Info.Members.length == 2);
    static assert(Info.Methods.length == 1);

    static assert(Info.staticMethods.length == 1);
    static assert(Info.staticMethods[0].name == "hello");
    static assert(Info.staticMethods[0].parameters.length == 1);
    static assert(Info.staticMethods[0].parameters[0].name == "number");
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

string autoImplementMethods(I, alias ExecuteMethod)()
{
    import std.array : join;
    import std.string : format;
    import std.traits : ParameterIdentifierTuple;

    alias Info = InterfaceInfo!I;

    // add required import
    string ret = q{
        import vibe.internal.meta.codegen : CloneFunction;
    };

    // generate method implementation
    foreach (i, F; Info.Methods)
    {
        alias ParamNames = ParameterIdentifierTuple!F;

        static if (ParamNames.length == 0)
            enum pnames = "";
        else
            enum pnames = [ParamNames].join(", ");

        ret ~= q{
            mixin CloneFunction!(%3$s, q{
                return %2$s!(%3$s)(%1$s);
            }, true);
        }.format(pnames, __traits(identifier, ExecuteMethod), __traits(identifier, F));
    }

    return ret;
}

unittest
{
    class AutoFunctionName(I) : I
    {
        private ReturnType!Func executeMethod(alias Func, ARGS...)(ARGS arg)
        {
            import std.traits;
            import std.conv : to;

            // retrieve some compile time informations
            alias RT = ReturnType!Func;
            alias PTT = ParameterTypeTuple!Func;

            string ret;

            foreach (i, PT; PTT)
            {
                ret ~= to!string(arg[i]);
            }

            return __traits(identifier, Func) ~ ret;
        }

        mixin(autoImplementMethods!(I, executeMethod));
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
        @("foo") string hello(int number, string str);

        string helloWorld();
    }

    auto api = new AutoFunctionName!IAPI();

    assert(api.hello(42, "foo") == "hello42foo");
    assert(api.helloWorld() == "helloWorld");
    assert(api.getNumber(12) == "getNumber12");
}
