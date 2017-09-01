-- require "luacom"

local sprintf = function(s,...)	return s:format(...) 			end

local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end



local function ShowToolTip(drawer, x, y, fmt, ...)
	local message = fmt:format(...)
	drawer.text:font { name="Tahoma", render="RasterFontCache", height=12, bold=0}
	
	local tw, th = drawer.text:calcSize(message)
	
	local padding = 3
	drawer.prop:lineWidth(1)
	drawer.prop:fillColor{r=200, g=255, b=200, a=130}
	drawer.prop:lineColor{r=0, g=150, b=0, a=250}
	drawer.fig:roundedRect(
		x - padding, 
		y - padding + 1, 
		x + tw + padding, 
		y + th + padding, 
		padding*2)
	
	--drawer.prop:lineWidth(1)
	--drawer.prop:lineColor{r=255, g=255, b=255, a=200}
	drawer.prop:fillColor{r=0, g=0, b=0, a=220}
	drawer.text:alignment("AlignLeft", "AlignBottom")
	drawer.text:multiline {x=x, y=y, str=message}
end

local function OutlineTextOut(drawer, x, y, text, params)
	params = params or {}
	drawer.text:font { name=params.font or "Tahoma", render="VectorFontCache", height=params.height or 13, bold=0}
	drawer.text:alignment("AlignLeft", "AlignBottom")
	
	local tw, th = drawer.text:calcSize(text)
	x = x - tw/2
	y = y - th/2
	
	drawer.prop:lineWidth(3)
	drawer.prop:fillColor{r=0, g=0, b=0, a=255}
	drawer.prop:lineColor{r=0, g=0, b=0, a=255}
	drawer.text:out{x=x, y=y, str=text}
	
	drawer.prop:lineWidth(1)
	drawer.prop:fillColor{r=255, g=255, b=255, a=220}
	drawer.prop:lineColor{r=255, g=255, b=255, a=220}
	drawer.text:out{x=x, y=y, str=text}
end


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

local function raw_parse_polygon(str)
	local points = {}
	for x,y in str:gmatch('(-?%d+),(-?%d+)') do
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



local function ProcessCalcRailGap(drawer, frame, dom)
	local cur_frame_coord = frame.coord.raw
	local colors = {
		CalcRailGap_Head_Top =  {r=255, g=255, b=0  },
		CalcRailGap_Head_Side = {r=0,   g=255, b=255},
		CalcRailGap_User =      {r=255, g=0,   b=255},
	}
	
	local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and starts-with(@value, "CalcRailGap")]\z
		/PARAM[@name="FrameNumber" and @value="0" and @coord]\z
		/PARAM[@name="Result" and @value="main"]'
	for node in SelectNodes(dom, req) do
		local gap_type =  node:SelectSingleNode("../../@value").nodeValue
		local color = colors[gap_type]
		
		local fig_channel = node:SelectSingleNode("../../@channel")
		fig_channel = fig_channel and tonumber(fig_channel.nodeValue)
		
		if color and (not fig_channel or not frame.channel or fig_channel == frame.channel) then
			local item_frame = node:SelectSingleNode("../@coord").nodeValue
			local polygon = node:SelectSingleNode('PARAM[@name="Coord" and @type="polygon" and @value]/@value').nodeValue
			local width = node:SelectSingleNode('PARAM[@name="RailGapWidth_mkm" and @value]/@value').nodeValue
		
			local points = parse_polygon(polygon, cur_frame_coord, item_frame)
			--print(polygon, cur_frame_coord, item_frame)
			--print(points[1], points[2], points[3], points[4], points[5], points[6], points[7], points[8])
			
			if #points == 8 then
				drawer.prop:lineWidth(1)
				drawer.prop:fillColor(color.r, color.g, color.b, 20)
				drawer.prop:lineColor(color.r, color.g, color.b, 200)
				drawer.fig:polygon(points)
				
				--drawer.fig:rectangle(points[1], points[2], points[5], points[6])
				local strWidth = sprintf('%.1f mm', tonumber(width) / 1000)
				
				local tcx, tcy = get_center_point(points)
				OutlineTextOut(drawer, tcx, tcy, strWidth)
			end
		end
	end
