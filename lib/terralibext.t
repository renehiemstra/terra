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

--__create a missing __init for 'T' and all its entries
local function addmissinginit(T)

    --flag that signals that a missing __init method needs to
    --be generated
    local generate = false

    local runinit = macro(function(self)
        local V = self:gettype()
        --avoid generating code for empty array initializers
        local function hasinit(U)
            if U:isstruct() then return U.methods.__init
            elseif U:isarray() then return hasinit(U.type)
            else return false end
        end
        if V:isstruct() then
            if not V.methods.__init then
                addmissinginit(V)
            end
            local method = V.methods.__init
            if method then
                generate = true
                return quote
                    self:__init()
                end
            end
        elseif V:isarray() and hasinit(V) then
            return quote
                var pa = &self
                for i = 0,T.N do
                    runinit((@pa)[i])
                end
            end
        elseif V:ispointer() then
            return quote
                self = nil
            end
        end
        return quote end
    end)

    local generateinit = macro(function(self)
        local T = self:gettype()
        local stmts = terralib.newlist()
        local entries = T:getentries()
        for i,e in ipairs(entries) do
            if e.field then
                local expr = `runinit(self.[e.field])
                if expr and #expr.tree.statements > 0 then
                    stmts:insert(expr)
                end
            end
        end
        return stmts
    end)

    if T:isstruct() then
        --__init is implemented
        if T.methods.__init and not T.methods.__init_generated then
            T.methods.__init_generated = T.methods.__init
            return
        end
        --__dtor is not implemented
        if not T.methods.__init and not T.methods.__init_generated then
            T.methods.__init_generated = terra(self : &T)
                generateinit(@self)
            end
            if generate then
                T.methods.__init = T.methods.__init_generated
            else
                --set T.methods.__init to false. This means that addmissinginit(T) will not
                --attempt to generate 'T.methods.__init' twice
                T.methods.__init = false
            end
            return
        end
    end
end

--__create a missing __dtor for 'T' and all its entries
local function addmissingdtor(T)

    --flag that signals that a missing __dtor method needs to
    --be generated
    local generate = false

    local rundtor = macro(function(self)
        local V = self:gettype()
        --avoid generating code for empty array destructors
        local function hasdtor(U)
            if U:isstruct() then return U.methods.__dtor
            elseif U:isarray() then return hasdtor(U.type)
            else return false end
        end
        if V:isstruct() then
            if not V.methods.__dtor then
                addmissingdtor(V)
            end
            local method = V.methods.__dtor
            if method then
                generate = true
                return quote
                    self:__dtor()
                end
            end
        elseif V:isarray() and hasdtor(V) then
            return quote
                var pa = &self
                for i = 0,T.N do
                    rundtor((@pa)[i])
                end
            end
        end
        return quote end
    end)

    local generatedtor = macro(function(self)
        local T = self:gettype()
        local stmts = terralib.newlist()
        local entries = T:getentries()
        for i,e in ipairs(entries) do
            if e.field then
                local expr = `rundtor(self.[e.field])
                if expr and #expr.tree.statements > 0 then
                    stmts:insert(expr)
                end
            end
        end
        return stmts
    end)

    if T:isstruct() then
        --__dtor is implemented
        if T.methods.__dtor and not T.methods.__dtor_generated then
            T.methods.__dtor_generated = T.methods.__dtor
            return
        end
        --__dtor is not implemented
        if not T.methods.__dtor and not T.methods.__dtor_generated then
            --generate __dtor
            T.methods.__dtor_generated = terra(self : &T)
                generatedtor(@self)
            end
            if generate then
                T.methods.__dtor = T.methods.__dtor_generated
            else
                --set T.methods.__dtor to false. This means that addmissingdtor(T) will not
                --attempt to generate 'T.methods.__dtor' twice
                T.methods.__dtor = false
            end
            return
        end
    end
end

--__create a missing __copy for 'T' and all its entries
local function addmissingcopy(T)

    --flag that signals that a missing __copy method needs to
    --be generated
    local generate = false

    local runcopy = macro(function(from, to)
        local U = from:gettype()
        local V = to:gettype()
        --avoid generating code for empty array initializers
        local function hascopy(W)
            if W:isstruct() then return W.methods.__copy
            elseif W:isarray() then return hascopy(W.type)
            else return false end
        end
        if V:isstruct() and U==V then
            if not V.methods.__copy then
                addmissingcopy(V)
            end
            local method = V.methods.__copy
            if method then
                generate = true
                return quote
                    method(&from, &to)
                end
            else
                return quote
                    to = from
                end
            end
        elseif V:isarray() and hascopy(V) then
            return quote
                var pa = &self
                for i = 0,V.N do
                    runcopy((@pa)[i])
                end
            end
        else
            return quote
                to = from
            end
        end
        return quote end
    end)

    local generatecopy = macro(function(from, to)
        local stmts = terralib.newlist()
        local entries = T:getentries()
        for i,e in ipairs(entries) do
            local field = e.field
            if field then
                local expr = `runcopy(from.[field], to.[field])
                if expr and #expr.tree.statements > 0 then
                    stmts:insert(expr)
                end
            end
        end
        return stmts
    end)

    if T:isstruct() then
        --__copy is implemented
        if T.methods.__copy and not T.methods.__copy_generated then
            T.methods.__copy_generated = T.methods.__copy
            return
        end
        --__copy is not implemented
        if not T.methods.__copy and not T.methods.__copy_generated then
            --generate __copy
            T.methods.__copy_generated = terra(from : &T, to : &T)
                generatecopy(@from, @to)
            end
            if generate then
                T.methods.__copy = T.methods.__copy_generated
            else
                --set T.methods.__copy to false. This means that addmissingcopy(T) will not
                --attempt to generate 'T.methods.__copy' twice
                T.methods.__copy = false
            end
            return
        end
    end
end

--generate __move, which moves resources to a new allocated variable
local function addmissingmove(T)
    if T:isstruct() then
        if T.methods.__move and not T.methods.__move_generated then
            T.methods.__move_generated = T.methods.__move
            return
        end

        if not T.methods.__move and not T.methods.__move_generated then
            --generate missing __forward and __init
            addmissingforward(T)
            addmissinginit(T)
            --if an __init was generated then we can generate a specialized __move
            if T.methods.__init then
                T.methods.__move_generated = terra(self : &T)
                    var new = self:__forward_generated() --shallow copy of 'self'
                    self:__init_generated()   --initialize old 'self'
                    return new
                end
                T.methods.__move = T.methods.__move_generated
            --otherwise, __move is just __forward and is accessible only in __move_generated
            else
                T.methods.__move_generated = T.methods.__forward_generated
                T.methods.__move = false
            end
            return
        end
    end
end

local function addmissingraii(T)
    addmissingforward(T)
    addmissingdinit(T)
    addmissingdtor(T)
    addmissingcopy(T)
    addmissingmove(T)
end

terralib.ext = {
    addmissing = {
        __forward = addmissingforward,
        __init = addmissinginit,
        __dtor = addmissingdtor,
        __copy = addmissingcopy,
        __move = addmissingmove,
        __all = addmissingraii
    }
}