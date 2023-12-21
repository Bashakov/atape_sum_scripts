dofile("tests\\setup_test_paths.lua")

local lu = require("luaunit")

local xml_utils = require 'xml_utils'

function testLoadXmlStr()
    local function pload(s)
        local ok, res = pcall(xml_utils.load_xml_str, s)
        if ok then
            return res.documentElement.tagName
        else
            local _, e = res:find(':%d+:')
            return res:sub(e+2)
        end
    end

    lu.assertEquals(pload("<a/>"), "a")
    lu.assertEquals(pload("<a></a>"), "a")
    lu.assertEquals(pload("<a><b/></a>"), "a")
    lu.assertStrMatches(pload("<a>"), "Error parse XML.+")
end

function testSelectNodes()
    local function n2l(str_xml, xpath)
        local root = xml_utils.load_xml_str(str_xml)
        root = root.documentElement
        local res = {}
        for n in xml_utils.SelectNodes(root, xpath) do
            table.insert(res, n.tagName)
        end
        return res
    end

    lu.assertEquals(n2l("<a/>", "."), {"a"})
    lu.assertEquals(n2l("<a/>", "/"), {})
    lu.assertEquals(n2l("<a></a>", "."), {"a"})
    lu.assertEquals(n2l("<a></a>", "/a"), {"a"})
    lu.assertEquals(n2l("<a><b/><c/></a>", "/a/*"), {"b", "c"})
    lu.assertEquals(n2l("<a><b/><c/></a>", "//*"), {"a", "b", "c"})
end

function testXmlAttr()
    local root = xml_utils.load_xml_str("<r a='1' b='2'/>").documentElement
    lu.assertEquals(xml_utils.xml_attr(root, 'a'), '1')
    lu.assertEquals(xml_utils.xml_attr(root, 'n', '5'), '5')
    lu.assertEquals({xml_utils.xml_attr(root, {'a', 'b'})}, {'1', '2'})
end

os.exit(lu.LuaUnit.run())
