local lu = require("luaunit")
local SaxWriter = require "xml_sax_writer"


function testWriteXmlSax()
    local res = ""
    local gen = SaxWriter(function(s)
        res = res .. s
    end, true)
    gen:add_node("a", nil, function (node)
        node:add_node("b", {test=1}, "text")
        gen:add_node("c", {val=2}, function ()
            node:add_node("d")
        end)
    end)
    lu.assertEquals(res,
[[<a>
 <b test="1">text</b>
 <c val="2">
  <d></d>
 </c>
</a>]])
end

os.exit(lu.LuaUnit.run())
