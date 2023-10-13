require "luacom"
local DEFECT_CODES = require 'report_defect_codes'
local TYPES = require 'sum_types'
local utils = require 'utils'
local algorithm = require 'algorithm'
local xml_utils = require 'xml_utils'
local apbase = require 'ApBaze'
local mark_xml_cache = require "mark_xml_cache"


local printf = utils.printf
local sprintf = utils.sprintf
local errorf = utils.errorf

local SelectNodes = xml_utils.SelectNodes

local GetGapType -- definition

local xml_cache = mark_xml_cache.MarkXmlCache(100)

local function readParam(parent)
	local res = {}
	for node in SelectNodes(parent, "PARAM[@name and @value and not(@type)]") do
		local name = node.attributes:getNamedItem("name").nodeValue
		local value = node.attributes:getNamedItem("value").nodeValue
		res[name] = tonumber(value) or value
	end
	return res
end

local RAILWAY_TYPES = {
	WAY = "путь",
	JOINT = "стрелка",
	SCB = "СЦБ",
}

-- =================== ШИРИНА ЗАЗОРА ===================

-- получить все ширины из отметки
-- возвращает таблицу [тип][номер канала] = ширина
local function GetAllGapWidth(mark)
	local res = {}

	local ext = mark.ext
	for _, name in pairs{"VIDEOIDENTGWT", "VIDEOIDENTGWS"} do
		local w = name and ext[name]
		if w then
			res[name] = {[0] = tonumber(w)}
		end
	end

	local nodeRoot = xml_cache:get(mark)
	if nodeRoot then
		local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and starts-with(@value, "CalcRailGap")]\z
		/PARAM[@name="FrameNumber" and @value="0" and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="RailGapWidth_mkm" and @value]/@value'

		for node in SelectNodes(nodeRoot, req) do
			local node_gap_type =  node:SelectSingleNode("../../../../@value").nodeValue
			local width = tonumber(node.nodeValue) / 1000

			local node_channel = node:SelectSingleNode("../../../../@channel")
			local channel = node_channel and tonumber(node_channel.nodeValue) or 0

			if not res[node_gap_type] then
				res[node_gap_type] = {}
			end
			res[node_gap_type][channel] = width
		end
	end

	return res
end


-- выбрать ширину зазора из таблицы {номер_канала:ширина} в соответствии с приоритетами каналов,
-- сначала 19,20 (внешняя камера), потом 17,18 (внутренняя), остальные (в тч. непромаркированные)
-- возвращает ширину, и номер откуда взята
local function SelectWidthFromChannelsWidths(channel_widths, mark)
	if channel_widths then
		-- сначала проверим известные каналы
		for _, n in ipairs{19, 20, 17, 18} do
			if channel_widths[n] then
				return channel_widths[n], n
			end
		end

		-- а потом хоть какой нибудь
		for n, width in pairs(channel_widths) do
			if n == 0 and mark then
				n = utils.GetSelectedBits(mark.prop.ChannelMask)
				n = n and n[1]
				return width, n
			end
		end
	end
	return nil
end

-- получить результирующую ширину зазора
local function GetGapWidth(mark)
	local widths = GetAllGapWidth(mark)

	-- сначала проверим установленные пользователем ширины
	-- если их нет, то сначала проверим ширину по боковой грани, потом по пов. катания
	local src_names = {
		'CalcRailGap_User',
		'VIDEOIDENTGWS',
		'VIDEOIDENTGWT',
		'CalcRailGap_Head_Side',
		'CalcRailGap_Head_Top',
	}
	for _, name in ipairs(src_names) do
		if widths[name] then
			return SelectWidthFromChannelsWidths(widths[name], mark)
		end
	end
	-- ничего не нашли
	return nil
end

-- получить конкретную ширину зазора ('inactive', 'active', 'thread', 'user', nil)
local function GetGapWidthName(mark, name)
	if not name then
		return GetGapWidth(mark)
	end

	local widths = GetAllGapWidth(mark)

	if name == 'inactive' then -- нерабочая: боковая по 19,20 каналу
		local w = widths.CalcRailGap_Head_Side
		if w then
			if w[19] then return w[19], 19 end
			if w[20] then return w[20], 20 end
		end
	elseif name == 'active' then -- рабочая: боковая по 17,18 каналу
		local w = widths.CalcRailGap_Head_Side
		if w then
			if w[17] then return w[17], 17 end
			if w[18] then return w[18], 18 end
			if w[0] then
				local video_channel = utils.GetSelectedBits(mark.prop.ChannelMask)
				video_channel = video_channel and video_channel[1]
				return w[0], video_channel
			end
		end
	elseif name == 'thread' then -- поверх катания:
		local w = widths.CalcRailGap_Head_Top
		return SelectWidthFromChannelsWidths(w, mark)
	elseif name == 'user' then -- поверх катания:
		for _, n in ipairs{'CalcRailGap_User', 'VIDEOIDENTGWS', 'VIDEOIDENTGWT'} do
			if widths[n] then
				return SelectWidthFromChannelsWidths(widths[n], mark)
			end
		end
		return nil
	end
	return nil
end

-- получить высоты ступеньки на стыке
local function GetRailGapStep(mark)
	local nodeRoot = xml_cache:get(mark)
	local node = nodeRoot and nodeRoot:SelectSingleNode('\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="CalcRailGapStep"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="RailGapStepWidth" and @value]/@value')
	return node and utils.round(tonumber(node.nodeValue)/1000, 0)
end


-- ================================= Маячные отметки ====================================

