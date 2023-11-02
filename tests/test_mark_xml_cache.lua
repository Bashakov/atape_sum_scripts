dofile("tests\\setup_test_paths.lua")

local lu = require 'luaunit'
local mark_xml_cache = require "mark_xml_cache"


function TestCache()
    local requests = {}
    local get_key = function (mark)
        return mark
    end
    local get_value = function (mark)
        table.insert(requests, mark)
        return mark*10
    end

    local cache = mark_xml_cache.MarkXmlCache(4, get_value, get_key)
    lu.assertEquals(cache:get(1), 10)
    lu.assertEquals(cache:get(10), 100)
    lu.assertEquals(cache:get(1), 10)
    lu.assertEquals(cache:get(2), 20)
    lu.assertEquals(cache:get(11), 110)
    lu.assertEquals(cache:get(3), 30)
    lu.assertEquals(cache:get(12), 120)
    lu.assertEquals(cache:get(10), 100)
    lu.assertEquals(cache:get(11), 110)
	lu.assertEquals(cache:get(1), 10)
    lu.assertEquals(requests, {1, 10, 2, 11, 3, 12, 10, 1})
end

os.exit(lu.LuaUnit.run())
