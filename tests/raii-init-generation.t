require "terralibext"  --load 'terralibext' to enable raii

local test = require("test")

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

ninitcalls = global(int,`0)

terra getninitcalls()
    return ninitcalls
end

local struct A {
    data : int
}

terra A:__init()
    self.data = 1
    ninitcalls = ninitcalls + 1
end

local struct B{
    a : A
    b : &A
}

local struct C{
    a : A
    b : B
    p : &int
    i : int
    z : int[3]
    q : A[2]
    v : bool
}

terralib.ext.addmissing.__init(C)

local c = global(C)
terra cinit()
    c:__init()
end
cinit()

terra geta() return c.a.data end
terra getb0() return c.b.a.data end
terra getb1() return c.b.b end
terra getp() return c.p end
terra geti() return c.i end
terra getz(i : int) return c.z[i] end
terra getq(i : int) return c.q[i].data end
terra getv() return c.v end

printtestheader("raii-init.t - testing generation of __init")

test.eq(geta(), 1)
test.eq(getb0(), 1)
test.eq(getb1(), nil)
test.eq(getp(), nil)
test.eq(geti(), 0)
test.eq(getz(0), 0)
test.eq(getz(1), 0)
test.eq(getz(2), 0)
test.eq(getq(0), 1)
test.eq(getq(1), 1)
test.eq(getv(), false)


printtestheader("raii-init.t - testing generation of array initializer")

terra main()
    ninitcalls = 0
    var a : A[4]
    return getninitcalls()
end
test.eq(main(), 4)