--получить смещенеи маячной отметки
local function GetBeaconOffset(mark)
	local nodeRoot = xml_cache:get(mark)
	local node = nodeRoot and nodeRoot:SelectSingleNode('\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="Beacon_Web"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="Shift_mkm" and @value]/@value')
	local offset = node and tonumber(node.nodeValue)/1000
	if offset and Passport.INCREASE == '1' then
		offset = -offset  -- https://bt.abisoft.spb.ru/view.php?id=908
	end
	return offset
end

-- ================================= БОЛТЫ ====================================

-- получить массив с качествами болтов
local function GetCrewJointArray(mark)
	local nodeRoot = xml_cache:get(mark)
	if not nodeRoot	then
		return nil
	end

	local req_safe = '\z
		PARAM[@name="FrameNumber" and @value]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="JointNumber" and @value]\z
		/PARAM[@name="CrewJointSafe" and @value]/@value'

	local res = {}

	for nodeCrewJoint in SelectNodes(nodeRoot, '/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="CrewJoint"]') do
		local video_channel = nodeCrewJoint:SelectSingleNode("@channel")
		video_channel = video_channel and tonumber(video_channel.nodeValue) or 0

		local cur_safe = {}
		for node in SelectNodes(nodeCrewJoint, req_safe) do
			local safe = tonumber(node.nodeValue)
			cur_safe[#cur_safe+1] = safe
		end
		res[video_channel] = cur_safe
	end

	res = res[17] or res[18] or res[19] or res[20] or res[0]
	return res
end


-- посчитать количество нормальных дефектных и нетиповых болтов в массиве в заданном диапазоне
local function CalcJointDefectInRange(joints, first, last)
	local defects, valid, atypical = 0, 0, 0
	for i = first or 1, last or #joints do
		local safe = joints[i]
		if safe > 0 then
			if safe == 4 then
				atypical = atypical + 1
			end
			valid = valid + 1
		else
			defects = defects + 1
		end
	end
	return valid, defects, atypical
end


-- извлечь количество и качество болтов из xml (если распз по неск каналам, то данные берутся последовательно из 17/18 потом из 19/20)
local function GetCrewJointCount(mark)
	local joints = GetCrewJointArray(mark)
	if joints then
		local valid, defects, atypical = CalcJointDefectInRange(joints)
		return #joints, defects, atypical
	end
end

-- проверить стык на дефектность по наличие болтов (не больше одного плохого в половине накладки)
local function CalcValidCrewJointOnHalf(mark)
	local joints = GetCrewJointArray(mark)
	local valid_on_half = nil
	local broken_on_half = nil

	if joints and #joints ~= 0 then
		if true then
			--[[ https://bt.abisoft.spb.ru/view.php?id=733
				на картинке выделено синим 5/0
				5 болтов найдено неисправных - 0
				выдано закрытие.
				но один не найден.
				надо добавить его к неисправным.
				тогда результат будет 6/1
				и дальше использовать эти данные.

				для другой строки где 3/0 считать 4/1, хотя это условие более спорное

				т.е. если число болтов 5 - считаем накладку 6-дырной
					если число болтов 3 - считаем накладку 4-дырной (если возможно в коде пометить где его отключать)
			]]
			if joints and (#joints == 3 or #joints == 5) then
				table.insert(joints, -1)
			end
		end

		if #joints == 6 then
			local l = CalcJointDefectInRange(joints, 1, 3)
			local r = CalcJointDefectInRange(joints, 4, 6)
			valid_on_half = math.min(l, r)
		elseif #joints == 4 then
			local l = CalcJointDefectInRange(joints, 1, 2)
			local r = CalcJointDefectInRange(joints, 3, 4)
			valid_on_half = math.min(l, r)
		else
			valid_on_half = 0
		end

		broken_on_half = math.ceil(#joints/2) - valid_on_half
	end

	return valid_on_half, broken_on_half, (joints and #joints)
end

-- =================== Накладка ===================

local function GetFishplateState(mark)
	local res = -1
	local cnt = 0

	local nodeRoot = xml_cache:get(mark)
	if nodeRoot then
		local req = '\z
			ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and @value="Fishplate"]\z
			/PARAM[@name="FrameNumber" and @value]\z
			/PARAM[@name="Result" and @value="main"]\z
			/PARAM[@name="FishplateState"]\z
			/PARAM[@name="FishplateFault" and @value]/@value'

		for nodeFault in SelectNodes(nodeRoot, req) do
			local fault = tonumber(nodeFault.nodeValue)
			res = math.max(res, fault)
			if fault > 0 then
				cnt = cnt + 1
			end
		end
	end
	return res, cnt
end

-- =================== Скрепления ===================

local function IsFastenerDefect(mark)
	local xpath = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="Fastener"]\z
		//PARAM[@name="FastenerFault" and @value]/@value'
	local nodeRoot = xml_cache:get(mark)
	if nodeRoot then
		local node = nodeRoot:SelectSingleNode(xpath)
		if node then
			node = tonumber(node.nodeValue)
			return node ~= 0
		end
	end
end

local function GetFastenetParams(mark)
	local nodeRoot = xml_cache:get(mark)
	if nodeRoot	then
		local res = {}
		for node_frame in SelectNodes(nodeRoot, '/ACTION_RESULTS/PARAM[@value="Fastener"]/PARAM[@name="FrameNumber" and @value="0" and @coord]') do
			res['frame_coord'] = tonumber(node_frame:SelectSingleNode('@coord').nodeValue)
			for node_param in SelectNodes(node_frame, 'PARAM/PARAM[@name and @value]') do
				local name, value = xml_utils.xml_attr(node_param, {'name', 'value'})
				res[name] = tonumber(value) or value
			end
		end

		local roc = 'RecogObjCoord'
		local node = nodeRoot:SelectSingleNode('//PARAM[@name="' .. roc .. '" and @value]/@value')
		if node then
			res[roc] = tonumber(node.nodeValue)
		end

		return res
	end
end

-- =================== Поверхностные дефекты ===================

local function GetSurfDefectPrm(mark)
	local res = {}

	local nodeRoot = xml_cache:get(mark)
	if nodeRoot then
		local req = '\z
		/ACTION_RESULTS\z
		/PARAM[starts-with(@value, "Surface")]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name and @value]'
		for node_param in SelectNodes(nodeRoot, req) do
			local name, value = xml_utils.xml_attr(node_param, {'name', 'value'})
			if value and name and name:find('Surface') then
				value = tonumber(value)
			end
			res[name] = value
		end

		if 1 then
			if res.SurfaceWidth then
				res.SurfaceWidth = res.SurfaceWidth/10
			end

			if res.SurfaceLength then
				res.SurfaceLength = (res.SurfaceLength/10) or 0
			end

			if not res.SurfaceArea and res.SurfaceWidth and res.SurfaceLength then
				res.SurfaceArea = res.SurfaceWidth * res.SurfaceLength / 100
			end
			if res.SurfaceArea then
				res.SurfaceArea = res.SurfaceArea / 100
			end
		end
		return res
	end
end

-- =================== Коннекторы ===================

local CONNECTOR_TYPE = {
	GOOD 		= -2,
	MISSING     = -1,	-- defect
	BOLT 		= 0,	-- good
	KLIN 		= 1,	-- good
	MIS_SCREW 	= 2,	-- defect
	TWO_SCREW 	= 3,	-- good
	HOLE  		= 4,	-- defect
	UNDEFINED 	= 100,	-- defect
}

--[[
	+----------------+--------------------------------------------------------------+
	| ConnectorFault |                        ConnectorType                         |
	+----------------+--------------------------------------------------------------+
	| 0-исправен     | 0-болт, 1-клин, 3-есть две гайки                             |
	| 1-неисправен   | 2-отсутствие 1 или 2 гайки, 4-дырка, 100-не определено       |
	+----------------+--------------------------------------------------------------+
]]
local CONNECTOR_TYPE_DEFECT = {
	[CONNECTOR_TYPE.MISSING] 	= true,
	[CONNECTOR_TYPE.MIS_SCREW] 	= true,
	[CONNECTOR_TYPE.HOLE] 		= true,
	[CONNECTOR_TYPE.UNDEFINED] 	= true,
}

local WELDEDBOND_TYPE = {
	MISSING 	= -1,
	GOOD 		= 0,
	DEFECT 		= 1,
	BAD_CABLE 	= 2,
}

local function GetConnecterType(mark)
	local res = {}
	local req = '\z
		/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Connector"]\z
		/PARAM[@name="FrameNumber" and @value]\z
		/PARAM[@name="Result" and @value="main"]'

	local nodeRoot = xml_cache:get(mark)
	if nodeRoot	then
		for node in SelectNodes(nodeRoot, req) do
			local node_video_channel = node:SelectSingleNode("../../@channel")
			local video_channel_num = node_video_channel and tonumber(node_video_channel.nodeValue)
			if video_channel_num then
				if not res[video_channel_num] then res[video_channel_num] = {} end

				local params = readParam(node)
				if not params.ConnectorType then
					params.ConnectorType = (params.ConnectorFault == 0) and CONNECTOR_TYPE.BOLT or CONNECTOR_TYPE.MIS_SCREW
				end

				table.insert(res[video_channel_num], params.ConnectorType)
			end
		end
	end

	local function is_defect(arr)
		for _, t in ipairs(arr or {}) do
			if CONNECTOR_TYPE_DEFECT[t] then
				return true
			end
		end
	end

	if res[17] then
		return res[17], res[19], is_defect(res[17]) or is_defect(res[19])
	elseif res[18] then
		return res[18], res[20], is_defect(res[18]) or is_defect(res[20])
	else
		return {CONNECTOR_TYPE.MISSING}, {CONNECTOR_TYPE.MISSING}, true
	end
end

-- получить полное количество, колич. дефектных
local function GetConnectorsCount(mark)
	local types = GetConnecterType(mark)
	if #types == 1 and types[1] == CONNECTOR_TYPE.MISSING then
		return 0, 0
	end

	local fault = 0
	for _, t in ipairs(types) do
		if CONNECTOR_TYPE_DEFECT[t] then
			fault = fault + 1
		end
	end
	return #types, fault
end

-- =================== Приварной соединитель ===================

-- получить статус конектора (WeldedBond) из описания стыка
local function GetWeldedBondStatus(mark)
	local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="WeldedBond"]\z
		/PARAM[@name="FrameNumber" and @value]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="ConnectorFault" and @value]\z
		/@value'

	local nodeRoot = xml_cache:get(mark)
	local nodeFault = nodeRoot and nodeRoot:SelectSingleNode(req)
	return nodeFault and tonumber(nodeFault.nodeValue) or WELDEDBOND_TYPE.MISSING