end

local function ProcessRailGapStep(drawer, frame, dom)
	local cur_frame_coord = frame.coord.raw
		
	local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="CalcRailGapStep"]\z
		/PARAM[@name="FrameNumber" and @value="0" and @coord]\z
		/PARAM[@name="Result" and @value="main"]'
	for node in SelectNodes(dom, req) do

		local fig_channel = node:SelectSingleNode("../../@channel")
		fig_channel = fig_channel and tonumber(fig_channel.nodeValue)
		
		if not fig_channel or not frame.channel or fig_channel == frame.channel then
			local item_frame = node:SelectSingleNode("../@coord").nodeValue
			local line = node:SelectSingleNode('PARAM[@name="Coord" and @type="line" and @value]/@value').nodeValue
			local width = node:SelectSingleNode('PARAM[@name="RailGapStepWidth" and @value]/@value').nodeValue
		
			local points = parse_polygon(line, cur_frame_coord, item_frame)
			
			if #points == 4 then
				drawer.prop:lineWidth(2)
				drawer.prop:fillColor(255, 0, 0, 20)
				drawer.prop:lineColor(255, 0, 0, 200)
				drawer.fig:line(points[1], points[2], points[3], points[4])
				
				local strWidth = sprintf('%.1f mm', tonumber(width))
				
				local tcx, tcy = get_center_point(points)
				OutlineTextOut(drawer, tcx, tcy + 10, strWidth)
			end
		end
	end
end


local function DrawFishplate(drawer, frame, dom)
	local points = {}
	local cur_frame_coord = frame.coord.raw
	local req = '\z
			/ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and @value="Fishplate"]\z
			/PARAM[@name="FrameNumber" and @value and @coord]\z
			/PARAM[@name="Result" and @value="main"]\z
			/PARAM[@name="FishplateEdge" and @value]\z
			/PARAM[@name="Coord" and @type="polygon" and @value]'
	for node in SelectNodes(dom, req) do
		local item_frame = node:SelectSingleNode("../../../@coord").nodeValue
		local polygon = node:SelectSingleNode('@value').nodeValue
		
		local fig_channel = node:SelectSingleNode("../../../../@channel")
		fig_channel = fig_channel and tonumber(fig_channel.nodeValue)
		if not fig_channel or not frame.channel or fig_channel == frame.channel then
			local x1,y1, x2,y2 = string.match(polygon, '(%d+),(%d+)%s+(%d+),(%d+)')
			x1, y1 = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, x1, y1)
			x2, y2 = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, x2, y2)
			
			if x1 and y1 and x2 and y2 then
				if #points ~= 0 then
					x1, y1, x2, y2 = x2, y2, x1, y1
				end
				table.insert(points, x1)
				table.insert(points, y1)
				table.insert(points, x2)
				table.insert(points, y2)
			end
		end
	end
	
	if #points == 8 then
		local color = {r=0, g=255, b=0},
		drawer.prop:lineWidth(1)
		drawer.prop:fillColor(color.r, color.g, color.b,  20)
		drawer.prop:lineColor(color.r, color.g, color.b, 200)
		drawer.fig:polygon(points)
	end
	
	--ShowToolTip(drawer, 200, 200, sprintf("%d %d  %d %d", edges_rect[1], edges_rect[2], edges_rect[3], edges_rect[4]))
end

