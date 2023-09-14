local lu = require('luaunit')

--print(package.cpath)
package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'
--print(package.cpath)

local mark_helper = require 'sum_mark_helper'




os.exit( lu.LuaUnit.run() )
