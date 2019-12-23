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
			
		table.insert(points, x)
		table.insert(points, y)
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
	Drawer.prop:fillColor( color.r, color.g, color.b,  50 )
	Drawer.prop:lineColor( color.r, color.g, color.b, 255 )
	cx, cy, rx, ry = table.unpack(ellipse)
	Drawer.fig:ellipse(cx, cy, rx, ry)
end

local function drawRectangle(points, color, inflateSize)
	local ix = inflateSize and (inflateSize.x or inflateSize[1]) or 0
	local iy = inflateSize and (inflateSize.y or inflateSize[2]) or 0
	
	Drawer.prop:lineWidth(1)
	Drawer.prop:fillColor( color.r, color.g, color.b,  50 )
	Drawer.prop:lineColor( color.r, color.g, color.b, 255 )
	x1,y1, x2,y2 = table.unpack(points)
	Drawer.fig:rectangle(x1-ix,y1-iy, x2+ix,y2+iy)
end

function drawPolygon(points, lineWidth, line_color, fill_color)	
	if not points or #points == 0 or #points % 2 ~= 0 then
		--assert(0)
		return
	end
	
	if not fill_color then fill_color = line_color end
	
	Drawer.prop:lineWidth(lineWidth)
	Drawer.prop:fillColor(fill_color.r, fill_color.g, fill_color.b, fill_color.a or 20)
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
	drawer = Drawer
	params = params or {}
	local fill_color = params.fill_color or {r=255, g=255, b=255}
	local line_color = params.line_color or {r=0, g=0, b=0}
	local ox = params.offset and (params.offset.x or params.offset[1]) or 0
	local oy = params.offset and (params.offset.y or params.offset[2]) or 0
	
	drawer.text:font { name=params.font or "Tahoma", render="VectorFontCache", height=params.height or 13, bold=0}
	drawer.text:alignment("AlignLeft", "AlignBottom")
	
	local tw, th = drawer.text:calcSize(text)
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
	OutlineTextOut(tcx, tcy, text, params)
end


local function showError(text)
	print(text)
	OutlineTextOut(100, Frame.size.current.y - 10, text, {line_color={r=255, g=0, b=0}})
end

-- ============================ XML =========================

local function getMarkRawXml(mark)
	if not xmlDom then
		showError("Ошибка загрузки MSXML")
		return
	end
	
	local raw_xml = mark.ext.RAWXMLDATA
	if not raw_xml or #raw_xml  == 0 then
		showError(string.format('mark id = %d not contain RAWXMLDATA', mark.prop.ID))
		return
	end
	
	if not xmlDom:loadXML(raw_xml) then
		local msg = string.format('Error parse XML: %d %s\nmark id = %d\n%s', 
			xmlDom.parseError.errorCode, 
			xmlDom.parseError.reason,
			mark.prop.ID,
			raw_xml)
		showError(msg)
		error(msg)
		return
	end
	
	return xmlDom.documentElement
end

local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end

local function getParameters(nodeResult)
	assert(nodeResult)
	local res = {}
	for nodeParam in SelectNodes(nodeResult, 'PARAM[@name and @value and not (@type)]') do
		local attrib = nodeParam.attributes
		local name = attrib:getNamedItem('name').nodeValue
		local value = attrib:getNamedItem('value').nodeValue
		res[name] = value
	end
	return res
end

local function getDrawFig(nodeParamResult)
	assert(nodeParamResult)
	local res = {}
	
	local cur_frame_coord = Frame.coord.raw
	local nodeFrameCoord = nodeParamResult:SelectSingleNode("../@coord") or nodeParamResult:SelectSingleNode("../../@coord")
	if nodeFrameCoord then
		local item_frame = nodeFrameCoord.nodeValue
		
		local req = 'PARAM[@name="Coord" and @value and (@type="polygon" or @type="line" or @type="rect")]'
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

