/* Digital Mars DMDScript source code.
 * Copyright (c) 2000-2002 by Chromium Communications
 * D version Copyright (c) 2004-2010 by Digital Mars
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 * written by Walter Bright
 * http://www.digitalmars.com
 *
 * DMDScript is implemented in the D Programming Language,
 * http://www.digitalmars.com/d/
 *
 * For a C++ implementation of DMDScript, including COM support, see
 * http://www.digitalmars.com/dscript/cppscript.html
 */

module dmdscript.ddeclaredfunction;

import std.stdio;
import std.c.stdlib;

import dmdscript.script;
import dmdscript.dobject;
import dmdscript.dfunction;
import dmdscript.darguments;
import dmdscript.opcodes;
import dmdscript.ir;
import dmdscript.identifier;
import dmdscript.value;
import dmdscript.functiondefinition;
import dmdscript.text;
import dmdscript.property;

/* ========================== DdeclaredFunction ================== */

class DdeclaredFunction : Dfunction
{
    FunctionDefinition fd;

    this(FunctionDefinition fd)
    {
        super(fd.parameters.length, Dfunction.getPrototype());
        assert(Dfunction.getPrototype());
        assert(internal_prototype);
        this.fd = fd;

        Dobject o;

        // ECMA 3 13.2
        o = new Dobject(Dobject.getPrototype());        // step 9
        Put(TEXT_prototype, o, DontEnum);               // step 11
        o.Put(TEXT_constructor, this, DontEnum);        // step 10
    }

    void *Call(CallContext *cc, Dobject othis, Value* ret, Value[] arglist)
    {
        // 1. Create activation object per ECMA 10.1.6
        // 2. Instantiate function variables as properties of
        //    activation object
        // 3. The 'this' value is the activation object

        Dobject actobj;         // activation object
        Darguments args;
        Value[] locals;
        uint i;
        void *result;

        //writefln("DdeclaredFunction.Call() '%s'", toString());
        //writefln("this.scopex.length = %d", this.scopex.length);
        //writefln("\tinstantiate(this = %x, fd = %x)", cast(uint)cast(void*)this, cast(uint)cast(void*)fd);

        // if it's an empty function, just return
        if (fd.code[0].opcode == IRret)
        {
            return null;
        }

        // Generate the activation object
        // ECMA v3 10.1.6
        actobj = new Dobject(null);

        // Instantiate the parameters
        {
            uint a = 0;
            foreach (Identifier* p; fd.parameters)
            {
                Value* v = (a < arglist.length) ? &arglist[a++] : &vundefined;
                actobj.Put(p.toString(), v, DontDelete);
            }
        }

        // Generate the Arguments Object
        // ECMA v3 10.1.8
        args = new Darguments(cc.caller, this, actobj, fd.parameters, arglist);

        actobj.Put(TEXT_arguments, args, DontDelete);

        // The following is not specified by ECMA, but seems to be supported
        // by jscript. The url www.grannymail.com has the following code
        // which looks broken to me but works in jscript:
        //
        //          function MakeArray() {
        //            this.length = MakeArray.arguments.length
        //            for (var i = 0; i < this.length; i++)
        //                this[i+1] = arguments[i]
        //          }
        //          var cardpic = new MakeArray("LL","AP","BA","MB","FH","AW","CW","CV","DZ");
        Put(TEXT_arguments, args, DontDelete);          // make grannymail bug work

        auto scoperootsave = cc.scoperoot;

        /* If calling a nested function, need to increase scoperoot
         */
        if (fd.enclosingFunction == cc.callerf)
        {   assert(cc.scoperoot < cc.scopex.length);
            cc.scoperoot++;
        }
        else
        {
            auto df = cast(DdeclaredFunction)cc.caller;
            if (df && !fd.isanonymous)
            {
                version (none)
                {
                    writefln("current nestDepth = %d, calling %d, cc.scopex.length = %d",
                            df.fd.nestDepth,
                            fd.nestDepth,
                            cc.scopex.length);
                }
                int diff = df.fd.nestDepth - fd.nestDepth;
                if (diff > 0)
                {   if (diff >= cc.scoperoot)
                        writefln("diff %s cc.scoperoot %s", diff, cc.scoperoot);
                    else
                        cc.scoperoot -= diff;
                    assert(cc.scoperoot >= 1);
                }
            }
        }

        Dobject[] scopesave = cc.scopex;

        Dobject[] scopex;
        //scopex = cc.scopex[0 .. cc.scoperoot].dup;
        scopex = this.scopex.dup;
        if (scopex.length == 0)
        {   this.scopex = cc.scopex[0 .. cc.scoperoot];
            scopex = this.scopex.dup;
        }
        scopex ~= actobj;

        fd.instantiate(scopex, actobj, DontDelete);

        cc.scopex = scopex;
        Dobject variablesave = cc.variable;
        cc.variable = actobj;
        auto callersave = cc.caller;
        cc.caller = this;
        auto callerfsave = cc.callerf;
        cc.callerf = fd;

        Value[] p1;
        Value* v;
        if (fd.nlocals < 128)
            v = cast(Value*) alloca(fd.nlocals * Value.sizeof);
        if (v)
            locals = v[0 .. fd.nlocals];
        else
        {
            p1 = new Value[fd.nlocals];
            locals = p1;
        }

        result = IR.call(cc, othis, fd.code, ret, locals.ptr);

        delete p1;

        cc.callerf = callerfsave;
        cc.caller = callersave;
        cc.variable = variablesave;
        cc.scopex = scopesave;
        cc.scoperoot = scoperootsave;

        // Remove the arguments object
        //Value* v;
        //v=Get(TEXT_arguments);
        //writef("1v = %x, %s, v.object = %x\n", v, v.getType(), v.object);
        Put(TEXT_arguments, &vundefined, 0);
        //actobj.Put(TEXT_arguments, &vundefined, 0);

    version (none)
    {
        writef("args = %x, actobj = %x\n", args, actobj);
        v=Get(TEXT_arguments);
        writef("2v = %x, %s, v.object = %x\n", v, v.getType(), v.object);
        v.object = null;

        {
            uint *p = cast(uint *)0x40a49a80;
            uint i;
            for (i = 0; i < 16; i++)
            {
                writef("p[%x] = %x\n", &p[i], p[i]);
            }
        }
    }

        return result;
    }

    void *Construct(CallContext *cc, Value *ret, Value[] arglist)
    {
        // ECMA 3 13.2.2
        Dobject othis;
        Dobject proto;
        Value* v;
        void *result;

        v = Get(TEXT_prototype);
        if (v.isPrimitive())
            proto = Dobject.getPrototype();
        else
            proto = v.toObject();
        othis = new Dobject(proto);
        result = Call(cc, othis, ret, arglist);
        if (!result)
        {
            if (ret.isPrimitive())
                ret.putVobject(othis);
        }
        return result;
    }

    d_string toString()
    {
        d_string s;

        //writef("DdeclaredFunction.toString()\n");
        fd.toBuffer(s);
        return s;
    }
}


