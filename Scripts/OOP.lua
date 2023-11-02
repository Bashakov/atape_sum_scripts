
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

OOP.staticmethod = function (f)
    return f
end

function OOP.class(struct)
    struct = struct or {}

    local cls = {}
    setmetatable(cls, {
        __call = function(cls_, ...)
            assert(cls == cls_)
            local inst = {}
            for k, v in pairs(struct) do
                inst[k] = v
            end
            local res
            if struct.ctor then
                res = struct.ctor(inst, ...) -- вызываем конструктор с параметрами
            end
            return inst, res
        end,
    })

    for name, val in pairs(struct) do
        local val_type = type(val)
        if val_type == "function" then
            if val == OOP.staticmethod then
                cls[name] = val()
            end
        else
            cls[name] = val
        end
    end
    return cls
end


return OOP