local function DrawCrewJoint(drawer, frame, dom)
	local colors = {
		[-1] = {r=255, g=0,   b=0},  	-- отсутствует
		[ 0] = {r=255, g=255, b=0},  	-- болтается
		[ 1] = {r=128, g=128, b=255},  	-- есть 
		[ 2] = {r=128, g=192, b=255},   -- болт
		[ 3] = {r=128, g=64, b=255},    -- гайка	
	}	
		
	local cur_frame_coord = frame.coord.raw

	local req = '\z
			/ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and @value="CrewJoint"]\z
			/PARAM[@name="FrameNumber" and @value and @coord]\z
			/PARAM[@name="Result" and @value="main"]\z
			/PARAM[@name="JointNumber" and @value]'
	for node in SelectNodes(dom, req) do
		local num = xml_attr(node, "value")
		local item_frame = node:SelectSingleNode("../../@coord").nodeValue
		local elipse = node:SelectSingleNode('PARAM[@name="Coord" and @type="ellipse" and @value]/@value').nodeValue
		local safe = tonumber(node:SelectSingleNode('PARAM[@name="CrewJointSafe" and @value]/@value').nodeValue)
		
		local fig_channel = node:SelectSingleNode("../../../@channel")
		fig_channel = fig_channel and tonumber(fig_channel.nodeValue)
		
		local color = colors[safe] or {r=128, g=128, b=128}
		
		if color and (not fig_channel or not frame.channel or fig_channel == frame.channel) then
			local cx, cy, rx, ry = elipse:match('(%d+),(%d+),(%d+),(%d+)')
			--cx, cy = Convertor:ScalePoint(cx, cy)
			cx, cy = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, cx, cy)
			if cx and cy then
				rx, ry = Convertor:ScalePoint(rx, ry)
				
				drawer.prop:lineWidth(1)
				drawer.prop:fillColor( color.r, color.g, color.b,  50 )
				drawer.prop:lineColor( color.r, color.g, color.b, 255 )
				drawer.fig:ellipse(cx, cy, rx, ry)
			end
		end
		--ShowToolTip(drawer, 200, 100, "%d %d %d %d", x, y, rx, ry)
	end
end

local function DrawBeacon(drawer, frame, dom)
	local colors = {
		Beacon_Web 		= {r=67, g=149, b=209},
		Beacon_Fastener = {r=0,  g=169, b=157}, }
	
	local cur_frame_coord = frame.coord.raw
	
	local shifts = {}
	local req = '\z
			/ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and starts-with(@value, "Beacon_")]\z
			/PARAM[@name="FrameNumber" and @value and @coord]\z
			/PARAM[@name="Result" and @value="main"]'
	
	for node in SelectNodes(dom, req) do
		local pos = node:SelectSingleNode("../../@value").nodeValue
		local item_frame = node:SelectSingleNode("../@coord").nodeValue
		local rect = node:SelectSingleNode('PARAM[@name="Coord" and @type="rect" and @value]/@value').nodeValue
		local shift = tonumber(node:SelectSingleNode('PARAM[@name="Shift_mkm" and @value]/@value').nodeValue) / 1000
		
		local color = colors[pos]
		if color then
			local x1,y1, x2,y2 = string.match(rect, '(-?%d+),(-?%d+),(-?%d+),(-?%d+)')
			x1, y1 = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, x1, y1)
			x2, y2 = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, x2, y2)
			--x2, y2 = Convertor:ScalePoint(x2, y2)
			if x1 and y1 and x2 and y2 then
				
				--ShowToolTip(drawer, x1, y1, "%s\n%s\n%s\n%s", pos, rect, offset, item_frame)
				
				drawer.prop:lineWidth(1)
				drawer.prop:fillColor(color.r, color.g, color.b,  90)
				drawer.prop:lineColor(color.r, color.g, color.b, 250)
				drawer.fig:rectangle(x1-5, y1, x2+5, y2)
				--ShowToolTip(drawer, 200, 100, "%d %d %d %d", x1, y1, x2, y2)
				shifts[pos] = {coords = {x1, y1, x2, y2}, shift=shift}
			end
		end
		
		if shifts.Beacon_Web and shifts.Beacon_Fastener then
			local c1 = shifts.Beacon_Web.coords
			local c2 = shifts.Beacon_Fastener.coords
			local tcx = (c1[1] + c1[3] + c2[1] + c2[3]) / 4
			local tcy = (c1[4] + c2[2]) / 2
			
			local text = sprintf('%.1f mm', shifts.Beacon_Web.shift)
			OutlineTextOut(drawer, tcx, tcy, text)
		end
	end
end

