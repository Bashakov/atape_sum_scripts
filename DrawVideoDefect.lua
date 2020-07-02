package.loaded.sumPOV = nil -- для перезагрузки в дебаге
local sumPOV = require "sumPOV"

-- ================= математика =================

-- округление до idp значачих цифр после запятой
local function round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

-- ================= вспомогательные =================

local function sorted(src, cmp)
	local keys = {}
	for n in pairs(src) do table.insert(keys, n) end
	table.sort(keys, cmp)
	local i = 0 
	return function ()   
		i = i + 1
		return keys[i], src[keys[i]]
	end
end

local function starts_with(input, prefix)
	return string.sub(input, 1, #prefix) == prefix
end

local function save_and_show(str)
	local file_name = 'c:\\1.xml'
	local dst_file = assert(io.open(file_name, 'w+'))
	dst_file:write(str)
	dst_file:close()
	os.execute("start " .. file_name)
end


-- ================= XML =================

local function create_document()
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	if not xmlDom then
		error("no Msxml2.DOMDocument: " .. luacom.config.last_error)
	end
	return xmlDom
end

local function load_xml(path)
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	if not xmlDom then
		error("no Msxml2.DOMDocument: " .. luacom.config.last_error)
	end
	if not xmlDom:load(path) then
		error(string.format("Msxml2.DOMDocument load(%s) failed with: %s", path, xmlDom.parseError.reason))
	end
	return xmlDom
end

local function make_node(parent, name, attrib)
	local parentIsNode = parent.nodeType == 1  -- tagDOMNodeType.NODE_ELEMENT
	local dom = parentIsNode and parent.ownerDocument or parent
	local node = dom:createElement(name)
	for n, v in sorted(attrib or {}) do
		node:setAttribute(n, v)
	end
	if parentIsNode then
		parent:appendChild(node)
	end
	return node
end


-- ================= массивы =================

--[[ преобразование прямоугольника в кооринаты его вершин
исходный прямоугольник в формате программы (l, t, w, h) в координатах окна, 
выходной массив точек определяется параметром corners, который является строкой состоящей из букв "l", "r", "t", "b",
озанчающих соответствующие вершины, координаты соответствуют пикселям на кадре.
дополнительно возвращается координата кадра, на которой находится объект 
]]
local function rect2corners(object, corners)
	assert(#object.points == 4)
	assert(#corners%2 == 0 and not string.match(corners, '[^ltrb]'))
	local src = {
		l = object.points[1],
		t = object.points[2],
		r = object.points[1] + object.points[3], 
		b = object.points[2] + object.points[4], 
	}
	local points = {}
	for i = 1, #corners do
		points[i] = src[corners:sub(i,i)]
	end
	local pos, _, frame = object.area:draw2frame(points)
	return pos, frame
end

-- ================= Объекты =================

-- получает маску каналов и рельса из набора объектов
local function get_rail_channel_mask(objects)
	local chmask = 0
	for _, object in ipairs(objects) do
		local c = bit32.lshift(1, object.area.channel)
		chmask = bit32.bor(chmask, c)
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

-- вычислить системную координату по всем объектам
local function get_common_system_coord(objects)
	local mark_coord = 0
	for _, object in ipairs(objects) do
		local c = object.center_system - object.area.video_offset
		mark_coord = mark_coord + c / #objects
	end
	return round(mark_coord)
end


-- построение xml описания накладки
local function make_fishplate_node(nodeRoot, object)
	local nodeActRes = make_node(nodeRoot  , "PARAM", {name="ACTION_RESULTS", channel=object.area.channel, value='Fishplate'})
	for i, corners in ipairs{"ltlb", "rtrb"} do
		local pos, frame = rect2corners(object, corners)
		local frame_offset = object.area:frame_offset(frame, object.center_frame)
		local poligon = string.format("%d,%d %d,%d", pos[1], pos[2], pos[3], pos[4])
	
		local nodeFrame  = make_node(nodeActRes, "PARAM", {name="FrameNumber", value=frame_offset, coord=frame})
		local nodeResult = make_node(nodeFrame , "PARAM", {name="Result", value="main"})
		local nodeEdge   = make_node(nodeResult , "PARAM", {name="FishplateEdge", value=i})
		make_node(nodeEdge, "PARAM", {name="Coord", ['type']="polygon", value=poligon})
	end
end

-- построение xml описания дефекта накладки
local function make_fishplate_fault_node(nodeRoot, object)
	local w = 1
	local nodeActRes = make_node(nodeRoot , "PARAM", {name="ACTION_RESULTS", channel=object.area.channel, value='Fishplate'})
	local pos, _, frame = object.area:draw2frame(object.points)
	local poligon = string.format("%d,%d %d,%d %d,%d %d,%d", pos[1]-w, pos[2], pos[1]+w, pos[2], pos[3]+w, pos[4], pos[3]-w, pos[4])

	local nodeFrame  = make_node(nodeActRes, "PARAM", {name="FrameNumber", value='0', coord=frame})
	local nodeResult = make_node(nodeFrame , "PARAM", {name="Result", value="main"})
	local nodeState  = make_node(nodeResult , "PARAM", {name="FishplateState"})
	make_node(nodeState, "PARAM", {name="FishplateFault", value='1'})
	make_node(nodeState, "PARAM", {name="Coord", ['type']="polygon", value=poligon})
end

-- сформировать xml с описание зазора
local function make_gape_node(nodeRoot, object, action_result)
	local frame_src = rect2corners(object, "ltrtrblb") -- left, top, rigth, top, rigth, bottom, left, bottom
	local strRect = string.format("%d,%d %d,%d %d,%d %d,%d", table.unpack(frame_src))
	
	local nodeActRes = make_node(nodeRoot  , "PARAM", {name="ACTION_RESULTS", channel=object.area.channel, value=action_result})
	local nodeFrame  = make_node(nodeActRes, "PARAM", {name="FrameNumber", value="0", coord=object.center_frame})
	local nodeResult = make_node(nodeFrame , "PARAM", {name="Result", value="main"})
	make_node(nodeResult, "PARAM", {name="Coord", ['type']="polygon", value=strRect})
	make_node(nodeResult, "PARAM", {name="RailGapWidth_mkm", value=round((frame_src[3] - frame_src[1]) * 1000)})
end

-- сформировать xml с описание поверхностного дефекта
local function make_surface_node(nodeRoot, object, action_result)
	local frame_src = rect2corners(object, "ltrtrblb") -- left, top, rigth, top, rigth, bottom, left, bottom
	local strRect = string.format("%d,%d %d,%d %d,%d %d,%d", table.unpack(frame_src))
	
	local nodeActRes = make_node(nodeRoot  , "PARAM", {name="ACTION_RESULTS", channel=object.area.channel, value=action_result})
	local nodeFrame  = make_node(nodeActRes, "PARAM", {name="FrameNumber", value="0", coord=object.center_frame})
	local nodeResult = make_node(nodeFrame , "PARAM", {name="Result", value="main"})
	make_node(nodeResult, "PARAM", {name="Coord", ['type']="polygon", value=strRect})
	make_node(nodeResult, "PARAM", {name="SurfaceFault", value='0'})
	make_node(nodeResult, "PARAM", {name="SurfaceLength", value=frame_src[3]-frame_src[1]})
	make_node(nodeResult, "PARAM", {name="SurfaceWidth", value=frame_src[2]-frame_src[4]})
	make_node(nodeResult, "PARAM", {name="SurfaceArea", value='0'})
end

-- сформировать xml с описание болтовый отверстий
local function make_joint_node(nodeRoot, joints)
	local cfj = {} -- channel-frame-joint
	-- групируем отверстия по каналам и кадрам
	for _, object in ipairs(joints) do
		local ch = object.area.channel
		local fc = object.center_frame
		if not cfj[ch] then cfj[ch] = {} end
		if not cfj[ch][fc] then cfj[ch][fc] = {} end
		table.insert(cfj[ch][fc], object)
	end
	
	for ch, fj in sorted(cfj) do
		local nodeActRes = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", channel=ch, value='CrewJoint'})	
		local ffc = nil
		local n = 0
		for fc, joints in sorted(fj) do
			if not ffc then ffc = fc end
			local frame_offset = joints[1].area:frame_offset(fc, ffc)
			local nodeFrame  = make_node(nodeActRes, "PARAM", {name="FrameNumber", value=frame_offset, coord=fc})
			local nodeResult = make_node(nodeFrame , "PARAM", {name="Result", value="main"})	
			for _, joint in ipairs(joints) do
				local nodeJoint  = make_node(nodeResult , "PARAM", {name="JointNumber", value=n})
				n = n + 1
				local pos_c = joint.area:draw2frame({joint.points[1], joint.points[2]}, fc)
				local pos_rb = joint.area:draw2frame({joint.points[1]+joint.points[3], joint.points[2]+joint.points[4]}, fc)
				local s = string.format("%d,%d,%d,%d", pos_c[1], pos_c[2], pos_rb[1]-pos_c[1], pos_c[2]-pos_rb[2])
				make_node(nodeJoint , "PARAM", {name="Coord", ['type']="ellipse", value=s})
				
				local safe = ({joint_ok=1, joint_fl=-1})[joint.sign] 
				if safe then
					make_node(nodeJoint , "PARAM", {name="CrewJointSafe", value=safe})
				end
			end
		end
	end
end

local function make_beacons_node(nodeRoot, beacons)
	if #beacons == 0 then return end
	
	if #beacons ~=2 then
		error('Для установки Маячной отметки слеудет поставить 2 объекта: метку на рельсе и метку на накладке')
	end
	-- упорядочим по высоте
	if (beacons[1].points[2] + beacons[1].points[4]/2) < 
	   (beacons[2].points[2] + beacons[2].points[4]/2) then
			beacons = {beacons[2], beacons[1]} -- swap
	end
	
	local shift = beacons[1].center_system - beacons[2].center_system
	for i, object in pairs(beacons) do
		local tps = {'Beacon_Web', 'Beacon_Fastener'}
		local nodeActRes = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", channel=object.area.channel, value=tps[i]})
		local nodeFrame  = make_node(nodeActRes, "PARAM", {name="FrameNumber", value='0', coord=object.center_frame})
		local nodeResult = make_node(nodeFrame , "PARAM", {name="Result", value="main"})
		
		local frame_src = rect2corners(object, "ltrb")
		local strRect = string.format("%d,%d,%d,%d", table.unpack(frame_src))
		make_node(nodeResult, "PARAM", {name="Coord", ['type']="rect", value=strRect})
		
		local sign = k == 1 and 1 or -1
		make_node(nodeResult, "PARAM", {name="Shift", value=sign*shift})
		make_node(nodeResult, "PARAM", {name="Shift_mkm", value=sign*shift*1000})
	end
	
end


-- построение xml описания дефекта
local function make_recog_xml(objects, action_result, reliability)
	local dom = create_document()

	local joints = {}
	local beacons = {}
	
	local nodeRoot = dom:createElement("ACTION_RESULTS")
	for _, object in ipairs(objects) do
		if object.sign == 'fishplate' then
			make_fishplate_node(nodeRoot, object)
		elseif object.sign == 'gape' then
			make_gape_node(nodeRoot, object, action_result)
		elseif object.sign == 'surface' then
			make_surface_node(nodeRoot, object, action_result)
		elseif starts_with(object.sign, 'joint') then
			table.insert(joints, object)
		elseif object.sign == "beacon" then
			table.insert(beacons, object)
		elseif object.sign == 'fishplate_fault' then
			make_fishplate_fault_node(nodeRoot, object)
		else
			error('unknown tool: ' .. object.sign)
		end
	end
	
	make_joint_node(nodeRoot, joints)
	make_beacons_node(nodeRoot, beacons)
	
	local nodeCommon = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", value="Common"})
	make_node(nodeCommon, "PARAM", {name="Reliability", value=reliability})
	make_node(nodeCommon, "PARAM", {name="RecogObjCoord", value=get_common_system_coord(objects)})
	return nodeRoot
end

-- ================== MARK GENERATION ===================== --

-- значения флагов MarkFlags отметки 
local MarkFlags = {
	eIgnoreShift	= 0x01,		-- смещение канала на котором установлена отметка игнорируется и рамочки не ездят
	eDrawRect		= 0x02,		-- рисовать прямоугольник
	eDrawLine		= 0x04,		-- рисовать линию на координате отметки
	eShiftOnAsIs	= 0x08,		-- смещение применятеся с др знаком, то есть при выключенном сведении рамка рисуется сдвинутая относительно координаты отметки, а при включении сведения на своей координате (объект)
}


function make_recog_mark(name, objects, driver, defect)
	local reability = 101
	local mark = driver:NewMark()
	local nodeRoot = make_recog_xml(objects, defect.action_result, reability)
	local rmask, chmask = get_rail_channel_mask(objects)
	
	mark.prop.SysCoord = get_common_system_coord(objects)
	mark.prop.Len = 1
	mark.prop.RailMask = rmask + 8   -- video_mask_bit
	mark.prop.Guid = defect.guid
	mark.prop.ChannelMask = chmask
	mark.prop.MarkFlags = MarkFlags.eIgnoreShift

	mark.ext.RAWXMLDATA = nodeRoot.xml
	mark.ext.VIDEOIDENTRLBLT = reability
	mark.ext.VIDEOFRAMECOORD = objects[1].center_frame
	
--	save_and_show(nodeRoot.xml)
--	error('make_recog_mark error')
	
	sumPOV.UpdateMarks(mark, false)
	
	return {mark}
end


--[[ постановка отметки по типу "Ненормативный объект"]]
function make_simple_defect(name, objects, driver, defect)
	local reability = 101
	local marks = {}
	for i, object in ipairs(objects) do
		local rmask, chmask = get_rail_channel_mask({object})
		local points_on_frame, _ = rect2corners(object, "ltrtrblb") -- left, top, rigth, top, rigth, bottom, left, bottom
		
		local mark = driver:NewMark()
		
		if defect.add_width_from_user_rect then
			local w = tonumber(points_on_frame[3] - points_on_frame[1])
			--object.options.joint_width = w
			mark.ext.VIDEOIDENTGWT = w
			mark.ext.VIDEOIDENTGWS = w
		end
		
		local str_options = {}
		for n, v in sorted(object.options) do table.insert(str_options, string.format("%s:%s", n, v)) end
		str_options = table.concat(str_options, "\n")
		
		mark.prop.SysCoord = get_common_system_coord({object})
		mark.prop.Len = 1
		mark.prop.RailMask = rmask + 8   -- video_mask_bit
		mark.prop.ChannelMask = chmask
		mark.prop.Guid = defect.guid
		mark.prop.MarkFlags = MarkFlags.eIgnoreShift
		mark.prop.Description = defect.name .. '\nЕКАСУИ = ' .. defect.ekasui_code .. (#str_options == 0 and "" or "\n") .. str_options

		mark.ext.VIDEOIDENTRLBLT = 101
		mark.ext.VIDEOIDENTCHANNEL = object.area.channel
		mark.ext.VIDEOFRAMECOORD = object.center_frame
		mark.ext.CODE_EKASUI = defect.ekasui_code
		if str_options and # str_options ~= 0 then
			mark.ext.DEFECT_OPTIONS = str_options
		end
		mark.ext.UNSPCOBJPOINTS = string.format("%d,%d %d,%d %d,%d %d,%d", table.unpack(points_on_frame)) 
		
		marks[i] = mark
	end
	
	sumPOV.UpdateMarks(marks, false)
	
	--error('make_simple_defect error') -- testing
	return marks
end

-- загружаем после определения функция генерации отметок
package.loaded.DrawVideoDefect_defects = nil 	-- для перезагрузки в дебаге
local DEFECTS = require "DrawVideoDefect_defects"


-- ================= DEFECTS =================

local function find_defect(name)
	for _, d in ipairs(DEFECTS) do
		if (d.sign or d.name) == name then
			return d
		end
	end
	error(string.format('Unknown defect type [%s]', name))
end

-- ================= EXPORT =================

--[[ Функция вызывается из программы для построения панели с доступными типами дефектов.

Функция должна вернуть массив, где каждый элемент содержит описание типа дефекта,
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

--[[ Функция вызывается программой, для определения списка доступных инструментов для рисования

Функция должна вернуть массив с описанием, каждый элемент описания это таблица с полями:
- draw_sign идентификатор (передается в функцию генерации XML)
- draw_fig тип (rect, ellipse, line)
- name: имя инструмента, отображается в пенели инструментов
- tooltip: подсказка
- line_color: цвет рамки (0xRRGGBB или {r=0xRR, g=0xGG, b=0xBB, a=0xAA})
- fill_color: цвет заливки
- icon: иконка на панели. 
  если отсутствует то рисуется автоматически используй line_color и fill_color,
  иначе должна иметь префикс "file:" или "base64:" и содержать изображение (bmp, jpg, png)
]]
function GetAvailableTools(name)
	return find_defect(name).tools
end

--[[ Функция вызывается программой для генерации отметкок.

Функция принимает параметры:

- сигнатура дефекта (третий элемент возвращаемый GetDefects)
- список объектов, нарисованных пользователем. Каждый объект содержит поля:
    - draw_sign: описание фигуры.
    - points: массив длинной 2N, описывающий N точек (координаты x,y),
      выбранных пользователем (в экранных координатах),
      например прямоугольник описывается 8 числами (4 угла).
	- area: описание области канала (2).
	  Используется для привязки нарисованных пользователем фигур к координатам кадров.
	  Имеет следующие поля и методы:
        - channel: номер видео канала
        - video_offset: смещение видео канала
		- center_frame: координата фрейма содержащего среднюю точку
		- center_system: системная координата средней точки
		- get_frame: метод получения координаты кадра по набору точек.
		  Принимает массив (длинна кратна 2) или пару чисел.
		  Возвращает координату фрейма и системную координату точки.
		  Если передано несколько точек, то по ним вычисляется среднее значение.
		- draw2frame: метод переводит экранные координаты точек в координаты фрейма.
		  Принимает массив точек и опционально номер фрейма (иначе вычисляет его сам по средней точке).
		  Возвращает массив точек в координатах фрейма.
		- frame_offset: метод для определения необходимого количества шагов, 
		  чтобы попасть с одного кадра на другой. 
		  Принимает 2 параметра: координаты кадров.  
- объект драйвера, используется для создания и сохранения отметок.
  Имеееет следующие методы:
	- NewMark: возвращает обект специальной пользовательской отметки.
	  описание возвращаемого обекта см. в SumReportLua.md#объект-отметки

Логика работы функции следующая:

- по сигнатуре дефекта определяется гуид отметки и другие неодходимые параметры.
- введенные пользователем объекты разбираются по типам, приводятся в координаты кадра,
- создается новая отметка,
- заполняются ее поля (координата, длинна, канал, гуид и тд.)
- формируется xml с описанием, и сохраняется в отметку,
- вызывается метод отметки для ее сохранения.
]]
function MakeMark(name, objects, driver)
	local defect = find_defect(name)
	local marks = defect.fn(name, objects, driver, defect)
	for _, m in ipairs(marks) do
		m:Save()
	end
end
