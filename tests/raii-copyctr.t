require "terralibext"  --load 'terralibext' to enable raii
--[[
    We need that direct initialization
        var a : A = b
    yields the same result as
        var a : A
        a = b
    If 'b' is a variable or a literal (something with a value) and the user has
    implemented the right copy-assignment 'A.methods.__copy' then the copy
    should be performed using this method.
--]]

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end


local test = require("test")
local io = terralib.includec("stdio.h")

struct A{
    data : int
}

A.methods.__init = terra(self : &A)
    io.printf("__init: calling initializer.\n")
    self.data = 1
end

A.methods.__dtor = terra(self : &A)
    io.printf("__dtor: calling destructor.\n")
    self.data = -1
end

A.methods.__copy = terra(from : &A, to : &A)
    io.printf("__copy: calling copy assignment {&A, &A} -> {}.\n")
    to.data = from.data + 1
end

printtestheader("raii-copyctr.t - copy-construction")

terra test1()
    var a : A           --__init -> a.data = 1
    var aa = a          --__init + __copy -> a.data = 2
    return aa.data
end
test.eq(test1(), 2)


printtestheader("raii-copyctr.t - copy-construction with generated __ctor")

--since A is managed, an __init, __dtor, and __copy will
--be generated
struct B{
    data : A
}
B.generate_initializers = true

terra test2()
    var a : A           --__init -> a.data = 1
    var b = B{a}        --__init + copy assignment --> b.data.data = 2
    return b.data.data
end
test2:printpretty()
test.eq(test2(), 2)


printtestheader("raii-copyctr.t - copy-construction in passing parameters by value to function")

--passing by value, so copy-assignment is performed on both 'a' and 'b'
--increasing 'a.data' and 'b.data' by one
terra myfun(a : A, b : A)
    return a.data + b.data
end

terra test3()
    var a : A --a.data = 1
    var b : A --b.data = 1
    return myfun(a, b) --copy-assignment is performed for 'a' and 'b', so myfun returns 4
end
test.eq(test3(), 4)