end

local function getPrivarnoyDefectCode(privarnoy, railway_type)
	if privarnoy == WELDEDBOND_TYPE.BAD_CABLE then
		local codes = {
			[RAILWAY_TYPES.WAY] 	= DEFECT_CODES.JOINT_WELDED_BOND_FAULT_WAY[1],
			[RAILWAY_TYPES.JOINT] 	= DEFECT_CODES.JOINT_WELDED_BOND_FAULT_JOINT[1],
			[RAILWAY_TYPES.SCB]   	= DEFECT_CODES.JOINT_WELDED_BOND_FAULT_SCB[1],
		}
		return codes[railway_type]
	end

	if privarnoy == WELDEDBOND_TYPE.MISSING or
	   privarnoy == WELDEDBOND_TYPE.DEFECT then
		local codes = {
			[RAILWAY_TYPES.WAY] 	= DEFECT_CODES.JOINT_WELDED_BOND_MISSING_WAY[1],
			[RAILWAY_TYPES.JOINT] 	= DEFECT_CODES.JOINT_WELDED_BOND_MISSING_JOINT[1],
			[RAILWAY_TYPES.SCB]   	= DEFECT_CODES.JOINT_WELDED_BOND_MISSING_SCB[1],
		}
		return codes[railway_type]
	end
