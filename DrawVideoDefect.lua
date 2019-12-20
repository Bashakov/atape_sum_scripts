
local function getDom()
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	if not xmlDom then
		error("no Msxml2.DOMDocument: " .. luacom.config.last_error)
	end
--	local pi = xmlDom:createProcessingInstruction("xml", "version='1.0' encoding='utf-8'")
--	xmlDom:appendChild(pi)
	return xmlDom
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

-- ============================================== 

local function make_xml_hun(defect_sign, objects)
	local dom = getDom()
	local mark_coord, mark_coord_count = 0, 0
	
	local nodeRoot = dom:createElement("ACTION_RESULTS")
	for _, object in ipairs(objects) do
		local area = object.area
		local center_point = get_center_point(object.points)
		local frame, sys_coord = area:get_frame(center_point)
		if frame then
			mark_coord = mark_coord + sys_coord - area.video_offset
			mark_coord_count = mark_coord_count + 1
			
			local nodeActRes = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", channel=area.channel, value=defect_sign})
			local nodeFrame = make_node(nodeActRes, "PARAM", {name="FrameNumber", value="0", coord=frame})
			local nodeResult = make_node(nodeFrame, "PARAM", {name="Result", value="main"})
			
			local frame_points = area:draw2frame(object.points, frame)
			make_node(nodeResult, "PARAM", {name="Coord", ['type']="polygon", value=points2str(frame_points)})
		end
	end
	if mark_coord_count ~= 0 then
		mark_coord = round(mark_coord / mark_coord_count, 0)
		
		local nodeCommon = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", value="Common"})
		make_node(nodeCommon, "PARAM", {name="Reliability", value="101"})
		make_node(nodeCommon, "PARAM", {name="RecogObjCoord", value=mark_coord})
	end
	
	return nodeRoot.xml
end

local DRAW_FIG = 
{
	rect_red = {sign="", fig="rect", line_color=0xff0000}
}

-- ================= DEFECTS =================

local DEFECTS = 
{
	{group="Венгры", name="UIC_2251", sign="Surface_SLEEPAGE_SKID_UIC_2251", tools={DRAW_FIG.rect_red}, fn=make_xml_hun},
	{group="Венгры", name="UIC_2252", sign="Surface_SLEEPAGE_SKID_UIC_2252", tools={DRAW_FIG.rect_red}, fn=make_xml_hun},
	{group="Венгры", name="UIC_227",  sign="Surface_SQUAT_UIC_227",          tools={DRAW_FIG.rect_red}, fn=make_xml_hun},
}

local function find_defect(defect_sign)
	for _, d in ipairs(DEFECTS) do
		if d.sign == defect_sign then 
			return d
		end
	end
	error(string.format('Unknown defect type [%s]', defect_sign))
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
		table.insert(defects, {d.group, d.name, d.sign})
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
function GetAvailableTools(defect_sign)
	return find_defect(defect_sign).tools
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
function BuildXML(defect_sign, objects)
	local fn = find_defect(defect_sign).fn
	return fn(defect_sign, objects)
end
