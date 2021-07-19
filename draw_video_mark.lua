require "luacom"



local sprintf = function(s,...)	return s:format(...) end
local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")

-- ============================ MATH =========================

local function parse_polygon(str, cur_frame_coord, item_frame)
	local points = {}

	for x,y in str:gmatch('(-?%d+),(-?%d+)') do
		if cur_frame_coord and item_frame and item_frame ~= cur_frame_coord then
			x, y = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, x, y)
		else
			x, y = Convertor:ScalePoint(x, y)
		end

		table.insert(points, tonumber(x))
		table.insert(points, tonumber(y))
	end

	return points
end

local function get_center_point(points)
	local x, y = 0, 0
	local cnt = #points / 2
	for i = 1, #points, 2 do
		x = x + points[i]   / cnt
		y = y + points[i+1] / cnt
	end
	return x, y
end

-- ========================= DRAW PRIMITIVES ======================

local function drawEllipse(ellipse, color)
	Drawer.prop:lineWidth(1)
	Drawer.prop:fillColor( color.r, color.g, color.b,   0 )
	Drawer.prop:lineColor( color.r, color.g, color.b, 255 )
	local cx, cy, rx, ry = table.unpack(ellipse)
	Drawer.fig:ellipse(cx, cy, rx, ry)
end

local function drawRectangle(points, color, inflateSize)
	local ix = inflateSize and (inflateSize.x or inflateSize[1]) or 0
	local iy = inflateSize and (inflateSize.y or inflateSize[2]) or 0

	Drawer.prop:lineWidth(1)
	Drawer.prop:fillColor( color.r, color.g, color.b,   0 )
	Drawer.prop:lineColor( color.r, color.g, color.b, 255 )
	local x1,y1, x2,y2 = table.unpack(points)
	Drawer.fig:rectangle(x1-ix,y1-iy, x2+ix,y2+iy)
end

local function drawPolygon(points, lineWidth, line_color, fill_color)
	if not points or #points == 0 or #points % 2 ~= 0 then
		--assert(0)
		return
	end

	if not fill_color then fill_color = line_color end

	Drawer.prop:lineWidth(lineWidth)
	Drawer.prop:fillColor(fill_color.r, fill_color.g, fill_color.b, fill_color.a or   0)
	Drawer.prop:lineColor(line_color.r, line_color.g, line_color.b, line_color.a or 200)
	Drawer.fig:polygon(points)
end

local function drawMultiline(x, y, text, lineWidth, color)
	Drawer.prop:lineWidth(lineWidth)
	Drawer.prop:fillColor{r=color.r, g=color.g, b=color.b, a=color.a or 225}
	Drawer.prop:lineColor{r=color.r, g=color.g, b=color.b, a=color.a or 225}
	Drawer.text:multiline{x=x, y=y, str=text}
end

local function OutlineTextOut(x, y, text, params)
	local drawer = Drawer
	params = params or {}
	local fill_color = params.fill_color or {r=255, g=255, b=255}
	local line_color = params.line_color or {r=0, g=0, b=0}
	local ox = params.offset and (params.offset.x or params.offset[1]) or 0
	local oy = params.offset and (params.offset.y or params.offset[2]) or 0

	drawer.text:font { name=params.font or "Tahoma", render="VectorFontCache", height=params.height or 13, bold=0}
	drawer.text:alignment("AlignLeft", "AlignBottom")

	local tw, th = drawer.text:calcSize(text)
	tw = -5  -- https://bt.abisoft.spb.ru/view.php?id=642
	x = x - tw/2 + ox
	y = y - th/2 + oy

	drawMultiline(x, y, text, 3, line_color)
	drawMultiline(x, y, text, 1, fill_color)
end

local function textOut(center, text, params)
	local tcx, tcy = table.unpack(center)
	if #center > 2 then
		tcx, tcy = get_center_point(center)
	end
	if true then -- https://bt.abisoft.spb.ru/view.php?id=642
		tcx = center[1]
		for i = 3, #center, 2 do
			tcx = math.max(tcx, center[i])
		end
	end
	OutlineTextOut(tcx, tcy, text, params)
