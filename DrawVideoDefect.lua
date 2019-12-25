
local function getDom()
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	if not xmlDom then
		error("no Msxml2.DOMDocument: " .. luacom.config.last_error)
	end
--	local pi = xmlDom:createProcessingInstruction("xml", "version='1.0' encoding='utf-8'")
--	xmlDom:appendChild(pi)
	return xmlDom
end

-- итератор по нодам xml
local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end

local function make_node(parent, name, attrib)
	local isParetNode = parent.nodeType == 1  -- tagDOMNodeType.NODE_ELEMENT
	local dom = isParetNode and parent.ownerDocument or parent
	local node = dom:createElement(name)
	for n, v in pairs(attrib or {}) do
		node:setAttribute(n, v)
	end
	if isParetNode then
		parent:appendChild(node)
	end
	return node
end

local function get_center_point(points)
	assert(#points % 2 == 0)
	local x, y = 0, 0
	local cnt = #points / 2
	for i = 1, #points, 2 do
		x = x + points[i]   / cnt
		y = y + points[i+1] / cnt
	end
	return {x, y}
end
	
function round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end	
	
local function points2str(points)
	assert(#points % 2 == 0)
	local res = ''
	for i = 1, #points, 2 do
		if #res ~= 0 then res = res .. ' ' end
		res = res .. string.format("%d,%d", points[i], points[i+1])
	end
	return res
end

local function get_frame_cooord(xmlRoot)
	local nodeFrameCoord = xmlRoot:selectSingleNode("//PARAM[@name='FrameNumber' and @value='0']/@coord")
	local nodeSysCoord = xmlRoot:selectSingleNode('/PARAM[@name="ACTION_RESULTS" and @value="Common"]/PARAM[@name="RecogObjCoord"]/@value')
	if nodeFrameCoord and nodeSysCoord then
		return tonumber(nodeFrameCoord.nodeValue), tonumber(nodeSysCoord.nodeValue)
	end
end

local function get_rail_channel_mask(xmlRoot)
	local chmask = 0
	for node in SelectNodes(xmlRoot, "PARAM[@name='ACTION_RESULTS' and @channel]/@channel") do
		local ch = tonumber(node.nodeValue)
		chmask = bit32.bor(chmask, bit32.lshift(1, ch))
	end
	local rmask = 0
	if bit32.btest(chmask, 0xaaaaaaaa) then  -- b10101010
		rmask = bit32.bor(rmask, 1)
	end
	if bit32.btest(chmask, 0x55555555) then  -- b01010101
		rmask = bit32.bor(rmask, 2)
	end
	return rmask, chmask
end

local function get_action_result(name)
	local guids = {
		['UIC_2251'] = 'Surface_SLEEPAGE_SKID_UIC_2251_USER',
	    ['UIC_2252'] = 'Surface_SLEEPAGE_SKID_UIC_2252_USER',
        ['UIC_227']  = 'Surface_SQUAT_UIC_227_USER',
	}
	local res = guids[name]
	if not res then
		error(string.format('no action result for defect (%s)'), name)
	end
	return res
end

local function get_mark_guid(name)
	local guids = {
		['UIC_2251'] = '{41486CAC-EBE9-46FF-ACCA-041AFAFFC531}',
	    ['UIC_2252'] = '{3401C5E7-7E98-4B4F-A364-701C959AFE99}',
        ['UIC_227']  = '{13A7906C-BBFB-4EB3-86FA-FA74B77F5F35}',
	}
	local res = guids[name]
	if not res then
		error(string.format('no GUID for defect (%s)'), name)
	end
	return res
end
		
local MarkFlags = {
	eIgnoreShift	= 0x01,		-- смещение канала на котором установлена отметка игнорируется и рамочки не ездят
	eDrawRect		= 0x02,		-- рисовать прямоугольник
	eDrawLine		= 0x04,		-- рисовать линию на координате отметки
	eShiftOnAsIs	= 0x08,		-- смещение применятеся с др знаком, то есть при выключенном сведении рамка рисуется сдвинутая относительно координаты отметки, а при включении сведения на своей координате (объект)
}		
		
-- ============================================== 

local function make_xml_hun(name, objects, reliability)
	local action_result = get_action_result(name)
	local dom = getDom()
	local mark_coord, mark_coord_count = 0, 0
	
	local nodeRoot = dom:createElement("ACTION_RESULTS")
	for _, object in ipairs(objects) do
		local area = object.area
		local center_point = get_center_point(object.points)
		local frame, sys_coord = area:get_frame(center_point)
		if frame then
			frame_coord = frame
			mark_coord = mark_coord + sys_coord - area.video_offset
			mark_coord_count = mark_coord_count + 1
			
			local nodeActRes = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", channel=area.channel, value=action_result})
			local nodeFrame = make_node(nodeActRes, "PARAM", {name="FrameNumber", value="0", coord=frame})
			local nodeResult = make_node(nodeFrame, "PARAM", {name="Result", value="main"})
			
			local frame_points = area:draw2frame(object.points, frame)
			make_node(nodeResult, "PARAM", {name="Coord", ['type']="polygon", value=points2str(frame_points)})
		end
	end
	if mark_coord_count ~= 0 then
		mark_coord = round(mark_coord / mark_coord_count, 0)
		
		local nodeCommon = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", value="Common"})
		make_node(nodeCommon, "PARAM", {name="Reliability", value=reliability})
		make_node(nodeCommon, "PARAM", {name="RecogObjCoord", value=mark_coord})
	else 
		mark_coord = nil
	end
	
	return nodeRoot
end

local function make_hun_mark(name, objects, driver)
	local reliability = 101
	local mark_xml = make_xml_hun(name, objects, reliability)
	print(mark_xml)
	if not mark_xml then 
		return {}
	end
	local frame_coord, sys_coord = get_frame_cooord(mark_xml)
	print(frame_coord, sys_coord)
	if not frame_coord or not sys_coord then
		return {}
	end
	
	local rmask, chmask = get_rail_channel_mask(mark_xml)
	print(rmask, chmask)
	local guid = get_mark_guid(name)
	
	local mark = driver:NewMark()
	mark.prop.SysCoord = sys_coord
	mark.prop.Len = 1
	mark.prop.RailMask = rmask + 8   -- 9 = video mask
	mark.prop.Guid = guid
	mark.prop.ChannelMask = chmask
--	mark.prop.UserFlags = 
	mark.prop.MarkFlags = MarkFlags.eIgnoreShift
	
	mark.ext.RAWXMLDATA = mark_xml.xml
	mark.ext.VIDEOIDENTRLBLT = reliability
	
	mark.ext.VIDEOFRAMECOORD = frame_coord
	return {mark}
end


local DRAW_FIG = 
{
	rect_red = {sign="", fig="rect", line_color=0xff0000}
}

-- ================= DEFECTS =================

local DEFECTS = 
{
	{group="Венгры", name="UIC_2251", tools={DRAW_FIG.rect_red}, fn=make_hun_mark},
	{group="Венгры", name="UIC_2252", tools={DRAW_FIG.rect_red}, fn=make_hun_mark},
	{group="Венгры", name="UIC_227",  tools={DRAW_FIG.rect_red}, fn=make_hun_mark},
}

local function find_defect(name)
	for _, d in ipairs(DEFECTS) do
		if (d.sign or d.name) == name then 
			return d
		end
	end
	error(string.format('Unknown defect type [%s]', name))
end

-- ================= EXPORT =================

--[[
Функция вызывается из программы DrawVideoDefect для построения панели с доступными типами дефектов.

Функция должна вернуть массив, где каждый элемент содержит описанеи типа дефекта, 
описание является массивом из 3х эламентов:
- группа, 
- текстовое описание, 
- внутреннее наименование (sign) (передеается в функцию генерации XML)
]]
function GetDefects()
	local defects = {}
	for _, d in ipairs(DEFECTS) do
		table.insert(defects, {d.group, d.name, d.sign or d.name})
	end
	return defects
end   
    
--[[
Функция вызывается программой, для определения списка доступных инструментов для рисования

Функция должна вернуть массив с описанием, каждый элемент это таблица с полями:
- draw_sign идентификатор (передается в функцию генерации XML)
- draw_fig тип (rect, circle)
- line_color цвет (0xRRGGBB)
]]	
function GetAvailableTools(name)
	return find_defect(name).tools
end

--[[
Функция вызывается программой для построения итогового XML

Функция принимает параметры:
- сигнатура дефекта
- список объектов, нарисованных пользователем(1).

Каждый объект (1) содержит поля:
- sign: описание фигуры
- points: - массив длинной 2N, содержащий N точек, поставленных пользователем (в экранных координатах), например прямоугольник дает 8 точек (4 угла)
- area: описание области канала (2)

Область канала (2) объект со следующими полями и методами:
- channel: номер видео канала
- video_offset: смещение видео канала
- get_frame: метод получения координаты кадра по набору точек, принимает массив точек (длинной 2 и более, но кратно 2) и возвращает соотв. координату фрема и сисемную координату точки
- draw2frame: метод перемодит экранный координаты точек в координаты фрейма, принимает массив точек и опционально номер фрейма (иначе вычисляет его сам по средней точке), возвращает массив точек в координатах фрейма

Функция должна вернуть строку с XML
]]
function MakeMark(name, objects, driver)
	local fn = find_defect(name).fn
	local marks = fn(name, objects, driver)
	for _, m in ipairs(marks) do
		m:Save()
	end
end
