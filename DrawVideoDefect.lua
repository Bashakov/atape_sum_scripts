-- require('mobdebug').start()

package.loaded.sumPOV = nil -- для перезагрузки в дебаге

local TYPES = require 'sum_types'
local sumPOV = require "sumPOV"
local utils = require 'utils'
local alg = require 'algorithm'
local xml_utils = require 'xml_utils'


-- ================= вспомогательные =================

local sorted = alg.sorted
local starts_with = alg.starts_with


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

--[[ преобразование прямоугольника в координаты его вершин
исходный прямоугольник в формате программы (l, t, w, h) в координатах окна,
выходной массив точек определяется параметром corners, который является строкой состоящей из букв "l", "r", "t", "b",
означающих соответствующие вершины, координаты соответствуют пикселям на кадре.
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
	return utils.round(mark_coord)
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
	local frame_src = rect2corners(object, "ltrtrblb") -- left, top, right, top, right, bottom, left, bottom
	local strRect = string.format("%d,%d %d,%d %d,%d %d,%d", table.unpack(frame_src))

	local nodeActRes = make_node(nodeRoot  , "PARAM", {name="ACTION_RESULTS", channel=object.area.channel, value=action_result})
	local nodeFrame  = make_node(nodeActRes, "PARAM", {name="FrameNumber", value="0", coord=object.center_frame})
	local nodeResult = make_node(nodeFrame , "PARAM", {name="Result", value="main"})
	make_node(nodeResult, "PARAM", {name="Coord", ['type']="polygon", value=strRect})
	make_node(nodeResult, "PARAM", {name="RailGapWidth_mkm", value=utils.round((frame_src[3] - frame_src[1]) * 1000)})
end

-- сформировать xml с описание поверхностного дефекта
local function make_surface_node(nodeRoot, object, action_result)
	local frame_src = rect2corners(object, "ltrtrblb") -- left, top, right, top, right, bottom, left, bottom
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

-- сформировать xml с описание болтовых отверстий
local function make_joint_node(nodeRoot, joints)
	local cfj = {} -- channel-frame-joint
	-- группируем отверстия по каналам и кадрам
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


local function make_beacons_node(nodeRoot, beacon)
	local pos_web = beacon.area:draw2frame({beacon.points[1], beacon.points[2]}, beacon.center_frame)
	local pos_fst = beacon.area:draw2frame({beacon.points[3], beacon.points[4]}, beacon.center_frame)
	
	-- упорядочим по высоте
	if pos_web[2] < pos_fst[2] then
		pos_web, pos_fst = pos_fst, pos_web
	end

	local shift = pos_fst[1] - pos_web[1]

	local w, h = 10, 100
	local tps = {'Beacon_Web', 'Beacon_Fastener'}
	for i, pos in ipairs{pos_web, pos_fst} do
		local nodeActRes = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", channel=beacon.area.channel, value=tps[i]})
		local nodeFrame  = make_node(nodeActRes, "PARAM", {name="FrameNumber", value='0', coord=beacon.center_frame})
		local nodeResult = make_node(nodeFrame , "PARAM", {name="Result", value="main"})

		local strRect = string.format("%d,%d,%d,%d", pos[1]-w, pos[2], pos[1]+w, pos[2]+h)
		make_node(nodeResult, "PARAM", {name="Coord", ['type']="rect", value=strRect})

		make_node(nodeResult, "PARAM", {name="Shift", value=shift})
		make_node(nodeResult, "PARAM", {name="Shift_mkm", value=shift*1000})
		h = -h
		shift = -shift
	end
end

local function make_xml_node_common(nodeRoot, reliability, objects)
	local nodeCommon = make_node(nodeRoot, "PARAM", {name="ACTION_RESULTS", value="Common"})
	make_node(nodeCommon, "PARAM", {name="Reliability", value=reliability})
	make_node(nodeCommon, "PARAM", {name="RecogObjCoord", value=get_common_system_coord(objects)})
end

-- построение xml описания дефекта
local function make_recog_xml(objects, action_result, reliability)
	local dom = xml_utils.create_dom()

	local joints = {}

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
			make_beacons_node(nodeRoot, object)
		elseif object.sign == 'fishplate_fault' then
			make_fishplate_fault_node(nodeRoot, object)
		else
			error('unknown tool: ' .. object.sign)
		end
	end

	make_joint_node(nodeRoot, joints)
	make_xml_node_common(nodeRoot, reliability, objects)
	return nodeRoot
end

local function loadMarks(driver, guids, center, max_dist, rail_mask)
	return driver:GetMarks{
		GUIDS=guids,
		ListType='all',
		FromSys = center - max_dist,
		ToSys = center + max_dist,
		RailMask = rail_mask,
	}
end

local function formatMarkPos(driver, mark)
	local rail_names = {
		[1] = "Купейном рельсе",
		[2] = "Коридорном рельсе",
		[3] = "Двух рельсах"
	}
	local rail_name = rail_names[bit32.band(mark.prop.RailMask, 3)] or ""
	local km, m, mm = driver:GetPathCoord(mark.prop.SysCoord)
	return string.format("%d км %.1f м на %s рельсе", km, m + mm/1000, rail_name)
end

local function remove_old_beacons(driver, new_mark)
	local old_beacon = loadMarks(driver, {TYPES.VID_BEACON_INDT, TYPES.M_SPALA}, new_mark.prop.SysCoord, 5000, bit32.band(new_mark.prop.RailMask, 3))
	local to_remove = {}
	for _, m in ipairs(old_beacon) do
		if m.prop.RailMask == new_mark.prop.RailMask then
			table.insert(to_remove, m)
		end
	end
	if #to_remove > 0 then
		local msg = {"Найдены старые маячные отметки:"}
		for i, m in ipairs(to_remove) do
			table.insert(msg, string.format("\t - %s", formatMarkPos(driver, m)))
		end
		table.insert(msg, "Подтвердите удаление")
		if 1 == iup.Alarm("ATape", table.concat(msg, '\n'), "Да", "Нет") then
			for i, m in ipairs(to_remove) do
				m:Delete()
				m:Save()
			end
		end
	end
end

function replace_joint_gap_xml(old_xml, new_xml)
	local xpathGap = "//PARAM[@name='ACTION_RESULTS' and descendant::node()/@name='RailGapWidth_mkm']"
	for nodeGapOld in xml_utils.SelectNodes(old_xml, xpathGap) do
		nodeGapOld:getParentNode():removeChild(nodeGapOld)
	end
	local old_root = old_xml:selectSingleNode("/ACTION_RESULTS")
	for nodeGapNew in xml_utils.SelectNodes(new_xml, xpathGap) do
		old_root:appendChild(nodeGapNew)
	end
end

local function process_old_joint(driver, new_mark)
	local video_joints_guids =
	{
		TYPES.VID_INDT_1,	-- Стык(Видео)
		TYPES.VID_INDT_2,	-- Стык(Видео)
		TYPES.VID_INDT_3,	-- СтыкЗазор(Пользователь)
		TYPES.VID_INDT_ATS,	-- АТСтык(Видео)
		TYPES.RAIL_JOINT_USER,	-- Рельсовые стыки(Пользователь)
		TYPES.VID_ISO,   -- ИзоСтык(Видео)
	}

	local old_marks = loadMarks(driver, video_joints_guids, new_mark.prop.SysCoord, 5000, bit32.band(new_mark.prop.RailMask, 3))
	local distances = alg.map(function (m) return math.abs(m.prop.SysCoord - new_mark.prop.SysCoord) end, old_marks)
	local i = alg.min_element(distances)
	if i then
		local nearest_old_joint = old_marks[i]
		local old_xml = xml_utils.load_xml_str(nearest_old_joint.ext.RAWXMLDATA, true)
		if old_xml then
			local new_xml = xml_utils.load_xml_str(new_mark.ext.RAWXMLDATA)
			local nodeNewGape = new_xml:selectSingleNode("//PARAM[@name='RailGapWidth_mkm']")
			if nodeNewGape then
				local msg = string.format("Обнаружен стык %s,", formatMarkPos(driver, nearest_old_joint))
				local action = iup.Alarm("ATape", msg, "Удалить", "Переписать зазор", "Оставить оба")
				if 1 == action then
					nearest_old_joint:Delete()
					nearest_old_joint:Save()
				elseif 2 == action then
					replace_joint_gap_xml(old_xml, new_xml)
					nearest_old_joint.ext.RAWXMLDATA = old_xml.xml
					sumPOV.UpdateMarks({nearest_old_joint})
					nearest_old_joint:Save()
					driver:JumpMark(nearest_old_joint)
					return -- nothing, reject new mark
				end
			end
		end
	end
	return new_mark
end

-- ================== MARK GENERATION ===================== --

-- значения флагов MarkFlags отметки
local MarkFlags = {
	eIgnoreShift	= 0x01,		-- смещение канала на котором установлена отметка игнорируется и рамочки не ездят
	eDrawRect		= 0x02,		-- рисовать прямоугольник
	eDrawLine		= 0x04,		-- рисовать линию на координате отметки
	eShiftOnAsIs	= 0x08,		-- смещение применяется с др знаком, то есть при выключенном сведении рамка рисуется сдвинутая относительно координаты отметки, а при включении сведения на своей координате (объект)
}

local function _make_common_mark(driver, objects, guid)
	local rmask, chmask = get_rail_channel_mask(objects)

	local mark = driver:NewMark()
	mark.prop.SysCoord = get_common_system_coord(objects)
	mark.prop.Len = 1
	mark.prop.RailMask = rmask + 8   -- video_mask_bit
	if guid then
		mark.prop.Guid = guid
	end
	mark.prop.ChannelMask = chmask
	mark.prop.MarkFlags = MarkFlags.eIgnoreShift
	return mark
end

function make_recog_mark(name, objects, driver, defect)
	local mark = _make_common_mark(driver, objects, defect.guid)

	local reability = 101
	local nodeRoot = make_recog_xml(objects, defect.action_result, reability)

	mark.ext.RAWXMLDATA = nodeRoot.xml
	mark.ext.VIDEOIDENTRLBLT = reability
	mark.ext.VIDEOFRAMECOORD = objects[1].center_frame

	if name == "Маячная отметка" then
		remove_old_beacons(driver, mark)
	end
	if name == "Стык" then
		mark = process_old_joint(driver, mark)
	end

	return {mark}
end


local function _create_simple_mark(driver, object, guid)
	local points_on_frame, _ = rect2corners(object, "ltrtrblb") -- left, top, right, top, right, bottom, left, bottom

	local mark = _make_common_mark(driver, {object}, guid)
	mark.ext.VIDEOIDENTCHANNEL = object.area.channel
	mark.ext.VIDEOFRAMECOORD = object.center_frame
	mark.ext.UNSPCOBJPOINTS = string.format("%d,%d %d,%d %d,%d %d,%d", table.unpack(points_on_frame))
	return mark
end

--[[ постановка отметки по типу "Ненормативный объект"]]
function make_simple_defect(name, objects, driver, defect)
	local marks = {}
	for i, object in ipairs(objects) do
		local mark = _create_simple_mark(driver, object, defect.guid)

		if defect.add_width_from_user_rect then
			local points_on_frame, _ = rect2corners(object, "rl") -- right, left
			local w = tonumber(points_on_frame[1] - points_on_frame[2])
			--object.options.joint_width = w
			mark.ext.VIDEOIDENTGWT = w
			mark.ext.VIDEOIDENTGWS = w
		end

		local tbl_options = {}
		for n, v in sorted(object.options) do table.insert(tbl_options, string.format("%s:%s", n, v)) end
		local str_options = table.concat(tbl_options, "\n")

		mark.prop.Description = defect.name .. '\nЕКАСУИ = ' .. defect.ekasui_code .. (#str_options == 0 and "" or "\n") .. str_options

		mark.ext.VIDEOIDENTRLBLT = 101
		mark.ext.CODE_EKASUI = defect.ekasui_code
		if str_options and # str_options ~= 0 then
			mark.ext.DEFECT_OPTIONS = str_options
		end
		if defect.speed_limit then
			mark.ext.USER_SPEED_LIMIT = tostring(defect.speed_limit)
		end

		for _, attr_name in ipairs{"RAILWAY_HOUSE", "RAILWAY_TYPE"} do
			local val = defect[attr_name]
			if val then
				mark.ext[attr_name] = tostring(val)
			end
		end

		marks[i] = mark
	end

	--error('make_simple_defect error') -- testing
	return marks
end


--[[ постановка отметки ЖАТ ]]
function make_jat_defect(name, objects, driver, defect)
	local marks = {}
	for i, object in ipairs(objects) do
		local mark = _create_simple_mark(driver, object, defect.guid)

		for ti, tool in ipairs(defect.tools) do
			if tool.sign == object.sign then
				mark.ext.CODE_EKASUI = defect.ekasui_code_list[ti]
				for n, val in pairs(tool.static_options) do
					mark.ext[n] = val
				end

				for n, v in sorted(object.options) do 
					mark.ext[n] = v
				end
			end
		end
		mark.prop.Description = defect.desc
		marks[i] = mark
	end

	return marks
end

function make_group_defect(name, objects, driver, defect)
	local mark = _make_common_mark(driver, objects, defect.guid)

	mark.prop.Description = defect.name .. '\nЕКАСУИ = ' .. defect.ekasui_code
	mark.ext.CODE_EKASUI = defect.ekasui_code
	mark.ext.GROUP_DEFECT_COUNT = defect.objects_count
	if defect.speed_limit then
		mark.ext.USER_SPEED_LIMIT=tostring(defect.speed_limit)
	end

	local l = get_common_system_coord({objects[1]})
	local r = l

	local str_xml = '<draw>\n'
	for _, object in ipairs(objects) do
		local points_on_frame, frame_coord = rect2corners(object, "ltrtrblb") -- left, top, right, top, right, bottom, left, bottom
		local rect = string.format("%d,%d,%d,%d,%d,%d,%d,%d", table.unpack(points_on_frame))

		str_xml = str_xml .. string.format("\t<object channel='%d' type='rect' frame='%d' points='%s'/>\n", object.area.channel, frame_coord, rect)

		local c = get_common_system_coord({object})
		local w = tonumber(points_on_frame[3] - points_on_frame[1])
		l = math.min(l, c-w/2)
		r = math.max(r, c+w/2)
	end
	str_xml = str_xml .. '</draw>'

	if l ~= r then
		mark.ext.GROUP_OBJECT_DRAW = str_xml
	end

	mark.prop.SysCoord = math.floor(l + 0.5)
	mark.prop.Len = math.floor(r - l + 0.5)

	for _, attr_name in ipairs{"RAILWAY_HOUSE", "RAILWAY_TYPE"} do
		local val = defect[attr_name]
		if val then
			mark.ext[attr_name] = tostring(val)
		end
	end

	return {mark}
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
описание является массивом из 3х элементов:
- группа,
- текстовое описание,
- внутреннее наименование (sign) (переедается в функцию генерации XML)
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
- sign идентификатор (передается в функцию генерации XML)
- draw_fig тип (rect, ellipse, line)
- name: имя инструмента, отображается в панели инструментов
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

--[[ Функция вызывается программой для генерации отметок.

Функция принимает параметры:

- сигнатура дефекта (третий элемент возвращаемый GetDefects)
- список объектов, нарисованных пользователем. Каждый объект содержит поля:
    - sign: описание фигуры.
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
  Имеет следующие методы:
	- NewMark: возвращает объект специальной пользовательской отметки.
	  описание возвращаемого объекта см. в SumReportLua.md#объект-отметки

Логика работы функции следующая:

- по сигнатуре дефекта определяется гуид отметки и другие необходимые параметры.
- введенные пользователем объекты разбираются по типам, приводятся в координаты кадра,
- создается новая отметка,
- заполняются ее поля (координата, длинна, канал, гуид и тд.)
- формируется xml с описанием, и сохраняется в отметку,
- вызывается метод отметки для ее сохранения.
]]
function MakeMark(name, objects, driver)
	local defect = find_defect(name)
	local marks = defect.fn(name, objects, driver, defect)
	sumPOV.UpdateMarks(marks, true)

	local lm = marks[#marks]
	if lm and lm.prop and lm.prop.ID then
		driver:JumpMark(lm.prop.ID)
	end
end