end


local function showError(text)
	print(text)
	OutlineTextOut(100, Frame.size.current.y - 10, text, {line_color={r=255, g=0, b=0}})
end

-- ============================ XML =========================

local function load_xml_str(str_xml)
	if not xmlDom then
		showError("Ошибка загрузки MSXML")
		return
	end

	if not xmlDom:loadXML(str_xml) then
		local msg = string.format('Error parse XML: %d %s\n%s',
			xmlDom.parseError.errorCode,
			xmlDom.parseError.reason,
			str_xml)
		showError(msg)
		error(msg)
		return
	end

	return xmlDom.documentElement
end

local function getMarkRawXml(mark)
	local raw_xml = mark.ext.RAWXMLDATA
	if not raw_xml or #raw_xml  == 0 then
		showError(string.format('mark id = %d not contain RAWXMLDATA', mark.prop.ID))
		return
	end
	return load_xml_str(raw_xml)
end

local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end

local function getParameters(nodeResult, parameters_common)
	assert(nodeResult)
	local res = {}

	if parameters_common then
		for key, value in pairs(parameters_common) do
			res[key] = value
		end
	end

	for nodeParam in SelectNodes(nodeResult, 'PARAM[@name and @value and not (@type)]') do
		local attrib = nodeParam.attributes
		local name = attrib:getNamedItem('name').nodeValue
		local value = attrib:getNamedItem('value').nodeValue
		local num = tonumber(value)
		res[name] = num or value
	end
	return res
end

local function getDrawFig(nodeParamResult)
	assert(nodeParamResult)
	local res = {}

	local cur_frame_coord = Frame.coord.raw
	local nodeFrameCoord = nodeParamResult:SelectSingleNode("../@coord") or nodeParamResult:SelectSingleNode("../../@coord")
	if nodeFrameCoord then
		local item_frame = tonumber(nodeFrameCoord.nodeValue)

		local req = 'descendant::PARAM[@name="Coord" and @value and (@type="polygon" or @type="line" or @type="rect")]'
		for nodeFig in SelectNodes(nodeParamResult, req) do
			local value = nodeFig:SelectSingleNode('@value').nodeValue
			local points = parse_polygon(value, cur_frame_coord, item_frame)
			if #points > 0 and #points % 2 == 0 then
				for _, p in ipairs(points) do
					table.insert(res, p)
				end
			end
		end

		local nodeEllipse = nodeParamResult:SelectSingleNode('PARAM[@name="Coord" and @type="ellipse" and @value]/@value')
		if nodeEllipse then
			local ellipse = nodeEllipse.nodeValue
			local cx, cy, rx, ry = ellipse:match('(%d+),(%d+),(%d+),(%d+)')
			--print(ellipse)
			if cx and cy and rx and ry then
				cx, cy = Convertor:GetPointOnFrame(Frame.coord.raw, item_frame, cx, cy)
				if cx and cy then
					rx, ry = Convertor:ScalePoint(rx, ry)
					--return {cx, cy, rx, ry}
					table.insert(res, cx)
					table.insert(res, cy)
					table.insert(res, rx)
					table.insert(res, ry)
				end
			end
		end
	end
	return res
end

-- ======================================================

local beacon_shifts = {}