end

-- получить Код дефекта конектора (WeldedBond) из описания стыка
local function GetWeldedBondDefectCode(mark)
	local gap_type = GetGapType(mark)
	if not gap_type or gap_type == 0 then
		local railway_type = mark.ext.RAILWAY_TYPE or RAILWAY_TYPES.WAY
		local status = GetWeldedBondStatus(mark)
		return getPrivarnoyDefectCode(status, railway_type)
	end
end

--[[
	+------------------------+------------+------------+------------------------+-------------------+
	| Тип перемычки/         | Где        | Имя ноды   | Атрибут                | Название в списке |
	| соединителя            | расположен |            |                        |                   |
	+========================+============+============+========================+===================+
	| Приварной              | Болтовой   | WeldedBond | ConnectorFault=1       | Оборван           |
	| (Основной)             | стык       |            | ConnectorFault=2       | Поврежден трос    |
	+------------------------+------------+------------+------------------------+-------------------+
	| Штепсельный            | Болтовой   | Connector  | Нет блока              | Нет отверстия     |
	| (Дублирующий)          | стык       |            | ConnectorType=2        | Нет гаек          |
	|                        |            |            | ConnectorType=4        | Отверстие         |
	|                        |            |            | ConnectorType=100      | Нет отверстия     |
	+------------------------+------------+------------+------------------------+-------------------+
	| Дроссельная перемычка  | изостык    | Connector  | Нет блока              | Нет отверстия     |
	| (Дроссель)             |            |            | ConnectorType=2        | Нет гаек          |
	|                        |            |            | ConnectorType=4        | Отверстие         |
	|                        |            |            | ConnectorType=100      | Нет отверстия     |
	+------------------------+------------+------------+------------------------+-------------------+
	| Бутлежная перемычка    | Признака   |            | CableConnector         | «Расположение     |
	| (Тросовая перемычка)   | стыка нет  |            | CableConnectorBothRail | объекта»          |
	+------------------------+------------+------------+------------------------+-------------------+
]]
local function GetJoinConnectors(mark)
	local gap_type = GetGapType(mark)
	local connector, _, connector_defected = GetConnecterType(mark)
	
	local defected = false
	local res = {}

	if not gap_type or gap_type == 0 then -- болтовой
		res.privarnoy = GetWeldedBondStatus(mark)
		res.shtepselmii = connector
		defected = connector_defected or res.privarnoy ~= WELDEDBOND_TYPE.GOOD
	elseif gap_type == 1 then -- изолированный
		res.drossel = connector
		defected = connector_defected
	end
	return res, defected, gap_type
end

local function GetJoinConnectorDefected(mark)
	local connectors = GetJoinConnectors(mark)
	if connectors.privarnoy == WELDEDBOND_TYPE.GOOD then
		connectors.privarnoy = nil
	end

	local function clean_good_connector(arr)
		local res = {}
		for _, val in ipairs(arr) do
			if CONNECTOR_TYPE_DEFECT[val] then
				table.insert(res, val)
			end
		end
		return #res > 0 and res
	end

	if connectors.drossel then
		connectors.drossel = clean_good_connector(connectors.drossel)
	end

	if connectors.shtepselmii then
		connectors.shtepselmii = clean_good_connector(connectors.shtepselmii)
	end

	return connectors
end

local function GetJoinConnectorDefectCodes(mark)
	local connectors = GetJoinConnectorDefected(mark)
	local railway_type = mark.ext.RAILWAY_TYPE or RAILWAY_TYPES.WAY
	local res = {}

	local privarnoy_defect_code = getPrivarnoyDefectCode(connectors.privarnoy, railway_type)
	table.insert(res, privarnoy_defect_code)

	for _, shtepselmii in ipairs(connectors.shtepselmii or {}) do
		if shtepselmii == CONNECTOR_TYPE.MIS_SCREW then
			local codes = {
				[RAILWAY_TYPES.WAY]		= DEFECT_CODES.JOINT_CONNECTOR_SCREW_FAULT_WAY[1],
				[RAILWAY_TYPES.JOINT] 	= DEFECT_CODES.JOINT_CONNECTOR_SCREW_FAULT_JOINT[1],
				[RAILWAY_TYPES.SCB]   	= DEFECT_CODES.JOINT_CONNECTOR_SCREW_FAULT_SCB[1],
			}
			table.insert(res, codes[railway_type])
		elseif shtepselmii == CONNECTOR_TYPE.HOLE or 
			   shtepselmii == CONNECTOR_TYPE.MISSING then
			local codes = {
				[RAILWAY_TYPES.WAY] 	= DEFECT_CODES.JOINT_CONNECTOR_FAULT_WAY[1],
				[RAILWAY_TYPES.JOINT] 	= DEFECT_CODES.JOINT_CONNECTOR_FAULT_JOINT[1],
				[RAILWAY_TYPES.SCB]   	= DEFECT_CODES.JOINT_CONNECTOR_FAULT_SCB[1],
			}
			table.insert(res, codes[railway_type])
		elseif shtepselmii == CONNECTOR_TYPE.UNDEFINED then
			local codes = {
				[RAILWAY_TYPES.WAY] 	= DEFECT_CODES.JOINT_CONNECTOR_HOLE_MISSING_WAY[1],
			}
			table.insert(res, codes[railway_type])
		end
	end

	for _, drossel in ipairs(connectors.drossel or {}) do
		if drossel == CONNECTOR_TYPE.MIS_SCREW then
			local codes = {
				[RAILWAY_TYPES.WAY] 	= DEFECT_CODES.ISO_CONNECTOR_INSUFFICIENCY_WAY[1],
				[RAILWAY_TYPES.JOINT] 	= DEFECT_CODES.ISO_CONNECTOR_INSUFFICIENCY_JOINT[1],
				[RAILWAY_TYPES.SCB]   	= DEFECT_CODES.ISO_CONNECTOR_INSUFFICIENCY_SCB[1],
			}
			table.insert(res, codes[railway_type])
		end
	end

	return algorithm.clean_array_dup_stable(res)
