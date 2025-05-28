local addmissinginit, addmissingdtor, addmissingcopy, addmissingmove

local function ismanaged(T)
    if T:isstruct() then
        addmissingdtor(T)
        if T.methods.__dtor then
            addmissinginit(T)
            return true
        end
    elseif T:isarray() then
        return ismanaged(T.type)
    end
    return false
end

local function hasmanagedfields(V)
    for i,e in ipairs(V:getentries()) do
        if ismanaged(e.type) then
            return true
        end
    end
    return false
end

local function hasmethod(W, method)
    if W:isstruct() then return W.methods[method]
    elseif W:isarray() then return hasmethod(W.type, method)
    else return false end
end

local function checkuniontypelist(t)
    assert(terralib.israwlist(t) and #t > 0, "CompileError: expected a union type.")
    assert(t[1].type, "CompileError: expected a valid type.")
    local size = sizeof(t[1].type)
    for i,e in ipairs(t) do
        local T = e.type
        if T then
            assert(not ismanaged(T), "CompileError: managed types not allowed in union type.")
            assert(sizeof(T) == size, "CompileError: expected union types to have identical size.")
        else
            error("CompileError: expected a valid type.")
        end
    end
end

--__create a missing __init for 'T' and all its entries
function addmissinginit(T)
    local generated = false
    local runinit
    runinit = macro(function(receiver)
        local V = receiver:gettype()
        if V:isstruct() then
            addmissinginit(V)
            if hasmethod(V, "__init") then
                generated = true
                return `receiver:__init()
            end
        elseif V:isarray() then
            addmissinginit(V.type)
            if hasmethod(V, "__init") then
                generated = true
                return quote
                    for i = 0, V.N do
                        runinit(receiver[i])
                    end
                end
            end
        elseif V:ispointer() then
            generated = true
            return quote receiver = nil end
        end
        return quote end
    end)
    --generate __init method
    if T:isstruct() and not T.methods.__init and not T.__init_generated then
        local imp = terra(self : &T)
            escape
                for i,e in ipairs(T:getentries()) do
                    if e.field then
                        --regular fields
                        emit quote runinit(self.[e.field]) end
                    else
                        --take care of 'union' types
                        checkuniontypelist(e)
                        emit quote runinit(self.[e[1].field]) end
                    end
                end
            end
        end
        --flag that `addmissinginit` already has been called
        T.__init_generated = true
        --only add implementation of __init and __init_generated if a non-trivial one was generated
        if generated then
            T.methods.__init_generated = imp
            T.methods.__init = T.methods.__init_generated
        end
    end
end

--generate an array initializer, recursively.
local generatearrayinitializer
generatearrayinitializer = terralib.memoize(function(V)
    assert(V:isarray())
    local T = V.type
    if T:isstruct() then
        addmissinginit(T)
        if T.methods.__init then
            return terra(array : &V)
                for i = 0, V.N do
                    (@array)[i]:__init()
                end
            end
        end
    elseif T:isarray() then
        local init = generatearrayinitializer(T)
        if init then
            return terra(array : &V)
                for i = 0, V.N do
                    init(&((@array)[i]))
                end
            end
        end
    end
end)

--__create a missing __dtor for 'T' and all its entries
function addmissingdtor(T)
    local generated = false
    local rundtor
    rundtor = macro(function(receiver)
        local V = receiver:gettype()
        if V:isstruct() then
            addmissingdtor(V)
            if hasmethod(V, "__dtor") then
                generated = true
                return `receiver:__dtor()
            end
        elseif V:isarray() then
            addmissingdtor(V.type)
            if hasmethod(V, "__dtor") then
                generated = true
                return quote
                    for i = 0, V.N do
                        rundtor(receiver[i])
                    end
                end
            end
        end
        return quote end
    end)
    --generate __dtor
    if T:isstruct() and not T.methods.__dtor and not T.__dtor_generated then
        local imp = terra(self : &T)
            escape
                for i,e in ipairs(T:getentries()) do
                    if e.field then
                        emit quote rundtor(self.[e.field]) end
                    end
                end
            end
        end
        --flag that `addmissingdtor` already has been called
        T.__dtor_generated = true
        --if non-trivial destructor code was actually generated then
        --set assign the implementation to '__dtor' and '__dtor_generated'
        if generated then
            T.methods.__dtor_generated = imp
            T.methods.__dtor = T.methods.__dtor_generated
        end
    end
end

--generate an array destructor, recursively
local generatearraydestructor
generatearraydestructor = terralib.memoize(function(V)
    assert(V:isarray())
    local T = V.type
    if T:isstruct() then
        addmissingdtor(T)
        if T.methods.__dtor then
            return terra(array : &V)
                for i = 0, V.N do
                    (@array)[i]:__dtor()
                end
            end
        end
    elseif T:isarray() then
        local dtor = generatearraydestructor(T)
        if dtor then
            return terra(array : &V)
                for i = 0, V.N do
                    dtor(&((@array)[i]))
                end
            end
        end
    end
end)

--create a missing __move for 'T' and all its entries
function addmissingmove(T)
    --macro for moveing data
    local runmove
    runmove = macro(function(from, to)
        local V = from:gettype()
        if V:isstruct() and ismanaged(V) then
            addmissingmove(V)
            --move will always be generated for a managed variable, so
            --we do a sanity check 
            assert(hasmethod(V, "__move"), "__move could not be generated.")
            return quote [V.methods.__move](&from, &to) end --__move is always generated, so no need for an if-here
        elseif V:isarray() then
            return quote
                for i = 0, V.N do
                    runmove(from[i], to[i])
                end
            end
        elseif V:ispointer() then
            return quote
                to = from           --regular bitcopy for unmanaged variables
                from = nil          --initialize old variables
            end
        else
            return quote
                to = from       --regular bitcopy for unmanaged variables
            end
        end
    end)
    --generate __move
    if T:isstruct() and ismanaged(T) and not T.methods.__move then
        if hasmanagedfields(T) then
            T.methods.__move_generated = terra(from : &T, to : &T)
                escape
                    for i,e in ipairs(T:getentries()) do
                        if e.field then
                            emit quote runmove(from.[e.field], to.[e.field]) end
                        else
                            checkuniontypelist(e)
                            emit quote runmove(from.[e[1].field], to.[e[1].field]) end
                        end
                    end
                end
            end
        else
            addmissinginit(T)
            T.methods.__move_generated = terra(from : &T, to : &T)
                to:__dtor()     --clear old resources of 'to', just-in-case
                escape
                    --copying field-by-field. otherwise the copy-constructor
                    --may be called
                    for i,e in ipairs(T:getentries()) do
                        if e.field then
                            emit quote to.[e.field] = from.[e.field] end
                        else
                            checkuniontypelist(e)
                            emit quote to.[e[1].field] = from.[e[1].field] end
                        end
                    end
                    if T.methods.__init then
                        emit quote from:__init() end   --re-initializing bits of 'from'
                    end
                end
            end
        end
        --the following flag will signal that addmissingmove(T) will not
        --attempt to generate 'T.methods.__move' twice
        T.methods.__move = T.methods.__move_generated
    end
end

--check if object is a pointer (not a function pointer) or has pointer
--fields or elements.
local function haspointers(T)
    if T:isstruct() then
        for i,e in ipairs(T:getentries()) do
            if e.type and haspointers(e.type) then
                return true
            end
        end
        return false
    elseif T:isarray() then
        return haspointers(T.type)
    elseif T:ispointer() and not T:ispointertofunction() then
        return true
    else
        return false
    end
end

--__create a missing __copy for 'T' and all its entries
--a type T is copyable if all its fields are copyable.
--a `field` is copyable if:
--      [1] `field` is a struct and implements a __copy or by induction it is copyable.
--      [2] `field` is a primitive type or a simd vector which is trivially copyable.
--      [3] `field` is an array of copyable objects.
--vice versa, a `field` is not copyable when it is a pointer (not a function pointer) or a struct that does not
--have a (generated) __copy or an array of objects that are not copyable.
function addmissingcopy(T)
    local generated = false --flag to check if actual copy-constructors are called
    local copyable = true  --flag to check if the type T is unambiguously copyable
    local runcopy
    runcopy = macro(function(from, to)
        local V = from:gettype()
        if V:isstruct() then
            addmissingcopy(V)
            if hasmethod(V, "__copy") then
                generated = true
                return quote
                    [V.methods.__copy](&from, &to)
                end
            else
                --bit-copies for unmanaged structs
                if not ismanaged(V) and not haspointers(V) then
                    return quote
                        to = from --perform a bitcopy
                    end
                else
                    --managed structs without (generated) __copy or unmanaged
                    --structs containing pointers are not copyable
                    copyable = false
                    return quote end
                end                
            end
        elseif V:isarray() then
            return quote
                for i = 0, V.N do
                    runcopy(from[i], to[i])
                end
            end
        elseif V:ispointer() and not V:ispointertofunction() then
            copyable = false --pointers are not copyable
            return quote end
        else
            return quote
                to = from --perform a bitcopy
            end
        end
    end)
    --generate a __copy
    if T:isstruct() and not T.methods.__copy and not T.__copy_generated then
        local imp = terra(from : &T, to : &T)
            escape
                for i,e in ipairs(T:getentries()) do
                    if e.field then
                        emit quote runcopy(from.[e.field], to.[e.field]) end
                    else
                        checkuniontypelist(e)
                        emit quote runcopy(from.[e[1].field], to.[e[1].field]) end
                    end
                end
            end
        end
        --flag that `addmissingdtor` already has been called
        T.__copy_generated = true
        --if non-trivial and valid copy-assignment code was actually generated then
        --set assign the implementation to '__copy' and '__copy_generated'
        if generated and copyable then
            T.methods.__copy_generated = imp
            T.methods.__copy = T.methods.__copy_generated
        end
    end
end

--generate an array destructor, recursively
local generatearraycopyormove
addmissing = {
        __init = addmissinginit,
        __dtor = addmissingdtor,
        __copy = addmissingcopy,
        __move = addmissingmove
}
generatearraycopyormove = terralib.memoize(function(V, copyormove)
    assert(V:isarray())
    local T = V.type
    if T:isstruct() then
        addmissing[copyormove](T)
        local method = T.methods[copyormove]
        if method then
            return terra(from : &V, to : &V)
                for i = 0, V.N do
                    method(&((@from)[i]), &((@to)[i]))
                end
            end
        end
    elseif T:isarray() then
        local method = generatearraycopyormove(T, copyormove)
        if method then
            return terra(from : &V, to : &V)
                for i = 0, V.N do
                    method(&((@from)[i]), &((@to)[i]))
                end
            end
        end
    end
end)

--__forward takes a value by reference and simply forwards it by reference,
--creating an rvalue
local function addmissingforward(T)
    if T:isstruct() then
        if T.methods.__forward then
            T.methods.__forward_generated = T.methods.__forward
            return
        end
        if not T.methods.__forward and not T.methods.__forward_generated then
            T.methods.__forward_generated = terra(self : &T)
                return self --simply forward the variable (turning it into an rvalue)
            end
            T.methods.__forward = T.methods.__forward_generated
            return
        end
    end
end

local function constructor(from, to)
    assert(from:isstruct(), tostring(from) .. " is not a valid struct.")
    assert(to:isstruct(), tostring(to) .. " is not a valid struct.")
    --get layout of structs
    local from_layout, to_layout = from:getlayout(), to:getlayout()
    --from here on we use 'T' for 'to' type
    local T = to
    --check input
    assert(#from_layout.entries <= #to_layout.entries, "number of arguments exceeds number of struct entries.")
    --add 'constructor' table
    if not T.constructor then T.constructor = {} end
    --extract symbols for the argument list
    local argumentlist, keys = terralib.newlist{}, terralib.newlist{}
    for i,entry in ipairs(from_layout.entries) do
        argumentlist:insert(symbol(entry.type))
        local offset = from.convertible == "tuple" and i - 1 or to_layout.keytoindex[entry.key]
        assert(offset, "structural cast invalid, result structure has no key ".. tostring(entry.key))
        keys:insert(to_layout.entries[offset+1].key)
    end
    --generate a constructor if it has not been generated before
    local sig = table.concat(keys, "+") --serialize keys to get a unique key
    if not T.constructor[sig] then
        local nargs = #argumentlist --number of function arguments
        addmissinginit(T) --add empty initializer
        --generate implementation
        T.constructor[sig] = terra([argumentlist])
            var v : T --initializer will be auto-generated
            escape
                for i=1,nargs do
                    local key, rhs = keys[i], argumentlist[i]
                    emit quote
                        v.[key] = __move__([rhs]) --__move constructor will be used for struct objects
                    end
                end
            end
            return v
        end
    end
    return T.constructor[sig]
end

--add definitions such that we can access them from terralib
terralib.ext = {
    addmissing = {
        __init = addmissinginit,
        __dtor = addmissingdtor,
        __copy = addmissingcopy,
        __move = addmissingmove,
        __forward = addmissingforward,
        arraydestructor = generatearraydestructor,
        arrayinitializer = generatearrayinitializer,
        arraycopyormove = generatearraycopyormove
    },
    constructor = constructor,
    ismanaged = ismanaged,
    hasmanagedfields = hasmanagedfields
}