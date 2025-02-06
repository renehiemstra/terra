require "terralibext"
local test = require "test"

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

printtestheader("range.t - integer, lvalue, unit-step")
terra test0()
    var i = 2:6
    var s = 0
    for ii in i do
        s = s + ii
    end
    return s
end
test.eq(test0(), 14) --2+3+4+5 = 14

printtestheader("range.t - integer, rvalue, unit-step")
terra test1()
    var s = 0
    for ii in 2:6 do
        s = s + ii
    end
    return s
end
test.eq(test1(), 14) --2+3+4+5 = 14

printtestheader("range.t - double, lvalue, unit-step")
terra test2()
    var i = 2.:6.
    var s = 0.
    for ii in i do
        s = s + ii
    end
    return s
end
test.eq(test2(), 14) --2+3+4+5 = 14

printtestheader("range.t - double, rvalue, unit-step")
terra test3()
    var s = 0.
    for ii in 2.:6. do
        s = s + ii
    end
    return s
end
test.eq(test3(), 14) --2+3+4+5 = 14

printtestheader("range.t - integer, lvalue, custom-step")
terra test4()
    var i = 2:2:8
    var s = 0
    for ii in i do
        s = s + ii
    end
    return s
end
test.eq(test4(), 12) --2+4+6 = 12

printtestheader("range.t - integer, rvalue, custom-step")
terra test5()
    var s = 0
    for ii in 2:2:8 do
        s = s + ii
    end
    return s
end
test.eq(test5(), 12) --2+4+6 = 12

--double, lvalue, custom-step
printtestheader("range.t - double, lvalue, custom-step")
terra test6()
    var i = 2.:2.:8.
    var s = 0.
    for ii in i do
        s = s + ii
    end
    return s
end
test.eq(test6(), 12) --2+4+6 = 12

--double, rvalue, custom-step
printtestheader("range.t - double, rvalue, custom-step")
terra test7()
    var s = 0.
    for ii in 2.:2.:8. do
        s = s + ii
    end
    return s
end
test.eq(test7(), 12) --2+4+6 = 12