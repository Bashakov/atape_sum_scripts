
local OOP = {}

function OOP.class1(src)
    local struct = src or {}

    local function _create_instance(cls, ...)
        local inst = {}
        for k, v in pairs(struct) do
            inst[k] = v
        end
		if struct.ctor then 
			struct.ctor(inst, ...) -- вызываем конструктор с параметрами
		end
        return inst
    end

    local cls = {}
    setmetatable(cls, {
        __index = {
            create = _create_instance, -- метод класса, не инстанции
        },
        __call = function(cls, ...)
            return cls:create(...) -- сахар синтаксиса конструктора
        end,
    })
    return cls
end


function OOP.class(src)
    local struct = src or {}

    local cls = {}
    setmetatable(cls, {
        __call = function(cls_, ...)
            assert(cls == cls_)
            local inst = {}
            for k, v in pairs(struct) do
                inst[k] = v
            end
            if struct.ctor then
                struct.ctor(inst, ...) -- вызываем конструктор с параметрами
            end
            return inst
        end,
    })
    return cls
end

return OOP
