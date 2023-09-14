require "luacom"

local function create_dom()
    local dom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
    if not dom then
        error("no Msxml2.DOMDocument: " .. luacom.config.last_error)
    end   
    return dom 
end

local function load_xml_str(str_xml)
    local dom = create_dom()
	if not dom:loadXML(str_xml) then
		local msg = string.format('Error parse XML: 0x%08X (%d) %s\n%s',
            0x100000000 + dom.parseError.errorCode,
            dom.parseError.errorCode,
            dom.parseError.reason,
			str_xml)
		error(msg)
	end
	return dom
end

-- итератор по нодам xml
local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end

-- конвертировать MSXML ноду в строку с форматированием
local function msxml_node_to_string(node)
	local oWriter = luacom.CreateObject("Msxml2.MXXMLWriter")
	local oReader =  luacom.CreateObject("Msxml2.SAXXMLReader")
	assert(oWriter)
	assert(oReader)

	oWriter.standalone = 0
    oWriter.omitXMLDeclaration = 1
    oWriter.indent = 1
	oWriter.encoding = 'utf-8'

	oReader:setContentHandler(oWriter)
	oReader:putProperty("http://xml.org/sax/properties/lexical-handler", oWriter)
	oReader:putProperty("http://xml.org/sax/properties/declaration-handler", oWriter)

	local unk1 = luacom.GetIUnknown(node)
    oReader:parse(unk1)

	local res = oWriter.output
	return res
end

-- получение значений атрибутов 
local function xml_attr(node, name, def)
	if type(name) == 'table' then
		local res = {}
		for i, n in ipairs(name) do
			res[i] = xml_attr(node, n, def)
		end
		return table.unpack(res)
	else
		local a = node.attributes:getNamedItem(name)
		return a and a.nodeValue or def
	end
end

local xmlDom = create_dom()

return
{
    xmlDom = xmlDom,
    create_dom = create_dom,
    load_xml_str = load_xml_str,
    SelectNodes = SelectNodes,
    msxml_node_to_string = msxml_node_to_string,
    xml_attr = xml_attr,
}
