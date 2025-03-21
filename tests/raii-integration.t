require "terralibext"  --load 'terralibext' to enable raii

local test = require("test")
local C = terralib.includecstring[[
	#include <stdio.h>
	#include <stdlib.h>
    #include <string.h>
]]

local debug = {}

debug.error = macro(function(expr, msg)
    local tree = expr.tree
    local filename = tree.filename
    local linenumber = tree.linenumber
    local offset = tree.offset
    local loc = filename .. ":" .. linenumber .. "+" .. offset
    return quote
        terralib.debuginfo(filename, linenumber)
        C.printf("%s: %s\n", loc, msg)
        C.abort()
    end
end)

debug.assert = macro(function(condition, msg)
    local msg = msg or "assertion failed!"
    return quote
        if not condition then
            debug.error(condition, msg)
        end
    end
end)

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

--Implementation of a Dynamic Stack class that stores its data on the heap.
--the following RAII methods are implemented/generated
--__dtor (user implemented)
--__init (user implemented)
--__move (auto-generated)
--__copy (not implemented)
local DynamicStack = terralib.memoize(function(T)

    local struct Stack {
        data : &T
        size : int
        capacity : int
    }

    Stack.staticmethods = {}

    Stack.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or Stack.staticmethods[methodname]
    end

    terra Stack:__init()
        self.data = nil
        self.size = 0
        self.capacity = 0
    end

    terra Stack:__dtor()
        C.free(self.data)
        self:__init()
    end

    terra Stack:size()
        return self.size
    end

    terra Stack:capacity()
        return self.capacity
    end

    Stack.metamethods.__apply = macro(function(self, i)
        assert(i.type:isintegral(), "index should be an integer.")
        return quote
            debug.assert(i > -1 and i < self.size, "index exceeds dimensions of stack")
        in
            self.data[i]
        end
    end)

    Stack.staticmethods.new = terra(capacity : int)
        return Stack{data=[&T](C.malloc(capacity * sizeof(T))), capacity=capacity} --self.size is initialized to 0 automatically
    end

    terra Stack:realloc(capacity : int)
        self.data = [&T](C.realloc(self.data, capacity * sizeof(T)))
        self.capacity = capacity
    end

    terra Stack:push(v : T)
        if self.size == self.capacity then
            self:realloc(1 + 2 * self.capacity)
        end
        self.size = self.size + 1
        --if 'T' is managed then the resources need to be transfered into the stack
        --if 'T' is not managed then this defaults to an ordinary assignment
        self.data[self.size - 1] = __move__(v)
    end

    terra Stack:pop()
        if self.size > 0 then
            --if 'T' is managed then the resources need to be transfered out of the stack
            --if 'T' is not managed then this defaults to an ordinary assignment
            var tmp = __move__(self.data[self.size - 1])
            self.size = self.size - 1
            return tmp
        end
    end

    return Stack
end)

--Implementation of a Dynamic Vector class that stores its data on the heap.
--the following RAII methods are implemented/generated
--__dtor (user implemented)
--__init (user implemented)
--__move (auto-generated)
--__copy (not implemented)
local DynamicVector = terralib.memoize(function(T)

    local struct Vector {
        data : &T
        size : int
    }

    Vector.staticmethods = {}

    Vector.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or Vector.staticmethods[methodname]
    end

    terra Vector:__init()
        self.data = nil
        self.size = 0
    end

    terra Vector:__dtor()
        C.free(self.data)
        self.size = 0
    end

    terra Vector:size()
        return self.size
    end

    Vector.metamethods.__apply = macro(function(self, i)
        assert(i.type:isintegral(), "index should be an integer.")
        return quote
            debug.assert(i > -1 and i < self.size, "index exceeds dimensions of stack")
        in
            self.data[i]
        end
    end)

    Vector.staticmethods.new = terra(size : int)
        return Vector{[&T](C.malloc(size * sizeof(T))), size}
    end

    --enabling a move from a stack object to a vector object
    local Stack = DynamicStack(T)

    --the cast from a DynamicStack to a DynamicVector is implemented as a move.
    Vector.metamethods.__cast = function(from, to, exp)
        if from:ispointer() and from.type == Stack and to:ispointer() and to.type == Vector then
            return quote
                exp.capacity = 0
            in
                [&Vector](exp)
            end
        else
            error("ArgumentError: not able to cast " .. tostring(from) .. " to " .. tostring(to) .. ".")
        end
    end

    return Vector
end)

local QuadratureRule = terralib.memoize(function(T)

    local DVector = DynamicVector(T)

    local struct Quadrature{
        x : DVector
        w : DVector
    }

    Quadrature.staticmethods = {}

    Quadrature.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or Quadrature.staticmethods[methodname]
    end

    terra Quadrature:size()
        return self.x:size()
    end

    --Arguments are passed by value. Since `DVector` does not implement `__copy` the 
    --resources are moved into the function and into the struct.
    Quadrature.staticmethods.new = terra(x : DVector, w : DVector)
        return Quadrature{x=x, w=w}
    end

    Quadrature.metamethods.__apply = macro(function(self, i)
        assert(i.type:isintegral(), "index should be an integer.")
        return quote
            debug.assert(i > -1 and i < self.size, "index exceeds dimensions of stack")
        in
            {self.x(i), self.w(i)}
        end
    end)

    return Quadrature
end)

local DStack = DynamicStack(double)
local DVector = DynamicVector(double)
local Quadrule = QuadratureRule(double)

--Representative example:
--(1) We create a dynamic stack and start adding elements. The Stack
--will reallocate data when needed.
--(2) We transfer the dynamic stack into a dynamic vector. A dynamic vector
--has a fixed dynamic size and can not grow.
--(3) We use the dynamic vector in an aggregate data type that is used to double
--some more operations.
terra main()
    --fill the first stack
    var stack_x : DStack
    stack_x:push(1.0)
    stack_x:push(2.0)
    stack_x:push(3.0)
    stack_x:push(4.0)
    stack_x:push(5.0)

    --transfer to a vector (stack_x will become empty)
    var x : DVector = stack_x

    --check that stack_x is empty
    debug.assert(stack_x.data == nil and stack_x.size == 0 and stack_x.capacity == 0)

    --fill the second stack
    var stack_w : DStack
    stack_w:push(0.5)
    stack_w:push(1.0)
    stack_w:push(1.0)
    stack_w:push(1.0)
    stack_w:push(0.5)

    --transfer to a vector (stack_x will become empty)
    var w : DVector = stack_w
    --check that stack_w is empty
    debug.assert(stack_w.data == nil and stack_w.size == 0 and stack_w.capacity == 0)

    --store (x,w) in an aggregate datatype
    var q = Quadrule{x=x, w=w}
    --check that `x` and `w` are now empty
    debug.assert(x.data == nil and x.size == 0)
    debug.assert(w.data == nil and w.size == 0)

    return q:size()
end
print(main())