local function DrawRecognitionMark(drawer, frame, mark)
	local prop, ext = mark.prop, mark.ext
	local raw_xml = ext.RAWXMLDATA
	if raw_xml then 
		local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
		assert(xmlDom)
		xmlDom:loadXML(raw_xml)

		ProcessCalcRailGap(drawer, frame, xmlDom)
		DrawFishplate(drawer, frame, xmlDom)
		DrawCrewJoint(drawer, frame, xmlDom)
		DrawBeacon(drawer, frame, xmlDom)
		ProcessRailGapStep(drawer, frame, xmlDom)
	end
end


local function DrawUnspecifiedObject(drawer, frame, mark)
	local color = {r=67, g=149, b=209}
		
	local cur_frame_coord = frame.coord.raw
	local prop, ext = mark.prop, mark.ext
	
	if ext.VIDEOFRAMECOORD and ext.VIDEOIDENTCHANNEL and ext.UNSPCOBJPOINTS and ext.VIDEOFRAMECOORD == cur_frame_coord then
		local points = parse_polygon(ext.UNSPCOBJPOINTS)
		--print(polygon, cur_frame_coord, item_frame)
		--print(points[1], points[2], points[3], points[4], points[5], points[6], points[7], points[8])
		
		if #points == 8 then
			drawer.prop:lineWidth(1)
			drawer.prop:fillColor(color.r, color.g, color.b, 50)
			drawer.prop:lineColor(color.r, color.g, color.b, 200)
			drawer.fig:polygon(points)
			
			--drawer.fig:rectangle(points[1], points[2], points[5], points[6])
			local text = prop.Description
			
			drawer.text:font { name="Tahoma", render="VectorFontCache", height=10, bold=0}
			drawer.text:alignment("AlignLeft", "AlignBottom")
			
			local tcx, tcy = get_center_point(points)
			local tw, th = drawer.text:calcSize(text)
			tcx = tcx - tw/2
			tcy = tcy - th/2
			
			drawer.prop:lineWidth(3)
			drawer.prop:fillColor{r=0, g=0, b=0, a=255}
			drawer.prop:lineColor{r=0, g=0, b=0, a=255}
			drawer.text:multiline{x=tcx, y=tcy, str=text}
			
			drawer.prop:lineWidth(1)
			drawer.prop:fillColor{r=255, g=255, b=255, a=220}
			drawer.prop:lineColor{r=255, g=255, b=255, a=220}
			drawer.text:multiline{x=tcx, y=tcy, str=text}
		end
	end
end

local fastener_type_names = {
	[0] = 'КБ-65',
	[1] = 'Аpc',
	[2] = 'КД',
}
	
local fastener_fault_names = {
	[0] = 'норм.',
	[1] = 'От.ЗБ', 
	[2] = 'От.Кл',
}