local function drawSimpleResult(resultType, points, params)
	
	if string.match(resultType, 'CalcRailGap_') then
		local colorsGap = {
			["CalcRailGap_Head_Top"] =  {r=255, g=255, b=0  },
			["CalcRailGap_Head_Side"] = {r=0,   g=255, b=255},
			["CalcRailGap_User"] =      {r=255, g=0,   b=255},
		}
		
		local color = colorsGap[resultType]
		if color then
			drawPolygon(points, 1, color, color)
			if params.RailGapWidth_mkm then
				textOut(points, sprintf('%d mm', tonumber(params.RailGapWidth_mkm) / 1000))
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
		}
		
		local color = colors[resultType]
		
		if color and #points > 0 and params.Shift_mkm then
			local shift = tonumber(params.Shift_mkm) / 1000
			drawRectangle(points, color, {5, 0})

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
	
	if resultType == 'Fastener' then
		local fastener_type_names = {
			[0] = 'КБ-65', 
			[1] = 'Аpc',  
			[2] = 'ДО', -- скрепление на деревянной шпале на костылях 
			[3] = 'КД', -- скрепление на деревянной шпале как КБ-65 но на двух шурупах 
		}
			
		local fastener_fault_names = {
			[0] = 'норм.',
			[1] = 'От.КБ',  -- отсутствие клемного болта kb65
			[2] = 'От.КЛМ',	-- отсуствие клеммы apc
			[10] = 'От.ЗБ',  -- отсутствие закладного болта kb65
			[11] = 'От.КЗБ',  -- отсутствие клемного и закладного болта kb65	
		}
		local color = {r=127, g=0, b=127}

		if #points == 8 then
			drawPolygon(points, 1, color, color)
			
			local strText = sprintf('тип..:  %s\nсост.:  %s\n', 
				params.FastenerType and (fastener_type_names[tonumber(params.FastenerType)] or params.FastenerType) or '', 
				params.FastenerFault and (fastener_fault_names[tonumber(params.FastenerFault)] or params.FastenerFault) or '')
			
			textOut(points, strText, {height=11})
		end
	end
	
	if resultType == 'Sleeper' then
		local color = {r=128, g=0, b=0}
		
		if #points == 8 then
			local l1 = {points[1], points[2], points[3], points[4]}
			local l2 = {points[5], points[6], points[7], points[8]}
			drawPolygon(l1, 1, color, color)
			drawPolygon(l2, 1, color, color)
			
			local text = sprintf('разв.=%4.1f', (params.Angle_mrad or 0) *180/3.14/1000 ) 				
			textOut(l2, text, {fill_color= {r=0, g=0, b=0}, line_color={r=255, g=255, b=255}, offset={35, 15}})
		end
	end
	
	if resultType == 'Surface' then
		local color = {r=192, g=0, b=192}
		if #points == 8 then
			drawPolygon(points, 1, color, color)
			
			local strText = sprintf('п.д.[a=%d,l=%d]', params.SurfaceWidth or 0 , params.SurfaceLength or 0) 
			textOut(points, strText, {offset={0, 20}})
		end
	end

	if resultType == "Surface_SQUAT_UIC_227" then
		local color = {r=255, g=0, b=255}
		if #points > 0 then
			drawPolygon(points, 1, color, color)
		end
	end
	
	if resultType == "Surface_SLEEPAGE_SKID_UIC_2251" then
		local color = {r=255, g=128, b=64}
		if #points > 0 then
			drawPolygon(points, 1, color, color)
		end
	end

	if resultType == "Surface_SLEEPAGE_SKID_UIC_2252" then
		local color = {r=255, g=255, b=128}
		if #points > 0 then
			drawPolygon(points, 1, color, color)
		end
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
	
	drawPolygon(points, 1, color_fishplate, color_fishplate)
	
	for _, fault in ipairs(faults) do
		drawPolygon(fault.points, 1, color_fault, color_fault)
	
		local text = fishpalte_fault_str[fault.code] or fault.code
		local tcx, tcy = get_center_point(fault.points)
		textOut(fault.points, text, {fill_color=color_fault, line_color={r=128, g=128, b=0}})
	end
end

-- ======================================================

local function processSimpleResult(nodeActRes, resultType)
	-- and @value="0"
	local req = '\z
		PARAM[@name="FrameNumber" and @coord]/\z
		PARAM[@name="Result" and @value="main"]'
		
	for nodeResult in SelectNodes(nodeActRes, req) do
		local params = getParameters(nodeResult)
		local points = getDrawFig(nodeResult)
		if #points > 0 then
			drawSimpleResult(resultType, points, params)
		end
	end
end

local function processCrewJoint(nodeActRes, resultType)
	local req = '\z
			PARAM[@name="FrameNumber" and @coord]/\z
			PARAM[@name="Result" and @value="main"]/\z
			PARAM[@name="JointNumber" and @value]'
	for nodeResult in SelectNodes(nodeActRes, req) do
		local params = getParameters(nodeResult)
		local points = getDrawFig(nodeResult)
		drawSimpleResult(resultType, points, params)
	end
end

