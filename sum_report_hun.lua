require "luacom"

local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local excel_helper = require 'excel_helper'

-- ======================================

local video_hun_juids = 
{
	"{DE548D8F-4E0C-4644-8DB3-B28AE8B17431}",
	"{BB144C42-8D1A-4FE1-9E84-E37E0A47B074}",
	"{EBAB47A8-0CDC-4102-B21F-B4A90F9D873A}",
	"{54188BA4-E88A-4B6E-956F-29E8035684E9}",
	"{7EF92845-226D-4D07-AC50-F23DD8D53A19}",
}

local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
if not xmlDom then
	error("no Msxml2.DOMDocument: " .. luacom.config.last_error)
end


-- сделать строку ссылку для открытия атейпа на данной отметке
local function make_mark_uri(markid)
	local link = stuff.sprintf(" -g %s -mark %d", Passport.GUID, markid)
	link = string.gsub(link, "[%s{}]", function (c)
			return string.format("%%%02X", string.byte(c))
		end)
	return "atape:" .. link
end

local function getReability(mark)
	local xmlStr = mark and mark.ext.RAWXMLDATA
	if xmlStr and xmlDom:loadXML(xmlStr) then
		local nodeReliability = xmlDom:selectSingleNode('/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Common"]/PARAM[@name="Reliability"]/@value')
		if nodeReliability then
			return tonumber(nodeReliability.nodeValue)
		end
	end
end

local function separate_mark_by_reability(all_marks)
	local manual_marks, auto_marks = {}, {}
	
	for _, mark in ipairs(all_marks) do
		local reliability = getReability(mark)
		if reliability then
			if reliability > 100 then
				table.insert(manual_marks, mark)
			else
				table.insert(auto_marks, mark)
			end
		end
	end
	return manual_marks, auto_marks
end

local ManualMarks = OOP.class
{
	-- инициализация
	ctor = function(self, marks)
		self.marks = mark_helper.sort_mark_by_coord(marks)
		self.coords = {}
		for _, mark in ipairs(self.marks) do
			local c = mark.prop.SysCoord
			table.insert(self.coords, c)
		end
	end,
	
	-- найти ближайшую отметку
	find_near = function(self, mark)
		local c = mark.prop.SysCoord
		local index_min
		local dist_min
		for i, cc in ipairs(self.coords) do
			local dist = math.abs(cc - c)
			if not dist_min or dist < dist_min then
				dist_min = dist
				index_min = i
			end
		end
		
		if index_min then
			return self.marks[index_min], dist_min
		end
	end,
}

-- построить изображение для данной отметки
local function make_mark_image(mark, video_channel, show_range, base64)
	local img_path
	
	if ShowVideo ~= 0 then
		local prop = mark.prop
		
		if not video_channel then
			local recog_video_channels = mark_helper.GetSelectedBits(prop.ChannelMask)
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

local function getVideoChannel(mark)
	local xmlStr = mark and mark.ext.RAWXMLDATA
	local channels = {}
	if xmlStr and xmlDom:loadXML(xmlStr) then
		local nodeChannels = xmlDom:selectNodes('/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS"]/@channel')
		while true do
			local nodeChannal = nodeChannels:nextNode()
			if not nodeChannal then break end
			channels[tonumber(nodeChannal.nodeValue)] = 1
		end
	end
	
	local res = {}
	for c, _ in pairs(channels) do res[#res+1] = c end
	return res
end

local function insert_frame(excel, cell, mark, video_channel)
	local img_path
	local ok, msg = pcall(function ()
			img_path = make_mark_image(mark, video_channel)
		end)
	if not ok then
		cell.Value2 = msg and #msg and msg or 'Error'
	elseif img_path and #img_path then
		excel:InsertImage(cell, img_path)
	end
end


-- =========================================================== --

local function report_Simple()
	local all_marks = Driver:GetMarks{GUIDS=video_hun_juids}
	local manual_marks, auto_marks = separate_mark_by_reability(all_marks)
	
	manual_marks = ManualMarks(manual_marks)
	auto_marks = mark_helper.sort_mark_by_coord(auto_marks)
	
	local dlg = luaiup_helper.ProgressDlg()
	local excel = excel_helper(Driver:GetAppPath() .. "Scripts/hun_template.xlsx", nil, false)
	local worksheet = excel._worksheet
	
	local row_height = worksheet.Rows(1).RowHeight
	for line, mark in ipairs(auto_marks) do
		worksheet.Rows(line).RowHeight = row_height
		local prop =  mark.prop
		local uri = make_mark_uri(prop.ID)
		local user_mark, dist_user_mark = manual_marks:find_near(mark)

		excel:InsertLink(worksheet.Cells(line, 1), uri, prop.ID)
		worksheet.Cells(line, 2).Value2 = mark_helper.format_path_coord(mark)
		worksheet.Cells(line, 3).Value2 = prop.SysCoord
		worksheet.Cells(line, 4).Value2 = Driver:GetSumTypeName(prop.Guid)
		if dist_user_mark and dist_user_mark < 1000 then
			worksheet.Cells(line, 5).Value2 = string.format('найдена ручная на расстоянии %d mm', dist_user_mark) 
		else
			worksheet.Cells(line, 5).Value2 = "ручная отметка не найдена"
		end
		
		local channels = getVideoChannel(mark)
		-- worksheet.Cells(line, 6).Value2 = table.concat(channels, ',')
		for cn, channel in ipairs(channels) do
			insert_frame(excel, worksheet.Cells(line, 6+cn), mark, channel)
		end
		
--		if line > 100 then
--			break
--		end
		
		if not dlg:step(1.0 * line / #auto_marks, stuff.sprintf('Process %d / %d mark', line, #auto_marks)) then 
			break 
		end
	end
	excel:SaveAndShow()
end



-- =========================================================== --

local function AppendReports(reports)
	local name_pref = 'Венгерские дефекты|'
	
	local local_reports = 
	{
		{name = name_pref..'ВСЕ',    			fn = report_Simple, 	},
	}

	for _, report in ipairs(local_reports) do
		if report.fn then
			report.guids = video_hun_juids,
			table.insert(reports, report)
		end
	end
end

-- тестирование
if not ATAPE then
	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	report_Simple()
end


return {
	AppendReports = AppendReports,
	videogram = videogram,
}