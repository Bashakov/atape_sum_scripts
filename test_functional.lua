local lu = require("luaunit")

local functional = require 'functional'

function testList()
    local gen = function(n)
        return function ()
            if n > 0 then
                n = n - 1
                return n
            end
        end
    end

    local g = gen(4)
    local actual = functional.list(g)
    lu.assertEquals(actual, {3, 2, 1, 0})
end

function testMap()
    local src = {1,2,3}
    local actual = functional.map(function (x)
        return x*2
    end, src);
    lu.assertEquals(actual, {2, 4, 6})
end

function testFilter()
    local src = {1,2,3,4,5}
    local actual = functional.filter(function (x)
        return x % 2 == 0
    end, src);
    lu.assertEquals(actual, {2, 4})
end

function testZip()
    local src1 = {1, 2, 3}
    local src2 = {'a', 'b', 'c'}

    local actual = functional.zip(src1, src2)
    lu.assertEquals(actual, {{1, 'a'}, {2, 'b'}, {3, 'c'}})
end

function testIZip()
    local src1 = {1, 2, 3}
    local src2 = {'a', 'b', 'c'}

    local actual = {}
    for a, b, c in functional.izip(src1, src2) do
        lu.assertIsNil(c)
        table.insert(actual, {a, b})
    end
    lu.assertEquals(actual, {{1, 'a'}, {2, 'b'}, {3, 'c'}})
end

os.exit(lu.LuaUnit.run())