local function processFishplate(nodeActionResFishplate)
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
		PARAM[@name="FrameNumber" and @value and @coord]/\z
		PARAM[@name="Result" and @value="main"]/\z
		PARAM[@name="FishplateState"]'
	for nodeParamFpltState in SelectNodes(nodeActionResFishplate, reqFault) do
		local points = getDrawFig(nodeParamFpltState)
		local nodeFaultCode = nodeParamFpltState:SelectSingleNode('PARAM[@name="FishplateFault" and @value]/@value')
		if #points > 0 and nodeFaultCode then
			faults[#faults+1] = {points = points, code=tonumber(nodeFaultCode.nodeValue)}
		end
	end
	
	assert(#pointsFishplate == 8)
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
	["Fastener"]	 	 			= {processSimpleResult},
	["Sleeper"]	 	 				= {processSimpleResult},
	["Surface"]	 	 				= {processSimpleResult},
	["Surface_SQUAT_UIC_227"] 		= {processSimpleResult},
	["Surface_SLEEPAGE_SKID_UIC_2251"] = {processSimpleResult},
	["Surface_SLEEPAGE_SKID_UIC_2252"] = {processSimpleResult},
	["Common"]	 	 				= {},
}

local function ProcessMarkRawXml(mark)
	local rawXmlRoot = getMarkRawXml(mark)
	if not rawXmlRoot then return end
	
	local req = sprintf('/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value and @channel="%d"]', 
		Frame.channel)
			
	for nodeActionResult in SelectNodes(rawXmlRoot, req) do
		local resultType = nodeActionResult.attributes:getNamedItem('value').nodeValue
		-- print(resultType)
		local fns = ActionResTypes[resultType]
		if fns then
			for _, fn in ipairs(fns) do
				fn(nodeActionResult, resultType)
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
	
	if ext.VIDEOFRAMECOORD and ext.VIDEOIDENTCHANNEL and ext.UNSPCOBJPOINTS and ext.VIDEOFRAMECOORD == cur_frame_coord then
		local points = parse_polygon(ext.UNSPCOBJPOINTS)
		
		if #points == 8 then
			drawPolygon(points, 1, color, color)
			
			--drawer.fig:rectangle(points[1], points[2], points[5], points[6])
			local text = prop.Description
			local tcx, tcy = get_center_point(points)
			OutlineTextOut(tcx, tcy, strText, {height=10})	
		end
	end
end

-- ==================== MARK TYPES ====================

local recorn_guids = 
{
	["{0860481C-8363-42DD-BBDE-8A2366EFAC90}"] = {ProcessUnspecifiedObject}, -- Ненормативный объект
	
	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = {ProcessMarkRawXml}, -- Стык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = {ProcessMarkRawXml}, -- Стык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = {ProcessMarkRawXml}, -- СтыкЗазор(Пользователь)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC804}"] = {ProcessMarkRawXml}, -- АТСтык(Видео)
	["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"] = {ProcessMarkRawXml}, -- Маячная
	["{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}"] = {ProcessMarkRawXml}, -- Маячная(Пользователь)
	["{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}"] = {ProcessMarkRawXml}, -- Скрепление	
	["{28C82406-2773-48CB-8E7D-61089EEB86ED}"] = {ProcessMarkRawXml}, -- Болты(Пользователь)
	["{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}"] = {ProcessMarkRawXml}, -- Поверх.(Видео)
	["{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}"] = {ProcessMarkRawXml}, -- Шпалы
	["{DE548D8F-4E0C-4644-8DB3-B28AE8B17431}"] = {ProcessMarkRawXml}, -- UIC_227
	["{BB144C42-8D1A-4FE1-9E84-E37E0A47B074}"] = {ProcessMarkRawXml}, -- BELGROSPI
	["{EBAB47A8-0CDC-4102-B21F-B4A90F9D873A}"] = {ProcessMarkRawXml}, -- UIC_2251
	["{54188BA4-E88A-4B6E-956F-29E8035684E9}"] = {ProcessMarkRawXml}, -- UIC_2252
	["{7EF92845-226D-4D07-AC50-F23DD8D53A19}"] = {ProcessMarkRawXml}, -- HC
	["{41486CAC-EBE9-46FF-ACCA-041AFAFFC531}"] = {ProcessMarkRawXml}, -- UIC_2251 (user)
	["{3401C5E7-7E98-4B4F-A364-701C959AFE99}"] = {ProcessMarkRawXml}, -- UIC_2252 (user)
	["{13A7906C-BBFB-4EB3-86FA-FA74B77F5F35}"] = {ProcessMarkRawXml}, -- UIC_227 (user)
}

-- ================= EXPORT FUNCTION ================ 

function Draw(drawer, frame, marks)
	-- совместимость
	if drawer then _G.Drawer = drawer end
	if frame then _G.Frame = frame end
		
	for _, mark in ipairs(marks) do
		local fns = recorn_guids[mark.prop.Guid] or {}
		for _, fn in ipairs(fns) do
			fn(mark)
		end
	end
end

-- запрос какие отметки следует загружать для отображения
function GetMarkGuids()
	local res = {}
	for g, f in pairs(recorn_guids) do
		table.insert(res, g)
	end
	return res
end