local function drawSimpleResult(resultType, points, params, mark)

	if string.match(resultType, 'CalcRailGap_') then
		local colorsGap = {
			["CalcRailGap_Head_Top"] =  {r=255, g=255, b=0  },
			["CalcRailGap_Head_Side"] = {r=0,   g=255, b=255},
			["CalcRailGap_User"] =      {r=255, g=0,   b=255},
		}

		local color = colorsGap[resultType]
		if color then
			drawPolygon(points, 1, color, color)

			local width = nil
			if resultType == "CalcRailGap_Head_Top" then
				width = mark.ext.VIDEOIDENTGWT
				if not width and not mark.ext.VIDEOIDENTGWS and params.RailGapWidth_mkm then
					width = tonumber(params.RailGapWidth_mkm) / 1000
				end
			elseif resultType == "CalcRailGap_Head_Side" then
				width = mark.ext.VIDEOIDENTGWS 
				if not width and not mark.ext.VIDEOIDENTGWT and params.RailGapWidth_mkm then
					width = tonumber(params.RailGapWidth_mkm) / 1000
				end
			else
				width = mark.ext.VIDEOIDENTGWS or mark.ext.VIDEOIDENTGWT
			end

			if width then
				textOut(points, sprintf('%d mm', width))
			end
		end
	end

	if resultType == 'CalcRailGapStep' then
		if #points == 4 then
			local color = {r=0, g=0, b=255}
			drawPolygon(points, 2, color, color)

			local strWidth = sprintf('%d mm', tonumber(params.RailGapStepWidth)/1000)
			textOut(points, strWidth, {fill_color={r=0, g=0, b=192}, line_color={r=128, g=128, b=128}, offset={0, 10}})
		end
	end

	if resultType == 'WeldedBond' then
		local colors = {
			[0] = {r=0, g=192, b=128}, -- хороший соединитель
			[1] = {r=255, g=128, b=0},
		}
		local color = colors[tonumber(params.ConnectorFault)] or {r=128, g=128, b=128}
		drawPolygon(points, 1, color, color)
	end

	if resultType == 'Connector' then
		local colors = {
			[0] = {r=0, g=192, b=128}, -- хороший соединитель
			[1] = {r=255, g=128, b=0},
		}

		local color = colors[tonumber(params.ConnectorFault)] or {r=128, g=128, b=128}
		drawEllipse(points, color)
	end

	if resultType == 'CrewJoint' then
		local colors = {
			[-1] = {r=255, g=0,   b=0},  	-- отсутствует
			[ 0] = {r=255, g=255, b=0},  	-- болтается
			[ 1] = {r=128, g=128, b=255},  	-- есть
			[ 2] = {r=128, g=192, b=255},   -- болт
			[ 3] = {r=128, g=64, b=255},    -- гайка
		}

		local color = colors[tonumber(params.CrewJointSafe)] or {r=128, g=128, b=128}
		drawEllipse(points, color)
	end

	if string.match(resultType, 'Beacon_') then
		local colors = {
			Beacon_Web 		= {r=67, g=149, b=209},
			Beacon_Fastener = {r=0,  g=169, b=157},
			Beacon_FirTreeMark = {r=100,  g=169, b=157},
		}

		local color = colors[resultType]

		if color and #points > 0  then
			drawRectangle(points, color, {5, 0})
			if params.Shift_mkm then
				local shift = tonumber(params.Shift_mkm) / 1000

				-- beacon_shifts используется для рисования текста с шириной посредине отметки (среднее положение по рискам)
				if beacon_shifts.frame and beacon_shifts.frame ~= Frame.coord.raw then	 -- предполагаем что не больше одной маячной отметки на кадре
					beacon_shifts = {frame = Frame.coord.raw}
				end

				beacon_shifts[resultType] = {coords = points, shift = shift}
				if beacon_shifts.Beacon_Web and beacon_shifts.Beacon_Fastener then
					local c1 = beacon_shifts.Beacon_Web.coords
					local c2 = beacon_shifts.Beacon_Fastener.coords
					local tcx = (c1[1] + c1[3] + c2[1] + c2[3]) / 4
					local tcy = (c1[4] + c2[2]) / 2

					local text = sprintf('%.1f mm', beacon_shifts.Beacon_Web.shift)
					textOut({tcx, tcy}, text)
					beacon_shifts = {} -- сбросим нарисованное
				end
			end
		end
	end

	if resultType == 'Fastener' then
		local fastener_type_names = {
			[0] = 'КБ-65',
			[1] = 'Аpc',
			[2] = 'ДО', -- скрепление на деревянной шпале на костылях
			[3] = 'КД', -- скрепление на деревянной шпале как КБ-65 но на двух шурупах
		}

		local fastener_fault_names = {
			[0] = 'норм.',
			[1] = 'От.КБ',  -- отсутствие клеммного болта kb65
			[2] = 'От.КЛМ',	-- отсутствие клеммы apc
			[10] = 'От.ЗБ',  -- отсутствие закладного болта kb65
			[11] = 'От.КЗБ',  -- отсутствие клеммного и закладного болта kb65
		}
		local color = {r=0, g=255, b=0}
		local colorFault = {r=255, g=0, b=0}


		if #points == 8 then --[[and params.FastenerFault == 0]]
			
			if fastener_fault_names[tonumber(params.FastenerFault)] == 'норм.' then
				drawPolygon(points, 1, color, color)
				else
				drawPolygon(points, 2, colorFault, colorFault)
			end
			
			local strText = sprintf('тип..:  %s\nсост.:  %s\n',
				params.FastenerType and (fastener_type_names[tonumber(params.FastenerType)] or params.FastenerType) or '',
				params.FastenerFault and (fastener_fault_names[tonumber(params.FastenerFault)] or params.FastenerFault) or '')

			textOut(points, strText, {height=11})
		
		end
	end

	if resultType == 'Sleeper' then
		local maskChannel = mark.prop.ChannelMask
		local mask21 = bit32.lshift(1, 21)
		local mask22 = bit32.lshift(1, 22)
		if bit32.btest(maskChannel, mask21) or bit32.btest(maskChannel, mask22) then
			points = {} -- При рисовании дефектов шпал по 21 22 - не рисовать шпалу и её разворот - только дефект.  https://bt.abisoft.spb.ru/view.php?id=764#c3718
		end

		-- print("Sleeper", #points)
		local color = {r=128, g=0, b=0}

		if #points == 8 then
			local l1 = {points[1], points[2], points[3], points[4]}
			local l2 = {points[5], points[6], points[7], points[8]}
			drawPolygon(l1, 1, color, color)
			drawPolygon(l2, 1, color, color)

			local text = sprintf('разв.=%4.1f', (params.Angle_mrad or 0) *180/3.14/1000 )
			textOut(l2, text, {fill_color= {r=0, g=0, b=0}, line_color={r=255, g=255, b=255}, offset={35, 15}})
		end

		if #points == 12 then
			local l1 = {points[1], points[2], points[3], points[4]}
			local l2 = {points[5], points[6], points[7], points[8]}
			local l3 = {points[9], points[10], points[11], points[12]}
			drawPolygon(l1, 1, color, color)
			drawPolygon(l2, 1, color, color)
			drawPolygon(l3, 1, color, color)

			local text = sprintf('разв.=%4.1f', (params.Angle_mrad or 0) *180/3.14/1000 )
			textOut(l2, text, {fill_color= {r=0, g=0, b=0}, line_color={r=255, g=255, b=255}, offset={35, 15}})
		end
	end

	if resultType == 'SleeperFault' then
		-- https://bt.abisoft.spb.ru/view.php?id=706
		local fault2color =
		{
			[0] = {r=255, g=0,  b=40}, -- undef
			[1] = {r=255, g=20, b=0},  -- fracture(ferroconcrete)
			[2] = {r=255, g=40, b=0},  -- chip(ferroconcrete)
			[3] = {r=255, g=60, b=0},  -- crack(wood)
			[4] = {r=255, g=80, b=0},  -- rottenness(wood)
		}
		local fault2text =
		{
			[0] = "undef",
			[1] = "fracture(ferroconcrete)",
			[2] = "chip(ferroconcrete)",
			[3] = "crack(wood)",
			[4] = "rottenness(wood)",
		}

		local color = fault2color[params.FaultType] or {r=0, g=0, b=0}
		local text = fault2text[params.FaultType] or ""
		print("SleeperFault", text, table.concat(points, ', '))

		drawPolygon(points, 2, color, {r=0, g=0, b=0, a=0})
		textOut(points, text, {fill_color= {r=255, g=255, b=255}, line_color={r=255, g=0, b=0}, offset={0, 0}})
	end

	if resultType == 'Surface' then
		local color = {r=192, g=0, b=192}
		if #points == 8 then
			drawPolygon(points, 1, color, color)

			local strText = sprintf('п.д.[a=%d,l=%d]', params.SurfaceWidth or 0 , params.SurfaceLength or 0)
			textOut(points, strText, {offset={0, 20}})
		end
	end

	local hun_act_types_color = {
		["Surface_SQUAT_UIC_227"] 				= {r=0,   g=255, b=0    }, -- зеленый
		["Surface_SLEEPAGE_SKID_UIC_2251"] 		= {r=0,   g=255, b=255  }, -- циан
		["Surface_SLEEPAGE_SKID_UIC_2252"] 		= {r=255, g=255, b=0  },  -- желтый

		["Surface_SQUAT_UIC_227_USER"] 			= {r=255, g=0,   b=255  }, -- малиновый
		["Surface_SLEEPAGE_SKID_UIC_2251_USER"] = {r=255, g=128, b=0    }, -- оранжевый
		["Surface_SLEEPAGE_SKID_UIC_2252_USER"] = {r=255, g=0,   b=0   },  -- красный
	}
	local hun_color = hun_act_types_color[resultType]
	if #points > 0 and hun_color then
		drawPolygon(points, 1, hun_color, hun_color)
	end
end

local function drawFishplate(points, faults)
	local color_fishplate = {r=0, g=255, b=0}

	local color_fault = {r=128, g=0, b=0}
	local fishpalte_fault_str = {
		[0] = 'испр.',
		[1] = 'ндp.',
		[3] = 'тре.',
		[4] = 'изл.',
	}

	if #points ~= 0 then
		assert(#points == 8)
		drawPolygon(points, 1, color_fishplate, color_fishplate)
	end

	for _, fault in ipairs(faults) do
		drawPolygon(fault.points, 1, color_fault, color_fault)

		local text = fishpalte_fault_str[fault.code] or fault.code
		local tcx, tcy = get_center_point(fault.points)
		textOut(fault.points, text, {fill_color=color_fault, line_color={r=128, g=128, b=0}})
	end
end

-- ======================================================

local function processSimpleResult(nodeActRes, resultType, mark)
	-- and @value="0"
	local req = '\z
		PARAM[@name="FrameNumber" and @coord]/\z
		PARAM[@name="Result" and @value="main"]'

	for nodeResult in SelectNodes(nodeActRes, req) do
		local params_common = getParameters(nodeResult)

		--[[ пройдем по всем вложенным фигурам, так например в <PARAM name="Result" value="main"> может быть
			как сразу описание фигуры например для стыка:
				<PARAM name="Result" value="main">
					<PARAM name="Coord" type="polygon" value="349,422 349,373 370,373 370,422"/>
					<PARAM name="RailGapWidth_mkm" value="21000"/>
				</PARAM>
			так и вложенные объекты, например шпала и ее дефект:
				<PARAM name="Result" value="main">
					<PARAM name="Sleeper">
						<PARAM name="Coord" type="line" value="776,8,776,488"></PARAM> ...
					</PARAM>
					<PARAM name="SleeperFault">
						<PARAM name="Coord" type="polygon" value="924,222,1004,222,1004,129,924,129"></PARAM>
						...
					</PARAM>
					<PARAM name="Angle_mrad" value="999"></PARAM>
					...
				</PARAM>
			поэтому идем по PARAM у которых есть PARAM[@name="Coord"] а внутри уже извлекаем описание объекта
		]]
		for nodeFigure in SelectNodes(nodeResult, 'descendant-or-self::PARAM[PARAM/@name="Coord"]') do
			local fig_type = nodeFigure:selectSingleNode('@name')
			if fig_type and fig_type.nodeValue ~= "Result" then
				resultType = fig_type.nodeValue
			end

			local params = getParameters(nodeFigure, params_common)
			local points = getDrawFig(nodeFigure)
			print("processSimpleResult", resultType, #points)
			if #points > 0 then
				drawSimpleResult(resultType, points, params, mark)
			end
		end
	end
end

local function processCrewJoint(nodeActRes, resultType, mark)
	local req = '\z
			PARAM[@name="FrameNumber" and @coord]/\z
			PARAM[@name="Result" and @value="main"]/\z
			PARAM[@name="JointNumber" and @value]'
	for nodeResult in SelectNodes(nodeActRes, req) do
		local params = getParameters(nodeResult)
		local points = getDrawFig(nodeResult)
		drawSimpleResult(resultType, points, params, mark)
	end
end

local function processFishplate(nodeActionResFishplate, mark)
	local cur_frame_coord = Frame.coord.raw

	local pointsFishplate = {}
	local reqFishplate = '\z
		PARAM[@name="FrameNumber" and @coord]/\z
		PARAM[@name="Result" and @value="main"]/\z
		PARAM[@name="FishplateEdge"]/\z
		PARAM[@name="Coord" and @type="polygon" and @value]'

	for nodeParamPolygon in SelectNodes(nodeActionResFishplate, reqFishplate) do
		local item_frame = nodeParamPolygon:SelectSingleNode("../../../@coord").nodeValue
		local polygon = nodeParamPolygon:SelectSingleNode('@value').nodeValue
		local x1,y1, x2,y2 = string.match(polygon, '(%d+),(%d+)%s+(%d+),(%d+)')
		x1, y1 = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, x1, y1)
		x2, y2 = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, x2, y2)

		if x1 and y1 and x2 and y2 then
			if #pointsFishplate ~= 0 then
				x1, y1, x2, y2 = x2, y2, x1, y1
			end
			table.insert(pointsFishplate, x1)
			table.insert(pointsFishplate, y1)
			table.insert(pointsFishplate, x2)
			table.insert(pointsFishplate, y2)
		end
	end

	local faults = {}
	local reqFault = '\z
		PARAM[@name="FrameNumber" and @coord]/\z
		PARAM[@name="Result" and @value="main"]/\z
		PARAM[@name="FishplateState"]'
	for nodeParamFpltState in SelectNodes(nodeActionResFishplate, reqFault) do
		local points = getDrawFig(nodeParamFpltState)
		local nodeFaultCode = nodeParamFpltState:SelectSingleNode('PARAM[@name="FishplateFault" and @value]/@value')
		if #points > 0 and nodeFaultCode then
			faults[#faults+1] = {points = points, code=tonumber(nodeFaultCode.nodeValue)}
		end
	end

	drawFishplate(pointsFishplate, faults)
end



-- ======================================================

local ActionResTypes =
{
	["CalcRailGap_Head_Top"] 		= {processSimpleResult},
	["CalcRailGap_Head_Side"]	 	= {processSimpleResult},
	["CalcRailGap_User"]		 	= {processSimpleResult},
	["CalcRailGapStep"]		 		= {processSimpleResult},
	["WeldedBond"]	 	 			= {processSimpleResult},
	["Connector"]	 	 			= {processSimpleResult},
	["CrewJoint"]	 	 			= {processCrewJoint},
	["Fishplate"]	 	 			= {processFishplate},
	["Beacon_Web"]	 	 			= {processSimpleResult},
	["Beacon_Fastener"]	 	 		= {processSimpleResult},
	["Beacon_FirTreeMark"]	 	 	= {processSimpleResult},
	["Fastener"]	 	 			= {processSimpleResult},
	["Sleeper"]	 	 				= {processSimpleResult},
	["Surface"]	 	 				= {processSimpleResult},
	["Surface_SQUAT_UIC_227"] 		= {processSimpleResult},
	["Surface_SLEEPAGE_SKID_UIC_2251"] = {processSimpleResult},
	["Surface_SLEEPAGE_SKID_UIC_2252"] = {processSimpleResult},
	["Surface_SQUAT_UIC_227_USER"] 		= {processSimpleResult},
	["Surface_SLEEPAGE_SKID_UIC_2251_USER"] = {processSimpleResult},
	["Surface_SLEEPAGE_SKID_UIC_2252_USER"] = {processSimpleResult},
	["Common"]	 	 				= {},
}

local function ProcessMarkRawXml(mark)
	-- print("ProcessMarkRawXml", mark)
	local rawXmlRoot = getMarkRawXml(mark)
	if not rawXmlRoot then return end

	local req = sprintf('/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value and @channel="%d"]',
		Frame.channel)

	for nodeActionResult in SelectNodes(rawXmlRoot, req) do
		local resultType = nodeActionResult.attributes:getNamedItem('value').nodeValue
		local fns = ActionResTypes[resultType]
		if fns then
			for _, fn in ipairs(fns) do
				fn(nodeActionResult, resultType, mark)
			end
		else
			local msg = sprintf('Unknown: %s', resultType)
			showError(msg)
		end
	end
end

local function ProcessUnspecifiedObject(mark)
	local color = {r=67, g=149, b=209}

	local cur_frame_coord = Frame.coord.raw
	local prop, ext = mark.prop, mark.ext

	if ext.VIDEOFRAMECOORD and ext.VIDEOIDENTCHANNEL and ext.UNSPCOBJPOINTS and math.abs(ext.VIDEOFRAMECOORD - cur_frame_coord) < 1500 then
		local points = parse_polygon(ext.UNSPCOBJPOINTS, cur_frame_coord, ext.VIDEOFRAMECOORD)

		if #points == 8 then
			drawPolygon(points, 1, color, color)

			--drawer.fig:rectangle(points[1], points[2], points[5], points[6])
			local text = prop.Description
			local tcx, tcy = get_center_point(points)
			OutlineTextOut(tcx, tcy, text, {height=10})
		end
	end
end

local function ProcessGroupDefectObject(mark)
	local color_line = {r=167, g=49, b=29, a=200}
	local color_fill = {r=167, g=49, b=29, a=50}

	local cur_frame_coord = Frame.coord.raw
	local prop, ext = mark.prop, mark.ext
	local text = prop.Description
	local all_points = {}

	if ext.GROUP_OBJECT_DRAW and #ext.GROUP_OBJECT_DRAW > 0 then
		local node = load_xml_str(ext.GROUP_OBJECT_DRAW)
		local req = sprintf('/draw/object[@type="rect" and @channel="%d" and @points and @frame]', Frame.channel)

		for node_obj in SelectNodes(node, req) do
			local str_points = node_obj.attributes:getNamedItem('points').nodeValue
			local frame = tonumber(node_obj.attributes:getNamedItem('frame').nodeValue)

			local points = parse_polygon(str_points, cur_frame_coord, frame)
			for _, p in ipairs(points) do table.insert(all_points, p) end

			if #points == 8 then
				drawPolygon(points, 1, color_line, color_fill)
			end
		end
		print('#all_points', #all_points)
		if #all_points > 0 then
			local tcx, tcy = get_center_point(all_points)
			OutlineTextOut(tcx, tcy, text, {height=10})
		end
	end
end

-- ==================== MARK TYPES ====================

local recorn_guids =
{
	["{0860481C-8363-42DD-BBDE-8A2366EFAC90}"] = {ProcessUnspecifiedObject}, -- Ненормативный объект

	["{3601038C-A561-46BB-8B0F-F896C2130001}"] = {ProcessUnspecifiedObject}, -- Скрепления(Пользователь)
	["{3601038C-A561-46BB-8B0F-F896C2130002}"] = {ProcessUnspecifiedObject}, -- Шпалы(Пользователь)
	["{3601038C-A561-46BB-8B0F-F896C2130003}"] = {ProcessUnspecifiedObject}, -- Рельсовые стыки(Пользователь)
	["{3601038C-A561-46BB-8B0F-F896C2130004}"] = {ProcessUnspecifiedObject}, -- Дефекты рельсов(Пользователь)
	["{3601038C-A561-46BB-8B0F-F896C2130005}"] = {ProcessUnspecifiedObject}, -- Балласт(Пользователь)
	["{3601038C-A561-46BB-8B0F-F896C2130006}"] = {ProcessUnspecifiedObject}, -- Бесстыковой путь(Пользователь)

	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = {ProcessMarkRawXml}, -- Стык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = {ProcessMarkRawXml}, -- Стык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = {ProcessMarkRawXml}, -- СтыкЗазор(Пользователь)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC804}"] = {ProcessMarkRawXml}, -- АТСтык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC805}"] = {ProcessMarkRawXml}, -- АТСтык(Пользователь)
	["{64B5F99E-75C8-4386-B191-98AD2D1EEB1A}"] = {ProcessMarkRawXml}, -- ИзоСтык(Видео)
	["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"] = {ProcessMarkRawXml}, -- Маячная
	["{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}"] = {ProcessMarkRawXml}, -- Маячная(Пользователь)
	["{D3736670-0C32-46F8-9AAF-3816DE00B755}"] = {ProcessMarkRawXml}, -- Маячная Ёлка
	["{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}"] = {ProcessMarkRawXml}, -- Скрепление
	["{28C82406-2773-48CB-8E7D-61089EEB86ED}"] = {ProcessMarkRawXml}, -- Болты(Пользователь)
	["{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}"] = {ProcessMarkRawXml}, -- Поверх.(Видео)
	["{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}"] = {ProcessMarkRawXml}, -- Шпалы
	["{1DEFC4BD-FDBB-4AC7-9008-BEEB56048131}"] = {ProcessMarkRawXml}, -- Дефекты шпал
	["{53987511-8176-470D-BE43-A39C1B6D12A3}"] = {ProcessMarkRawXml}, -- SleeperTop
	["{DE548D8F-4E0C-4644-8DB3-B28AE8B17431}"] = {ProcessMarkRawXml}, -- UIC_227
	["{BB144C42-8D1A-4FE1-9E84-E37E0A47B074}"] = {ProcessMarkRawXml}, -- BELGROSPI
	["{EBAB47A8-0CDC-4102-B21F-B4A90F9D873A}"] = {ProcessMarkRawXml}, -- UIC_2251
	["{54188BA4-E88A-4B6E-956F-29E8035684E9}"] = {ProcessMarkRawXml}, -- UIC_2252
	["{7EF92845-226D-4D07-AC50-F23DD8D53A19}"] = {ProcessMarkRawXml}, -- HC
	["{41486CAC-EBE9-46FF-ACCA-041AFAFFC531}"] = {ProcessMarkRawXml}, -- UIC_2251 (user)
	["{3401C5E7-7E98-4B4F-A364-701C959AFE99}"] = {ProcessMarkRawXml}, -- UIC_2252 (user)
	["{13A7906C-BBFB-4EB3-86FA-FA74B77F5F35}"] = {ProcessMarkRawXml}, -- UIC_227 (user)

	["{B6BAB49E-4CEC-4401-A106-355BFB2E0001}"] = {ProcessGroupDefectObject}, -- GROUP_GAP_AUTO
	["{B6BAB49E-4CEC-4401-A106-355BFB2E0002}"] = {ProcessGroupDefectObject}, -- GROUP_GAP_USER
	["{B6BAB49E-4CEC-4401-A106-355BFB2E0011}"] = {ProcessGroupDefectObject}, -- GROUP_SPR_AUTO
	["{B6BAB49E-4CEC-4401-A106-355BFB2E0012}"] = {ProcessGroupDefectObject}, -- GROUP_SPR_USER
	["{B6BAB49E-4CEC-4401-A106-355BFB2E0021}"] = {ProcessGroupDefectObject}, -- GROUP_FSTR_AUTO
	["{B6BAB49E-4CEC-4401-A106-355BFB2E0022}"] = {ProcessGroupDefectObject}, -- GROUP_FSTR_USER
}

-- ================= EXPORT FUNCTION ================

function Draw(drawer, frame, marks)
	-- совместимость
	if drawer then _G.Drawer = drawer end
	if frame then _G.Frame = frame end

	-- print('Draw ', #marks)
	for _, mark in ipairs(marks) do
		print('Draw mark', mark.prop.Guid)
		local fns = recorn_guids[mark.prop.Guid] or {}
		for _, fn in ipairs(fns) do
			fn(mark)
		end
	end
end

-- запрос какие отметки следует загружать для отображения
function GetMarkGuids()
	local res = {}
	for g, _ in pairs(recorn_guids) do
		table.insert(res, g)
	end
	return res
end