end

-- =================== Шпалы ===================

-- получить параметры шпалы
local function GetSleeperParam(mark)
	local nodeRoot = xml_cache:get(mark)
	if not nodeRoot	then
		return nil
	end

	local req = '\z
		/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Sleepers"]\z
		/PARAM[@name and @value]'

	local res = {}

	for node in SelectNodes(nodeRoot, req) do
		local name = node:SelectSingleNode("@name").nodeValue
		local val = node:SelectSingleNode("@value").nodeValue
		res[name] = tonumber(val)
	end

	return res
end

-- получить разворот шпалы (возвращает значение в радианах * 1000)
local function GetSleeperAngle(mark)
	local ext = mark.ext

	if ext.SLEEPERS_ANGLE then
		return ext.SLEEPERS_ANGLE
	end

	local nodeRoot = xml_cache:get(mark)
	if nodeRoot then
		local req = '\z
			/ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and @value="Sleepers"]\z
			/PARAM[@name="Angle_mrad" and @value]/@value'
		local node = nodeRoot:SelectSingleNode(req)
		return node and tonumber(node.nodeValue)
	end
end

-- получить параметры дефекта шпалы
local function GetSleeperFault(mark)
	local res = {}
	local ext = mark.ext

	local nodeRoot = xml_cache:get(mark)
	if nodeRoot then
		local req = '\z
			/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Sleeper"]\z
			//PARAM[@name="SleeperFault"]\z
			/PARAM[@name and @value]'
		for node in SelectNodes(nodeRoot, req) do
			local name, value = xml_utils.xml_attr(node, {'name', 'value'})
			res[name] = tonumber(value) or value
		end
	end
	return res
end


-- получить материал шпалы
local function GetSleeperMeterial(mark)
	local ext = mark.ext

	if ext.SLEEPERS_METERIAL then
		return ext.SLEEPERS_METERIAL
	end

	local nodeRoot = xml_cache:get(mark)
	if nodeRoot then
		local req = '\z
			/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Sleepers"]\z
			/PARAM[@name="Material" and @value]/@value'
		local node = nodeRoot:SelectSingleNode(req)
		return node and tonumber(node.nodeValue)
	end
end

local SLEEPER_MATERIAL_TO_MAX_DIFFS =
{
	[1] = 2*40, -- "бетон",
	[2] = 2*80, -- "дерево",
}

-- проверить эпюру шпалы
local function CheckSleeperEpure(mark, sleeper_count, MEK, dist_to_next, cur_material)
	local ref_dist = 1000000 / sleeper_count

	if not cur_material then
		cur_material = GetSleeperMeterial(mark)
	end
	local max_diff = SLEEPER_MATERIAL_TO_MAX_DIFFS[cur_material] or 80

	local function check()
		if dist_to_next < 200 then
			return true
		end
		for i = 1, MEK do
			if math.abs(dist_to_next/i - ref_dist) <= max_diff then
				return true
			end
		end
		return false
	end

	local defect_code = ""
	local dist_ok = check()

	if not dist_ok and cur_material then
		if cur_material == 1 then -- "бетон",
			defect_code = DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE[1]
		elseif cur_material == 2 then -- "дерево",
			defect_code = DEFECT_CODES.SLEEPER_DISTANCE_WOODEN[1]
		end
	end

	return dist_ok, defect_code
end

-- =================== Вспомогательные ===================

