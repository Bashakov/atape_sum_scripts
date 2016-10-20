require "luacom"

local sprintf = function(s,...)	return s:format(...) 			end


local function ShowToolTip(drawer, x, y, fmt, ...)
	fmt = fmt:format(...)
	drawer.text:font { name="Tahoma", render="RasterFontCache", height=12, bold=0}
	
	local tw, th = drawer.text:calcSize(fmt)
	
	local padding = 3
	drawer.prop:lineWidth(1)
	drawer.prop:fillColor{r=200, g=255, b=200, a=130}
	drawer.prop:lineColor{r=0, g=150, b=0, a=250}
	drawer.fig:roundedRect(x - padding, y - padding + 1, x + tw + padding, y + th + padding, padding*2)
	
	--drawer.prop:lineWidth(1)
	--drawer.prop:lineColor{r=255, g=255, b=255, a=200}
	drawer.prop:fillColor{r=0, g=0, b=0, a=220}
	drawer.text:alignment("AlignLeft", "AlignBottom")
	drawer.text:multiline {x=x, y=y, str=fmt}
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

local function parse_polygon(str, scale)
	local res = {}
	for w in str:gmatch('%d+') do 
		res[#res+1] = tonumber(w) / scale[(#res % #scale) + 1]
	end
	return res
end

local function get_center_point(points)
	local res = {0, 0}
	for i, p in ipairs(points) do
		local k = (i+1) % 2 + 1
		res[k] = res[k] + p
	end
	res[1] = res[1] / (#points / 2)
	res[2] = res[2] / (#points / 2)
	return res
end


local function DrawSingleRailGap(drawer, frame, node, gap_type, scale)
	local colors = {
		CalcRailGap_Head_Top = {r=255, g=255, b=0},
		CalcRailGap_Head_Side = {r=0, g=255, b=255},
	}
	local color = colors[gap_type]	
	
	local node_result = node:SelectSingleNode('PARAM[@name="Result" and @value="main"]')
	if node_result and color then 
		local polygon = node_result:SelectSingleNode('PARAM[@name="Coord" and @type="polygon" and @value]/@value').nodeValue
		local width = node_result:SelectSingleNode('PARAM[@name="RailGapWidth_mkm" and @value]/@value').nodeValue
		local points = parse_polygon(polygon, scale)
		
		drawer.prop:lineWidth(2)
		drawer.prop:fillColor(color.r, color.g, color.b, 100)
		drawer.prop:lineColor(color.r, color.g, color.b, 200)
		drawer.fig:polygon(points)
		--drawer.fig:rectangle(points[1], points[2], points[5], points[6])
		local strWidth = sprintf('%.1f mm', tonumber(width) / 1000)
		
		drawer.text:font { name="Tahoma", render="VectorFontCache", height=13, bold=0}
		drawer.text:alignment("AlignLeft", "AlignBottom")
		
		local tcx, tcy = table.unpack(get_center_point(points))		
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
		
		--ShowToolTip(drawer, 200, color.r, sprintf("%d %d %s", tw, th, strWidth))
	end
end

local function ProcessCalcRailGap(drawer, frame, dom, kx, ky)
	local nodes = dom:SelectNodes('/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and starts-with(@value, "CalcRailGap")]/PARAM[@name="FrameNumber" and @value="0" and @coord]')
	while true do
		local node = nodes:nextNode()
		if not node then break end
		
		local coord = tonumber(xml_attr(node, "coord"))
		if coord == frame.coord.raw then
			local recogn_type = xml_attr(node.parentNode, 'value')
			DrawSingleRailGap(drawer, frame, node, recogn_type, kx, ky) 
		end
	end
end


local function ParseFishplate(drawer, frame, dom, scale)
	local cur_frame_coord = frame.coord.raw
	local edges = {}
	
	local nodes = dom:SelectNodes('/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Fishplate"]/PARAM[@name="FrameNumber" and @value and @coord]')
	while true do
		local node = nodes:nextNode()
		if not node then break end
		
		local fram_num, frame_coord = xml_attr(node, {"value", "coord"})
		local node_polygon = node:SelectSingleNode('PARAM[@name="Result" and @value="main"]/PARAM[@name="FishplateEdge" and @value]/PARAM[@name="Coord" and @type="polygon" and @value]')
		if not node_polygon then break end
		
		local edge_num = tonumber(xml_attr(node_polygon.parentNode, 'value'))
		local polygon = xml_attr(node_polygon, 'value')
		edges[edge_num] = {points=parse_polygon(polygon, scale), coord=tonumber(frame_coord)}
		--ShowToolTip(drawer, 200, 100, tostring(edges[edge_num]))
	end
	
	local e1, e2 = edges[1], edges[2]
	if e1 and e2 and e1.coord <= cur_frame_coord and e2.coord >= cur_frame_coord then
		local res = {lines={}}
		
		if e1.coord < cur_frame_coord then
			--ShowToolTip(drawer, 200, 200, "1")
			e1.points[1] = 0
			e1.points[3] = 0
		else
			table.insert(res.lines, {e1.points[1], e1.points[2], e1.points[3], e1.points[4]})
		end
		
		if e2.coord > cur_frame_coord then
			-- ShowToolTip(drawer, 200, 210, "2")
			e2.points[1] = frame.size.current.x
			e2.points[3] = frame.size.current.x
			res.b2 = false
		else
			table.insert(res.lines, {e2.points[1], e2.points[2], e2.points[3], e2.points[4]})
		end
	
		res.rect = {
			e1.points[1], e1.points[2], e2.points[1], e2.points[2],
			e2.points[3], e2.points[4], e1.points[3], e1.points[4],}
		return res
	end
end


local function DrawFishplate(drawer, frame, dom, scale)
	local res = ParseFishplate(drawer, frame, dom, scale)
	if res then
		local color = {r=0, g=255, b=0},
		drawer.prop:lineWidth(0)
		drawer.prop:fillColor(color.r, color.g, color.b,  30)
		drawer.prop:lineColor(color.r, color.g, color.b, 160)
		drawer.fig:polygon(res.rect)
		
		drawer.prop:lineWidth(2)
		for _, l in ipairs(res.lines) do
			drawer.fig:line(l[1], l[2], l[3], l[4])
		end
	end
	--ShowToolTip(drawer, 200, 200, sprintf("%d %d  %d %d", edges_rect[1], edges_rect[2], edges_rect[3], edges_rect[4]))
end

local function DrawCrewJoint(drawer, frame, dom, scale)
	local colors = {
		[-1] = {r=255, g=0,   b=0},
		[ 0] = {r=255, g=255, b=0},
		[ 1] = {r=0,   g=255, b=0}, }
	
	local cur_frame_coord = frame.coord.raw

	local req_tmpl = '/ACTION_RESULTS\
/PARAM[@name="ACTION_RESULTS" and @value="CrewJoint"]\
/PARAM[@name="FrameNumber" and @value and @coord="%d"]\
/PARAM[@name="Result" and @value="main"]\
/PARAM[@name="JointNumber" and @value]'
	local nodes = dom:SelectNodes(req_tmpl:format(cur_frame_coord))
	while true do
		local node = nodes:nextNode()
		if not node then break end
		
		local num = xml_attr(node, "value")
		local elipse = node:SelectSingleNode('PARAM[@name="Coord" and @type="ellipse" and @value]/@value').nodeValue
		local safe = tonumber(node:SelectSingleNode('PARAM[@name="CrewJointSafe" and @value]/@value').nodeValue)
		
		local color = colors[safe]
		if color then
			local cx, cy, rx, ry = elipse:match('(%d+),(%d+),(%d+),(%d+)')
			cx = tonumber(cx) / scale[1]
			rx = tonumber(rx) / scale[1]
			
			cy = tonumber(cy) / scale[2]
			ry = tonumber(ry) / scale[2]
			
			drawer.prop:lineWidth(2)
			drawer.prop:fillColor(color.r, color.g, color.b,  80)
			drawer.prop:lineColor(color.r, color.g, color.b, 180)
			drawer.fig:ellipse(cx, cy, rx, ry)
		end
		--ShowToolTip(drawer, 200, 100, "%d %d %d %d", x, y, rx, ry)
	end
end


local function DrawRecognitionMark(drawer, frame, mark)
	local width, height = drawer:size()
	local scale = {frame.size.origin.x / frame.size.current.x, frame.size.origin.y / frame.size.current.y}
	
	local prop, ext = mark.prop, mark.ext
	local raw_xml = ext.RAWXMLDATA
	if raw_xml then 
		--raw_xml = '<ACTION_RESULTS version="1.4"><PARAM name="ACTION_RESULTS" value="CalcRailGap_Head_Top"><PARAM name="FrameNumber" value="0" coord="284142"><PARAM name="Result" value="main"><PARAM name="Coord" type="polygon" value="550,784 550,670 587,670 587,784"/><PARAM name="RailGapWidth_mkm" value="37000"/></PARAM></PARAM></PARAM><PARAM name="ACTION_RESULTS" value="CalcRailGap_Head_Side"><PARAM name="FrameNumber" value="0" coord="284142"><PARAM name="Result" value="main"><PARAM name="Coord" type="polygon" value="550,670 550,592 587,592 587,670"/><PARAM name="RailGapWidth_mkm" value="37000"/></PARAM></PARAM></PARAM><PARAM name="ACTION_RESULTS" value="Fishplate"><PARAM name="FrameNumber" value="0" coord="284142"><PARAM name="Result" value="main"><PARAM name="FishplateEdge" value="1"><PARAM name="Coord" type="polygon" value="68,559 68,292"/></PARAM></PARAM></PARAM><PARAM name="FrameNumber" value="1" coord="285166"><PARAM name="Result" value="main"><PARAM name="FishplateEdge" value="2"><PARAM name="Coord" type="polygon" value="44,559 44,292"/></PARAM></PARAM></PARAM></PARAM><PARAM name="ACTION_RESULTS" value="CrewJoint"><PARAM name="FrameNumber" value="0" coord="284142"><PARAM name="Result" value="main"><PARAM name="JointNumber" value="0"><PARAM name="Coord" type="ellipse" value="114,433,22,22"/><PARAM name="CrewJointSafe" value="-1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="1"><PARAM name="Coord" type="ellipse" value="246,422,26,43"/><PARAM name="CrewJointSafe" value="1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="2"><PARAM name="Coord" type="ellipse" value="468,416,26,43"/><PARAM name="CrewJointSafe" value="1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="3"><PARAM name="Coord" type="ellipse" value="675,415,26,43"/><PARAM name="CrewJointSafe" value="1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="4"><PARAM name="Coord" type="ellipse" value="894,413,26,43"/><PARAM name="CrewJointSafe" value="1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM><PARAM name="JointNumber" value="5"><PARAM name="Coord" type="ellipse" value="1016,424,22,22"/><PARAM name="CrewJointSafe" value="-1" _value="-1(нет), 0(болтается), 1(есть)"/></PARAM></PARAM></PARAM></PARAM><PARAM name="ACTION_RESULTS" value="Common"><PARAM name="Reliability" value="80"/><PARAM name="RecogObjCoord" value="284710" _desc="координата найденного объекта"/></PARAM></ACTION_RESULTS>'
	
		xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
		assert(xmlDom)
		xmlDom:loadXML(raw_xml)

		ProcessCalcRailGap(drawer, frame, xmlDom, scale)
		DrawFishplate(drawer, frame, xmlDom, scale)
		DrawCrewJoint(drawer, frame, xmlDom, scale)
	end
end


local recorn_guids = 
{
	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = DrawRecognitionMark, --VID_INDT
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = DrawRecognitionMark, --VID_INDT
	["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = DrawRecognitionMark, --VID_INDT
}


-- ================= EXPORT FUNCTION ================ 

function Draw(drawer, frame, marks)
	local width, height = drawer:size()
--	ShowToolTip(drawer, 10, height - 20, 'frame: %d %d', frame.coord.raw, frame.coord.visible)
--	ShowToolTip(drawer, 10, height - 40, 'orgn: %d %d', frame.size.origin.x, frame.size.origin.y)
--	ShowToolTip(drawer, 10, height - 60, 'curr: %d %d', frame.size.current.x, frame.size.current.y)
	
	
	for i = 1, #marks do
		local mark = marks[i]
		print("fdsa", mark.prop, mark.prop.Guid)
		local fn = recorn_guids[mark.prop.Guid]
		if fn then
			fn(drawer, frame, mark)
		end
	end
end