local function DrawFastener(drawer, frame, mark)
	local prop, ext = mark.prop, mark.ext
	local cur_frame_coord = frame.coord.raw
	local item_frame = ext.VIDEOFRAMECOORD
	local raw_xml = ext.RAWXMLDATA
	
	local color = {r=127, g=0, b=127}
	
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom)
	xmlDom:loadXML(raw_xml)
	-- print(raw_xml)
	
	local points = {}
	local req = '\z
			/ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and @value="Fastener"]\z
			/PARAM[@name="FrameNumber" and @value and @coord]\z
			/PARAM[@name="Result" and @value="main"]\z
			/PARAM[@name="Coord" and @type="polygon" and @value]'
	for node in SelectNodes(xmlDom, req) do
		local nodeFastenerType = node:SelectSingleNode('../PARAM[@name="FastenerType" and @value]/@value')
		local nodeFastenerFault = node:SelectSingleNode('../PARAM[@name="FastenerFault" and @value]/@value')
		nodeFastenerType = nodeFastenerType and nodeFastenerType.nodeValue
		nodeFastenerFault = nodeFastenerFault and nodeFastenerFault.nodeValue
		
		local fig_channel = node:SelectSingleNode("../../../@channel")
		fig_channel = fig_channel and tonumber(fig_channel.nodeValue)
		
		local polygon = node:SelectSingleNode('@value').nodeValue
	
		local points = parse_polygon(polygon, cur_frame_coord, item_frame)
		local raw_points = raw_parse_polygon(polygon)
		-- print(raw_points, raw_points[1], raw_points[5])
		--print(polygon, cur_frame_coord, item_frame)
		--print(points[1], points[2], points[3], points[4], points[5], points[6], points[7], points[8])
			
		if #points == 8 and (not fig_channel or not frame.channel or fig_channel == frame.channel) then
			drawer.prop:lineWidth(1)
			drawer.prop:fillColor(color.r, color.g, color.b, 20)
			drawer.prop:lineColor(color.r, color.g, color.b, 255)
			drawer.fig:polygon(points)
			
			--drawer.fig:rectangle(points[1], points[2], points[5], points[6])
			local strText = sprintf('тип..:  %s\nсост.:  %s\n', 
				nodeFastenerType and (fastener_type_names[tonumber(nodeFastenerType)] or nodeFastenerType) or '', 
				nodeFastenerFault and (fastener_fault_names[tonumber(nodeFastenerFault)] or nodeFastenerFault) or '')
			-- тоже с ширирной
			--local strText = sprintf('Тип   : %s\nСост.: %s\nШир.: %d\n', 
			---	nodeFastenerType and (fastener_type_names[tonumber(nodeFastenerType)] or nodeFastenerType) or '', 
			--	nodeFastenerFault and (fastener_fault_names[tonumber(nodeFastenerFault)] or nodeFastenerFault) or '',
			--	raw_points[5]- raw_points[1])				

        -- local strText = sprintf('%s, %s', raw_points[1], raw_points[2] )


			
			drawer.text:font { name="Tahoma", render="VectorFontCache", height=11, bold=0}
			drawer.text:alignment("AlignLeft", "AlignBottom")
			
			local tcx, tcy = get_center_point(points)
			local tw, th = drawer.text:calcSize(strText)
			tcx = tcx - tw/2
			tcy = tcy - th/2
			
			drawer.prop:lineWidth(3)
			drawer.prop:fillColor{r=0, g=0, b=0, a=255}
			drawer.prop:lineColor{r=0, g=0, b=0, a=255}
			drawer.text:multiline{x=tcx, y=tcy, str=strText}
			
			drawer.prop:lineWidth(1)
			drawer.prop:fillColor{r=255, g=255, b=255, a=220}
			drawer.prop:lineColor{r=255, g=255, b=255, a=220}
			drawer.text:multiline{x=tcx, y=tcy, str=strText}
		end
	end
end


local recorn_guids = 
{
	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = DrawRecognitionMark, --VID_INDT
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = DrawRecognitionMark, --VID_INDT
	["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = DrawRecognitionMark, --USER
	["{CBD41D28-9308-4FEC-A330-35EAED9FC804}"] = DrawRecognitionMark, --ATS
	
	["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"] = DrawRecognitionMark,	
	
	["{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}"] = DrawRecognitionMark,	--M_SPALA
	
	["{0860481C-8363-42DD-BBDE-8A2366EFAC90}"] = DrawUnspecifiedObject,	
	["{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}"] = DrawFastener,	
	["{28C82406-2773-48CB-8E7D-61089EEB86ED}"] = DrawRecognitionMark,
}


-- ================= EXPORT FUNCTION ================ 

function Draw(drawer, frame, marks)
--	local width, height = drawer:size()
--	ShowToolTip(drawer, 10, height - 20, 'frame: %d %d', frame.coord.raw, #marks)
--	ShowToolTip(drawer, 10, height - 40, 'orgn: %d %d', frame.size.origin.x, frame.size.origin.y)
--	ShowToolTip(drawer, 10, height - 60, 'curr: %d %d', frame.size.current.x, frame.size.current.y)
	
	--print(Convertor:ScalePoint(1000, 1000))
	
	for i = 1, #marks do
		local mark = marks[i]
		--print("fdsa", mark.prop, mark.prop.Guid)
		local fn = recorn_guids[mark.prop.Guid]
		if fn then
			fn(drawer, frame, mark)
		end
	end
end