-- фильтрация отметок
local function filter_marks(marks, fn, progress_callback)
	if not fn then
		return marks
	end

	local res = {}
	for i = 1, #marks do
		local mark = marks[i]
		if fn(mark) then
			res[#res+1] = mark
		end
		if progress_callback then
			progress_callback(#marks, i, #res)
		end
	end
	return res
end

-- фильтрация отметок по USER_ACCEPT. values = {[-1]=true, [0]=false, [1]=true}
local function filter_user_accept(marks, values, progress_callback)
	if not values then
		return marks
	end

	local res = {}
	for i = 1, #marks do
		local mark = marks[i]
		local ua = mark.ext.ACCEPT_USER or -1

		if values[ua] then
			res[#res+1] = mark
		end
		--print(i, mark.prop.dwID, ua, #res)
		if progress_callback then
			progress_callback(#marks, i, #res)
		end
	end
	return res
end

-- сортировка отметок
local function sort_marks(marks, fn, inc, progress_callback)
	if inc == nil then inc = true end
	inc = inc and inc ~= 0
	local start_time = os.clock()

	local keys = {}	-- массив ключей, который будем сортировать
	for i = 1, #marks do
		local mark = marks[i]
		local key = fn(mark)	-- создадим ключ (каждый ключ - массив), с сортируемой характеристикой
		key[#key+1] = i 		-- добавим текущий номер отметки номер последним элементом, для стабильности сортировки
		keys[#keys+1] = key 	-- и вставим в таблицу ключей
		if progress_callback then
			progress_callback(#marks, i)
		end
	end

	assert(#keys == #marks)
	local fetch_time = os.clock()

	local compare_fn = function(t1, t2)  -- функция сравнения массивов, поэлементное сравнение
		for i = 1, #t1 do
			local a, b = t1[i], t2[i]
			if a < b then return inc end
			if b < a then return not inc end
		end
		return false
	end
	table.sort(keys, compare_fn)  -- сортируем массив с ключами
	local sort_time = os.clock()

	local tmp = {}	-- сюда скопируем отметки в нужном порядке
	for i, key in ipairs(keys) do
		local mark_pos = key[#key] -- номер отметки в изначальном списке мы поместили последним элементом ключа
		tmp[i] = marks[mark_pos] -- берем эту отметку и помещаем на нужное место
	end
	local copy_res_time = os.clock()
	-- print(inc, #marks, #tmp)
	--printf('fetch: %.2f,  sort = %.2f, copy_res = %.2f', fetch_time - start_time, sort_time-fetch_time, copy_res_time-sort_time)
	--print("mem before KB: ", collectgarbage("count"))
	marks = nil
	key = nil
	collectgarbage()
	--print("mem after KB: ", collectgarbage("count"))
	return tmp
end


-- другой способ сортировки, должен быть быстрее чем sort_marks
local function sort_stable(marks, fn, inc, progress_callback)
	local start_time = os.clock()

	local keys = {}	-- массив ключей, который будем сортировать
	local key_nums = {} -- таблица ключ - массив позиций исходных отметок

	if true and #marks > 0 and marks[1].prop and marks[1].prop.ID then
		-- оптимизация для специальных пользовательских отметок,
		-- их свойства лучше читать последовательно по ID, тк доп свойства кешируются

		local id2mark = {}	-- таблица id-отметка
		local ids = {}		-- id отметок
		for i = 1, #marks do
			local mark = marks[i]
			local mark_id = mark.prop.ID
			id2mark[mark_id] = mark
			ids[#ids + 1] = mark_id
		end
		table.sort(ids)		-- сортируем ID отметок
		local id2val = {}
		for _, mark_id in ipairs(ids) do
			-- проходим по отмекам упрорядоченным по ID и получаем нужные свойства
			local mark = id2mark[mark_id]
			id2val[mark_id] = fn(mark)
		end
		-- переопределяем функцию получения значения, чтобы читать закешированные значения
		fn = function(mark)
			local id = mark.prop.ID
			return id2val[id] or 0
		end
	end

	for i = 1, #marks do
		local mark = marks[i]
		local key = fn(mark) or 0	-- создадим ключ, с сортируемой характеристикой

		local nms = key_nums[key]
		if not nms then
			nms = {i}
			key_nums[key] = nms
			keys[#keys+1] = key 	-- вставим в таблицу ключей
		else
			nms[#nms + 1] = i
		end

		if progress_callback then
			progress_callback(#marks, i)
		end
	end
	local fetch_time = os.clock()

	table.sort(keys)  -- сортируем массив с ключами
	local sort_time = os.clock()

	if inc == false or inc == 0 then
		algorithm.reverse_array(keys)
	end
	local rev_time = os.clock()

	local tmp = {}	-- сюда скопируем отметки в нужном порядке
	for _, key in ipairs(keys) do
		local nums = key_nums[key]
		for _, i in ipairs(nums) do
			tmp[#tmp + 1] = marks[i]
		end
	end
	local copy_res_time = os.clock()
	-- print(inc, #marks, #tmp)
	--printf('fetch: %.2f,  sort = %.2f, rev = %.2f copy_res = %.2f', fetch_time - start_time, sort_time-fetch_time, rev_time-sort_time, copy_res_time-rev_time)

	--print("mem before KB: ", collectgarbage("count"))
	marks = nil
	key = nil
	key_nums = nil
	collectgarbage()
	--print("mem after KB: ", collectgarbage("count"))
	return tmp
end


-- возвращает форматированную путейскую координату начала отметки
local function format_path_coord(mark)
	local km, m, mm = Driver:GetPathCoord(mark.prop.SysCoord)
	local res = sprintf('%d км %.1f м', km, m + mm/1000)
	return res
end

local function format_sys_coord(coord)
    local s = string.format("%d", coord)
    s = s:reverse():gsub('(%d%d%d)','%1.'):reverse()
    return s
end

-- отсортировать отметки по системной координате
local function sort_mark_by_coord(marks)
	return sort_stable(marks, function(mark)
		return mark.prop.SysCoord
	end)
end

-- вычислить назание рельса по отметке
local function GetRailName(mark)
	local mark_rail = mark
	if type(mark_rail) == 'table' or type(mark_rail) == 'userdata' then
		mark_rail = mark.prop.RailMask
	elseif type(mark_rail) == 'number' then
		-- ok
	else
		errorf('type of mark must be number or Mark(table), got %s', type(mark))
	end
	mark_rail = bit32.band(mark_rail, 0x03)

	if mark_rail == 0x03 then
		return "Оба"
	end

	local right_rail_mask = tonumber(Passport.FIRST_LEFT) + 1
	return bit32.btest(mark_rail, right_rail_mask) and "Правый" or "Левый"
end

-- определяет рельсовое расположение отметки. возвращает: -1 = левый, 0 = оба, 1 = правый
local function GetMarkRailPos(mark)
	local mark_rail = mark
	if type(mark_rail) == 'table' or type(mark_rail) == 'userdata' then
		mark_rail = mark.prop.RailMask
	elseif type(mark_rail) == 'number' then
		-- ok
	else
		errorf('type of mark must be number or Mark(table), got %s', type(mark))
	end

	mark_rail = bit32.band(mark_rail, 0x3)
	if mark_rail == 3 then
		return 0
	end

	local left_mask = tonumber(Passport.FIRST_LEFT) + 1
	return left_mask == mark_rail and 1 or -1
end

-- получить температуру у отметки
local function GetTemperature(mark)
	if mark and mark.prop then
		local rail = bit32.btest(mark.prop.RailMask, 0x01) and 0 or 1
		local temp = Driver:GetTemperature(rail, mark.prop.SysCoord)

		local v = temp and (temp.target or temp.head)
		if v then
			return math.floor(v + 0.5)
		end
	end
end

local function prepare_row_path(row, prefix, coord)
	local km, m, mm = Driver:GetPathCoord(coord)
	if km then
		row[prefix .. 'KM'] = km
		row[prefix .. 'M'] = m
		row[prefix .. 'MM'] = mm
		row[prefix .. 'M_MM1'] = sprintf('%.1f', m + mm/1000)
		row[prefix .. 'M_MM2'] = sprintf('%.2f', m + mm/1000)
		row[prefix .. 'PK'] = sprintf('%d', m/100+1)
		row[prefix .. 'PATH'] = sprintf('%d км %.1f м', km, m + mm/1000)
	end
	return km, m
end

local function prepare_row_gps(row, mark)
	local function fmt(val)
		if not val then return '' end
		local sign = val < 0 and -1 or 1
		val = math.abs(val)
		local d = math.floor(val)
		val = (val - d) * 60
		local m = math.floor(val)
		local s = (val-m) * 60
		return string.format("%d %2d' %.3f''", d*sign, m, s)
	end
	local function fmt_row(val)
		if not val then return '' end
		return string.format("%.8f", val)
	end

	local lat, lon
	if Driver.GetGPS then
		lat, lon = Driver:GetGPS(mark.prop.SysCoord + mark.prop.Len/2)
	end

	row.LAT = fmt(lat)
	row.LON = fmt(lon)
	row.LAT_RAW = fmt_row(lat)
	row.LON_RAW = fmt_row(lon)
end

local vel_table
local function get_preset_velocity(km, m)
	if not vel_table and EKASUI_PARAMS then
		vel_table = apbase.VelocityTable()
		vel_table:loadPsp(Passport)
	end
	return vel_table and vel_table:format(km, m)
end

-- создание таблицы подстановок с общими параметрами отметки
local function MakeCommonMarkTemplate(mark)
	local rails_names = {
		[-1]= 'лев.',
		[0] = 'оба',
		[1] = 'прав.'}
	local prop = mark.prop
	local sys_center = prop.SysCoord + prop.Len / 2
	local inc_offset = Passport.INCREASE == '0' and (-prop.Len / 2) or (prop.Len / 2)

	local row = {}
	local temperature = GetTemperature(mark)

	prepare_row_path(row, "BEGIN_", 	sys_center-inc_offset)
	local km, m = prepare_row_path(row, "", 		sys_center)
	prepare_row_path(row, "END_", 	sys_center+inc_offset)

	row.mark_id = prop.ID
	row.SYS = prop.SysCoord
	row.LENGTH = prop.Len
	row.GUID = prop.Guid
	row.TYPE = Driver:GetSumTypeName(prop.Guid)
	row.DESCRIPTION = prop.Description

	row.RAIL_RAW_MASK = prop.RailMask
	row.RAIL_POS = GetMarkRailPos(mark)
	row.RAIL_NAME = rails_names[row.RAIL_POS]
	row.RAIL_TEMP = temperature and sprintf('%+.1f', temperature) or ''

	prepare_row_gps(row, mark)

	row.DEFECT_CODE = ''
	row.DEFECT_DESC = ''

	row.PRESET_VELOCITY = get_preset_velocity(km, m)

	return row
end

-- получить описания запусков распознавания
local function GetRecognitionStartInfo()
	local guids_recog_info = {'{1D5095ED-AF51-43C2-AA13-6F6C86302FB0}'}
	local marks = Driver:GetMarks{ListType='all', GUIDS=guids_recog_info}
	marks = sort_stable(marks, function(mark) return mark.prop.ID end)

	-- for i, mark in ipairs(marks) do print(i, mark.prop.ID, park.prop.SysCoord) end

	local infos  = {}
	for _, mark in ipairs(marks) do
		local desc = mark and mark.prop.Description
		if desc and #desc > 0 then
			local info = {}
			for k, v in string.gmatch(desc, '([%w_]+)=([%w%.]+)') do
				info[k] = v
			end
			table.insert(infos, info)
		end
	end
	return infos
end

-- получить таблицу паспорта с доп параметрами
local function GetExtPassport(psp)
	psp = psp or Passport

	if not _ext_passport_table then
		_ext_passport_table = {}
		for n,v in pairs(psp) do
			_ext_passport_table[n] = v
		end

		local data_format = ' %Y-%m-%d %H:%M:%S '
		_ext_passport_table.REPORT_DATE = os.date(data_format)

		local recog_info = GetRecognitionStartInfo()
		if recog_info and #recog_info > 0 then
			local info = recog_info[#recog_info]

			if info.RECOGNITION_START then
				_ext_passport_table.RECOGNITION_START = os.date(data_format, info.RECOGNITION_START)
			end

			if info.RECOGNITION_DLL_CTIME then
				_ext_passport_table.RECOG_VERSION_DATE = os.date(data_format, info.RECOGNITION_DLL_CTIME)
			end

			if info.RECOGNITION_DLL_VERSION then
				local ver = info.RECOGNITION_DLL_VERSION
				_ext_passport_table.RECOG_VERSION = ver
				_ext_passport_table.RECOG_VERSION_MAJOR = string.match(ver, '(%d+)%.')
			end
		end
	end
	return _ext_passport_table
end

-- построить изображение для данной отметки
local function MakeMarkImage(mark, video_channel, show_range, base64)
	local img_path

	if ShowVideo ~= 0 then
		local prop = mark.prop

		if not video_channel then
			local recog_video_channels = utils.GetSelectedBits(prop.ChannelMask)
			video_channel = recog_video_channels and recog_video_channels[1]
		end

		local panoram_width = 1500
		local width = 400
		local mark_id = (ShowVideo == 1) and prop.ID or 0

		if show_range then
			panoram_width = show_range[2] - show_range[1]
			width = panoram_width / 10
			if ShowVideo == 1 then
				mark_id = -1
			end
		end

		if video_channel then
			local img_prop = {
				mark_id = mark_id,
				mode = 3,  -- panoram
				panoram_width = panoram_width,
				-- frame_count = 3,
				width = width,
				height = 300,
				base64=base64
			}

			--print(prop.ID, prop.SysCoord, prop.Guid, video_channel)
			local coord = show_range and (show_range[1] + show_range[2])/2 or prop.SysCoord
			img_path = Driver:GetFrame(video_channel, coord, img_prop)
		end
	end
	return img_path
end

-- сделать строку ссылку для открытия атейпа на данной отметке
function MakeMarkUri(markid)
	local link = sprintf(" -g %s -mark %d", Passport.GUID, markid)
	link = string.gsub(link, "[%s{}]", function (c)
			return string.format("%%%02X", string.byte(c))
		end)
	return "atape:" .. link
end

local table_gap_types = {
	[TYPES.VID_INDT_1] = 0, 	-- Стык(Видео)
	[TYPES.VID_INDT_2] = 0, 	-- Стык(Видео)
	[TYPES.VID_INDT_3] = 0, 	-- СтыкЗазор(Пользователь)
	[TYPES.VID_ISO]    = 1, 	-- ИзоСтык(Видео)
	[TYPES.VID_INDT_ATS] = 2, 	-- АТСтык(Видео)
	[TYPES.VID_INDT_ATS_USER] = 2, 	-- АТСтык(Пользователь)
}

--[[ получить тип стыка
(0 - болтовой, 1 - изолированный, 2 - сварной)]]
GetGapType = function (mark)
	-- 	https://bt.abisoft.spb.ru/view.php?id=743

	local nodeRoot = xml_cache:get(mark)
	if nodeRoot then
		local node = nodeRoot:SelectSingleNode('//PARAM[@name="ACTION_RESULTS" and @value="Common"]/PARAM[@name="JointType"]/@value')
		if node then
			return tonumber(node.nodeValue)
		end
	end

	return mark and mark.prop and table_gap_types[mark.prop.Guid]
end



-- =================== ЭКПОРТ ===================

return {
	xml_cache = xml_cache,

	errorf = errorf,
	printf = printf,
	sprintf = sprintf,
	sort_marks = sort_marks,
	sort_stable = sort_stable,
	filter_marks = filter_marks,
	SelectNodes = SelectNodes,
	filter_user_accept = filter_user_accept,
	table_find = algorithm.table_find,
	table_merge = algorithm.table_merge,
	sorted = algorithm.sorted,

	sort_mark_by_coord = sort_mark_by_coord,
	format_path_coord = format_path_coord,
	format_sys_coord = format_sys_coord,
	GetMarkRailPos = GetMarkRailPos,
	GetRailName = GetRailName,
	MakeCommonMarkTemplate = MakeCommonMarkTemplate,
	GetTemperature = GetTemperature,
	GetRecognitionStartInfo = GetRecognitionStartInfo,
	GetExtPassport = GetExtPassport,

	GetAllGapWidth = GetAllGapWidth,
	GetGapWidth = GetGapWidth,
	GetGapWidthName = GetGapWidthName,
	GetRailGapStep = GetRailGapStep,
	GetGapType = GetGapType,

	GetFishplateState = GetFishplateState,

	GetBeaconOffset = GetBeaconOffset,

	IsFastenerDefect = IsFastenerDefect,
	GetFastenetParams = GetFastenetParams,

	GetSurfDefectPrm = GetSurfDefectPrm,

	GetConnectorsCount = GetConnectorsCount,
	GetConnecterType = GetConnecterType,
	GetWeldedBondStatus = GetWeldedBondStatus,
	GetWeldedBondDefectCode = GetWeldedBondDefectCode,
	GetJoinConnectors = GetJoinConnectors,
	GetJoinConnectorDefectCodes = GetJoinConnectorDefectCodes,
	GetJoinConnectorDefected = GetJoinConnectorDefected,
	CONNECTOR_TYPE = CONNECTOR_TYPE,
	WELDEDBOND_TYPE = WELDEDBOND_TYPE,

	GetCrewJointArray = GetCrewJointArray,
	GetCrewJointCount = GetCrewJointCount,
	CalcValidCrewJointOnHalf = CalcValidCrewJointOnHalf,

	GetSleeperParam = GetSleeperParam,
	GetSleeperAngle = GetSleeperAngle,
	GetSleeperMeterial = GetSleeperMeterial,
	GetSleeperFault = GetSleeperFault,
	CheckSleeperEpure = CheckSleeperEpure,

	MakeMarkImage = MakeMarkImage,
	MakeMarkUri = MakeMarkUri,
}
