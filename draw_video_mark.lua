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
	
	for x,y in str:gmatch('(%d+),(%d+)') do
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



local function ProcessCalcRailGap(drawer, frame, dom)
	local cur_frame_coord = frame.coord.raw
	local colors = {
		CalcRailGap_Head_Top = {r=255, g=255, b=0},
		CalcRailGap_Head_Side = {r=0, g=255, b=255},
	}
	
	local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and starts-with(@value, "CalcRailGap")]\z
		/PARAM[@name="FrameNumber" and @value="0" and @coord]\z
		/PARAM[@name="Result" and @value="main"]'
	for node in SelectNodes(dom, req) do
		local gap_type =  node:SelectSingleNode("../../@value").nodeValue
		local color = colors[gap_type]
		if color then
			local item_frame = node:SelectSingleNode("../@coord").nodeValue
			local polygon = node:SelectSingleNode('PARAM[@name="Coord" and @type="polygon" and @value]/@value').nodeValue
			local width = node:SelectSingleNode('PARAM[@name="RailGapWidth_mkm" and @value]/@value').nodeValue
		
			local points = parse_polygon(polygon, cur_frame_coord, item_frame)
			--print(polygon, cur_frame_coord, item_frame)
			--print(points[1], points[2], points[3], points[4], points[5], points[6], points[7], points[8])
			
			if #points == 8 then
				drawer.prop:lineWidth(1)
				drawer.prop:fillColor(color.r, color.g, color.b, 50)
				drawer.prop:lineColor(color.r, color.g, color.b, 200)
				drawer.fig:polygon(points)
				
				--drawer.fig:rectangle(points[1], points[2], points[5], points[6])
				local strWidth = sprintf('%.1f mm', tonumber(width) / 1000)
				
				drawer.text:font { name="Tahoma", render="VectorFontCache", height=13, bold=0}
				drawer.text:alignment("AlignLeft", "AlignBottom")
				
				local tcx, tcy = get_center_point(points)
				local tw, th = drawer.text:calcSize(strWidth)
				tcx = tcx - tw/2
				tcy = tcy - th/2
				
				drawer.prop:lineWidth(3)
				drawer.prop:fillColor{r=0, g=0, b=0, a=255}
				drawer.prop:lineColor{r=0, g=0, b=0, a=255}
				drawer.text:out{x=tcx, y=tcy, str=strWidth}
				
				drawer.prop:lineWidth(1)
				drawer.prop:fillColor{r=255, g=255, b=255, a=220}
				drawer.prop:lineColor{r=255, g=255, b=255, a=220}
				drawer.text:out{x=tcx, y=tcy, str=strWidth}
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
		[-1] = {r=255, g=0,   b=0},
		[ 0] = {r=255, g=255, b=0},
		[ 1] = {r=128, g=128, b=255}, }
	
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
		
		local color = colors[safe]
		if color then
			local cx, cy, rx, ry = elipse:match('(%d+),(%d+),(%d+),(%d+)')
			--cx, cy = Convertor:ScalePoint(cx, cy)
			cx, cy = Convertor:GetPointOnFrame(cur_frame_coord, item_frame, cx, cy)
			if cx and cy then
				rx, ry = Convertor:ScalePoint(rx, ry)
				
				drawer.prop:lineWidth(1)
				drawer.prop:fillColor( color.r, color.g, color.b,  50 )
				drawer.prop:lineColor( color.r, color.g, color.b, 200 )
				drawer.fig:ellipse(cx, cy, rx, ry)
			end
		end
		--ShowToolTip(drawer, 200, 100, "%d %d %d %d", x, y, rx, ry)
	end
end

