local addmissinginit, addmissingdtor, addmissingcopy, addmissingmove

local function ismanaged(T)
    if not T:isstruct() then
        return false
    end
    addmissingdtor(T)
    if T.methods.__dtor then
        addmissinginit(T)
        return true
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

local runinit
runinit = macro(function(receiver)
    local V = receiver:gettype()
    if V:isstruct() then
        if not hasmethod(V, "__init") then
            addmissinginit(V)
        end
        return `receiver:__init()
    elseif V:isarray() then
        return quote
            for i = 0, V.N do
                runinit(receiver[i])
            end
        end
    elseif V:isvector() then
        return quote receiver = 0 end
    elseif V:isprimitive() then
        return quote receiver = [V](0) end
    elseif V:ispointer() then
        return quote receiver = nil end
    else
        error("case not implemented")
    end
end)

--__create a missing __init for 'T' and all its entries
function addmissinginit(T)
    if T:isstruct() then
        if not T.methods.__init then
            T.methods.__init = terra(self : &T)
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
            --flag that denotes that '__init' was generated rather than
            --implemented by the user
            T.methods.__init_generated = true
        end
    end
end

--generate an array destructor
local generatearrayinitializer = terralib.memoize(function(V)
    assert(V:isarray())
    local eltype = V.type
    if eltype:isstruct() then
        addmissinginit(eltype)
        if eltype.methods.__init then
            return terra(array : &V)
                for i = 0, V.N do
                    (@array)[i]:__init()
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
            if hasmethod(V.type, "__dtor") then
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
    if T:isstruct() then
        if not T.methods.__dtor and not T.methods.__dtor_generated then
            local imp = terra(self : &T)
                escape
                    for i,e in ipairs(T:getentries()) do
                        if e.field then
                            emit quote rundtor(self.[e.field]) end
                        end
                    end
                end
            end
            --the following flag will signal that addmissingdtor(T) will not
            --attempt to generate 'T.methods.__dtor' twice
            T.methods.__dtor_generated = true
            --if non-trivial destructor code was actually generated then
            --set assign the implementation to '__dtor'
            if generated then
                T.methods.__dtor = imp
            end
        end
    end
end

--generate an array destructor
local generatearraydestructor = terralib.memoize(function(V)
    assert(V:isarray())
    local eltype = V.type
    if eltype:isstruct() then
        addmissingdtor(eltype)
        if eltype.methods.__dtor then
            return terra(array : &V)
                for i = 0, V.N do
                    (@array)[i]:__dtor()
                end
            end
        end
    end
end)

--create a missing __move for 'T' and all its entries
function addmissingmove(T)
    local runmove
    runmove = macro(function(from, to)
        local V = from:gettype()
        if V:isstruct() and ismanaged(V) then
            addmissingmove(V)
            return quote [V.methods.__move](&from, &to) end --__move is always generated, so no need for an if-here
        elseif V:isarray() then
            return quote
                for i = 0, V.N do
                    runmove(from[i], to[i])
                end
            end
        else
            return quote
                to = from           --regular bitcopy for unmanaged variables
                runinit(from)       --initialize old variables
            end
        end
    end)

    if T:isstruct() and ismanaged(T) then
        if not T.methods.__move and not T.methods.__move_generated then
            if hasmanagedfields(T) then
                T.methods.__move = terra(from : &T, to : &T)
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
                T.methods.__move = terra(from : &T, to : &T)
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
                    end
                    from:__init()   --re-initializing bits of 'from'
                end
            end
            --the following flag will signal that addmissingmove(T) will not
            --attempt to generate 'T.methods.__move' twice
            T.methods.__move_generated = true
        end
    end
end

--__create a missing __copy for 'T' and all its entries
function addmissingcopy(T)
    local runcopy
    runcopy = macro(function(from, to)
        local V = from:gettype()
        if V:isstruct() then
            if ismanaged(V) then
                addmissingcopy(V)
                --copy will always be generated for a managed variable, so
                --we do a sanity check 
                assert(hasmethod(V, "__copy"), "__copy could not be generated.")
                return quote
                    [V.methods.__copy](&from, &to)
                end
            else
                return quote
                    to = from
                end
            end
        elseif V:isarray() then
            return quote
                for i = 0, V.N do
                    runcopy(from[i], to[i])
                end
            end
        else
            return quote
                to = from
            end
        end
    end)

    if T:isstruct() and ismanaged(T) then
        if not T.methods.__copy and not T.methods.__copy_generated then
            if hasmanagedfields(T) then
                T.methods.__copy = terra(from : &T, to : &T)
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
            else
                --if a managed variable or any of its fields do not implement 
                --a __copy then we fallback to a __move
                addmissingmove(T)
                T.methods.__copy = T.methods.__move
            end
            --the following flag will signal that addmissingcopy(T) will not
            --attempt to generate 'T.methods.__copy' twice
            T.methods.__copy_generated = true
        end
    end
end

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

--add definitions such that we can access them from terralib
terralib.ext = {
    addmissing = {
        __init = addmissinginit,
        __dtor = addmissingdtor,
        __copy = addmissingcopy,
        __move = addmissingmove,
        __forward = addmissingforward,
        arraydestructor = generatearraydestructor,
        arrayinitializer = generatearrayinitializer
    }
}