require "terralibext"  --load 'terralibext' to enable raii

local test = require("test")

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

local struct A {
    x : int
    y : int
    z : int
    ptr : &int
}

terra A:__dtor()
    self.x = -1
    self.y = -1
    self.z = -1
    self.ptr = nil
end

printtestheader("partial initialization - input as tuple")

terra main()
    var a : A = A{1,2,3}
    if a.ptr == nil then
        return 1
    else
        return 2
    end
end
test.eq(main(), 1)

printtestheader("partial initialization - input as named struct")

terra main2()
    var a : A = A{y=2,z=3,x=1}
    if a.x==1 and a.y==2 and a.z==3 and a.ptr == nil then
        return true
    end
end
test.eq(main2(), true)

printtestheader("initialization - with move from other struct")

local struct B{
    a : A
}

terra main3()
    var a : A = A{y=2,z=3,x=1}
    a.ptr = &a.x
    var b : B = B{__move__(a)}
    if a.ptr==nil and b.a.ptr==&a.x then
        return true
    end
end
test.eq(main3(), true)