local function DrawBeacon(drawer, frame, dom)
	local colors = {
		Beacon_Web 		= {r=67, g=149,   b=209},
		Beacon_Fastener = {r=0,   g=169, b=157}, }
	
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
				drawer.prop:fillColor(color.r, color.g, color.b,  50)
				drawer.prop:lineColor(color.r, color.g, color.b, 200)
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
		
			drawer.text:font { name="Tahoma", render="VectorFontCache", height=13, bold=0}
			drawer.text:alignment("AlignLeft", "AlignBottom")
			
			local tw, th = drawer.text:calcSize(text)
			tcx = tcx - tw/2
			--tcy = tcy - th/2
			
			drawer.prop:lineWidth(3)
			drawer.prop:fillColor{r=0, g=0, b=0, a=255}
			drawer.prop:lineColor{r=0, g=0, b=0, a=255}
			drawer.text:out{x=tcx, y=tcy, str=text}
			
			drawer.prop:lineWidth(1)
			drawer.prop:fillColor{r=255, g=255, b=255, a=220}
			drawer.prop:lineColor{r=255, g=255, b=255, a=220}
			drawer.text:out{x=tcx, y=tcy, str=text}
		
		end
	end
end

local function DrawRecognitionMark(drawer, frame, mark)
	local prop, ext = mark.prop, mark.ext
	local raw_xml = ext.RAWXMLDATA
	if raw_xml then 
		--raw_xml = '<ACTION_RESULTS version="1.4"><PARAM name="ACTION_RESULTS" value="CalcRailGap_Head_Top"><PARAM name="FrameNumber" value="0" coord="284142"><PARAM name="Result" value="main"><PARAM name="Coord" type="polygon" value="550,784 550,670 587,670 587,784"/><PARAM name="RailGapWidth_mkm" value="37000"/></PARAM></PARAM></PARAM><PARAM name="ACTION_RESULTS" value="CalcRailGap_Head_Side"><PARAM name="FrameNumber" value="0" coord="284142"><PARAM name="Result" value="main"><PARAM name="Coord" type="polygon" value="550,670 550,592 587,592 587,670"/><PARAM name="RailGapWidth_mkm" value="37000"/></PARAM></PARAM></PARAM><PARAM name="ACTION_RESULTS" value="Fishplate"><PARAM name="FrameNumber" value="0" coord="284142"><PARAM name="Result" value="main"><PARAM name="FishplateEdge" value="1"><PARAM name="Coord" type="polygon" value="68,559 68,292"/></PARAM></PARAM></PARAM><PARAM name="FrameNumber" value="1" coord="285166"><PARAM name="Result" value="main"><PARAM name="FishplateEdge" value="2"><PARAM name="Coord" type="polygon" value="44,559 44,292"/></PARAM></PARAM></PARAM></PARAM><PARAM name="ACTION_RESULTS" value="CrewJoint"><PARAM name="FrameNumber" value="0" coord="284142"><PARAM name="Result" value="main"><PARAM name="JointNumber" value="0"><PARAM name="Coord" type="ellipse" value="114,433,22,22"/><PARAM name="CrewJointSafe" value="-1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="1"><PARAM name="Coord" type="ellipse" value="246,422,26,43"/><PARAM name="CrewJointSafe" value="1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="2"><PARAM name="Coord" type="ellipse" value="468,416,26,43"/><PARAM name="CrewJointSafe" value="1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="3"><PARAM name="Coord" type="ellipse" value="675,415,26,43"/><PARAM name="CrewJointSafe" value="1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="4"><PARAM name="Coord" type="ellipse" value="894,413,26,43"/><PARAM name="CrewJointSafe" value="1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="5"><PARAM name="Coord" type="ellipse" value="1016,424,22,22"/><PARAM name="CrewJointSafe" value="-1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM></PARAM></PARAM></PARAM><PARAM name="ACTION_RESULTS" value="Common"><PARAM name="Reliability" value="80"/><PARAM name="RecogObjCoord" value="284710" _desc="координата найденного объекта"/></PARAM></ACTION_RESULTS>'
	
		xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
		assert(xmlDom)
		xmlDom:loadXML(raw_xml)

		ProcessCalcRailGap(drawer, frame, xmlDom)
		DrawFishplate(drawer, frame, xmlDom)
		DrawCrewJoint(drawer, frame, xmlDom)
		DrawBeacon(drawer, frame, xmlDom)
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


local recorn_guids = 
{
	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = DrawRecognitionMark, --VID_INDT
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = DrawRecognitionMark, --VID_INDT
	["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = DrawRecognitionMark, --VID_INDT
	
	["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"] = DrawRecognitionMark,	
	["{0860481C-8363-42DD-BBDE-8A2366EFAC90}"] = DrawUnspecifiedObject,	
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
