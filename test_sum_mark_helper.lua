local lu = require('luaunit')

--print(package.cpath)
package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'
--print(package.cpath)

local mark_helper = require 'sum_mark_helper'

function testEqualRange()
    local er = function(a, v, p) local l, b = mark_helper.equal_range(a, v, p) return {l, b} end

    local a = {10,20,}

    lu.assertEquals({1, 1}, er(a, 5))
    lu.assertEquals({1, 2}, er(a, 10))
    lu.assertEquals({2, 2}, er(a, 15))
    lu.assertEquals({2, 3}, er(a, 20))
    lu.assertEquals({3, 3}, er(a, 25))

    lu.assertEquals({1, 1}, er({}, 0))

    local l = {}
    for i = 1,1000 do l[i] = i end
    for i,_ in ipairs(l) do
        lu.assertEquals({i, i+1}, er(l, i))
    end
end


os.exit( lu.LuaUnit.run() )
