require "luacom"

local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local excel_helper = require 'excel_helper'
local luaiup_helper = require 'luaiup_helper'

-- ======================================

local video_hun_juids = 
{
	["{DE548D8F-4E0C-4644-8DB3-B28AE8B17431}"] = false,	-- UIC_227
	["{BB144C42-8D1A-4FE1-9E84-E37E0A47B074}"] = false,	-- BELGROSPI
	["{EBAB47A8-0CDC-4102-B21F-B4A90F9D873A}"] = false,	-- UIC_2251
	["{54188BA4-E88A-4B6E-956F-29E8035684E9}"] = false,	-- UIC_2252
	["{7EF92845-226D-4D07-AC50-F23DD8D53A19}"] = false,	-- HC

	["{13A7906C-BBFB-4EB3-86FA-FA74B77F5F35}"] = true,	-- UIC_227(User)
	["{981F7780-500C-47CD-978A-B9F3A91C37FE}"] = true,	-- BELGROSPI(User)
	["{41486CAC-EBE9-46FF-ACCA-041AFAFFC531}"] = true,	-- UIC_2251(User)
	["{3401C5E7-7E98-4B4F-A364-701C959AFE99}"] = true,	-- UIC_2252(User)
	["{515FA798-3893-41CA-B4C3-6E1FEAC8E12F}"] = true,	-- HC(User)
}

	local NAME_UIC_227   =	"UIC_227"
	local NAME_UIC_2251  =	"UIC_2251"
	local NAME_UIC_2252  =	"UIC_2252" 
	local NAME_BELGROSPI =	"BELGROSPI"	
	local NAME_UIC_227_USER   =	"UIC_227(User)"
	local NAME_UIC_2251_USER  =	"UIC_2251(User)"
	local NAME_UIC_2252_USER  =	"UIC_2252(User)" 
	local NAME_BELGROSPI_USER =	"BELGROSPI(User)"


local function keys(tbl)
	local res = {}
	for k, _ in pairs(tbl) do table.insert(res, k) end
	return res
end

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

--local function getReability(mark)
--	local xmlStr = mark and mark.ext.RAWXMLDATA
--	if xmlStr and xmlDom:loadXML(xmlStr) then
--		local nodeReliability = xmlDom:selectSingleNode('/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Common"]/PARAM[@name="Reliability"]/@value')
--		if nodeReliability then
--			return tonumber(nodeReliability.nodeValue)
--		end
--	end
--end

local function separate_mark_by_user_set(all_marks)
	local manual_marks, auto_marks = {}, {}
	
	for _, mark in ipairs(all_marks) do
		local user_mark = video_hun_juids[string.upper(mark.prop.Guid)]
		local dst = user_mark and manual_marks or auto_marks
		table.insert(dst, mark)
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

-- получить список номеров видео каналов по данных XML
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
	table.sort(res)
	return res
end

-- вставить изображение указанного видеоканала в указаную ячейку
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
local function get_ManualCount(SumTypeName)
	local all_marks = Driver:GetMarks{GUIDS=keys(video_hun_juids)}
	local manual_marks, auto_marks  = separate_mark_by_user_set(all_marks)
	manual_marks = mark_helper.sort_mark_by_coord(manual_marks)
	local manuals = 0
	for line, mark in ipairs(manual_marks) do
		local prop =  mark.prop
		if Driver:GetSumTypeName(prop.Guid) == SumTypeName then
			manuals = manuals + 1
		end 
	end 
	return manuals
end

local function get_AutoCount(SumTypeName)
	local all_marks = Driver:GetMarks{GUIDS=keys(video_hun_juids)}
	local manual_marks, auto_marks  = separate_mark_by_user_set(all_marks)
	auto_marks = mark_helper.sort_mark_by_coord(auto_marks)
	local auto = 0
	for line, mark in ipairs(auto_marks) do
		local prop =  mark.prop
		if Driver:GetSumTypeName(prop.Guid) == SumTypeName then
			auto = auto + 1
		end 
	end 
	return auto
end

local function isTheSameTypeExceptUserPosfix( UserMarkName,  MarkName)	
	if string.sub( UserMarkName, 1, string.len(UserMarkName) -  string.len("(User)") ) == MarkName then 
		return true
	end
	return false
end
-- ============================================================

local function report_Simple()
	local all_marks = Driver:GetMarks{GUIDS=keys(video_hun_juids)}
	local manual_marks, auto_marks = separate_mark_by_user_set(all_marks)
	
	manual_marks = ManualMarks(manual_marks)
	auto_marks = mark_helper.sort_mark_by_coord(auto_marks)
	
	local dlg = luaiup_helper.ProgressDlg()
	
	local dest_name = Passport.NAME .. '=' .. os.date('%y%m%d-%H%M%S')
	local excel = excel_helper(Driver:GetAppPath() .. "Scripts/hun_template.xlsx", nil, false, dest_name)
	
	local ext_psp = mark_helper.GetExtPassport(Passport)
	excel:ApplyPassportValues(ext_psp)
	
	local data_range = excel:CloneTemplateRow(#auto_marks)
	local found_manuals = 0
	local found_227  = 0   
	local found_2251 = 0   
	local found_2252 = 0   
	local found_bel  = 0
	
	-- найденные с точным совпадением типа
	local found_227_  = 0   
	local found_2251_ = 0   
	local found_2252_ = 0   
	local found_bel_  = 0
	
	
	local recog_227  = 0   
	local recog_2251 = 0   
	local recog_2252 = 0   
	local recog_bel  = 0	
	
	local last_mark_sys_coord = 0
	
	for line, mark in ipairs(auto_marks) do
		local prop =  mark.prop
		local user_mark, dist_user_mark = manual_marks:find_near(mark)
		
		last_mark_sys_coord = prop.SysCoord
		
		-- вставить ссылку нумерацию
		--excel:InsertLink(data_range.Cells(line, 1), make_mark_uri(prop.ID), prop.ID)
		data_range.Cells(line, 1).Value2 = line
		
		data_range.Cells(line, 2).Value2 = mark_helper.format_path_coord(mark)
		data_range.Cells(line, 3).Value2 = prop.SysCoord
		data_range.Cells(line, 4).Value2 = Driver:GetSumTypeName(prop.Guid)
		
		local cell_OK = data_range.Cells(line, 5)
		local cell = data_range.Cells(line, 6)
		if user_mark and dist_user_mark and dist_user_mark < 1000 then
			cell_OK.Value2 = "OK"		
			-- вставить ссылку на расстояние -- excel:InsertLink(cell, make_mark_uri(user_mark.prop.ID), text)
			cell.Value2 = string.format('%d mm', dist_user_mark) 
			
			local MarkName = Driver:GetSumTypeName(mark.prop.Guid)
			local UserMarkName = Driver:GetSumTypeName(user_mark.prop.Guid)			
			local isTheSame =   isTheSameTypeExceptUserPosfix( UserMarkName,  MarkName)	
			if isTheSame then
				cell_OK.interior.color = 0x80ff80	
			else
				cell_OK.interior.color = 0x80ff00
			end
			--0xf0fff0
			found_manuals =  found_manuals + 1			

			-- Распределяем по типам Ищем совпадения по типам
			if Driver:GetSumTypeName(mark.prop.Guid) == NAME_UIC_227 then
				found_227 = found_227 + 1
				if ( isTheSame ) then
					found_227_ = found_227_ + 1
				end
			end
			if Driver:GetSumTypeName(mark.prop.Guid) == NAME_UIC_2251 then
				found_2251 = found_2251 + 1
				if ( isTheSame ) then
					found_2251_ = found_2251_ + 1
				end
			end
			if Driver:GetSumTypeName(mark.prop.Guid) == NAME_UIC_2252 then
				found_2252 = found_2252 + 1
				if ( isTheSame ) then
					found_2252_ = found_2252_ + 1
				end				
			end			
			if Driver:GetSumTypeName(mark.prop.Guid) == NAME_BELGROSPI then
				found_bel = found_bel + 1
				if ( isTheSame ) then
					found_bel_ = found_bel_ + 1
				end				
			end				
			--
		end
		
		local channels = getVideoChannel(mark)
		for cn, channel in ipairs(channels) do
			insert_frame(excel, data_range.Cells(line, 6+cn), mark, channel)
		end
		
		if line % 3 == 0 and not dlg:step(1.0 * line / #auto_marks, stuff.sprintf('Process %d / %d mark, found %d', line, #auto_marks, found_manuals)) then 
			break 
		end
	end
	
	
	local worksheet = excel._worksheet
	-- рисование таблицы вручную поставленных дефектов
	worksheet.Cells( 4, 2).Value2  = NAME_UIC_227_USER
	worksheet.Cells( 5, 2).Value2  = NAME_UIC_2251_USER
	worksheet.Cells( 6, 2).Value2  = NAME_UIC_2252_USER
	worksheet.Cells( 7, 2).Value2  = NAME_BELGROSPI_USER
	worksheet.Cells( 8, 2).Value2  = "TOTAL"
	
	local manual_227  = get_ManualCount(NAME_UIC_227_USER) 
	local manual_2251 = get_ManualCount(NAME_UIC_2251_USER)  
	local manual_2252 = get_ManualCount(NAME_UIC_2252_USER)
	local manual_bel  = get_ManualCount(NAME_BELGROSPI_USER)
	
	worksheet.Cells( 4, 3).Value2  = string.format('%d', manual_227  )  
	worksheet.Cells( 5, 3).Value2  = string.format('%d', manual_2251 )  
	worksheet.Cells( 6, 3).Value2  = string.format('%d', manual_2252 )  
	worksheet.Cells( 7, 3).Value2  = string.format('%d', manual_bel  )  
	worksheet.Cells( 8, 3).Value2  = string.format('%d', manual_227+manual_2251+manual_2252+manual_bel  ) 
    
	-- рисование таблицы и изображениями вручную поставленных дефектов
	local manual_marks_1, auto_marks = separate_mark_by_user_set(all_marks)
	for line, mark in ipairs(manual_marks_1) do
		local prop =  mark.prop
		data_range.Cells(line, 10).Value2 = mark_helper.format_path_coord(mark)
		data_range.Cells(line, 11).Value2 = prop.SysCoord
		data_range.Cells(line, 12).Value2 = Driver:GetSumTypeName(prop.Guid)
		
		local channels = getVideoChannel(mark)
		for cn, channel in ipairs(channels) do
			insert_frame(excel, data_range.Cells(line, 12+cn), mark, channel)
		end
	end
	
	worksheet.Cells( 4, 4).Value2  = NAME_UIC_227
	worksheet.Cells( 5, 4).Value2  = NAME_UIC_2251
	worksheet.Cells( 6, 4).Value2  = NAME_UIC_2252
	worksheet.Cells( 7, 4).Value2  = NAME_BELGROSPI
	worksheet.Cells( 8, 4).Value2  = "TOTAL"
	
	worksheet.Cells( 4, 5).Value2  = found_227
	worksheet.Cells( 5, 5).Value2  = found_2251
	worksheet.Cells( 6, 5).Value2  = found_2252
	worksheet.Cells( 7, 5).Value2  = found_bel
	local found_total = found_227+found_2251+found_2252+found_bel
	worksheet.Cells( 8, 5).Value2  = found_total
	
	
	worksheet.Cells( 4, 6).Value2  = found_227_
	worksheet.Cells( 5, 6).Value2  = found_2251_
	worksheet.Cells( 6, 6).Value2  = found_2252_
	worksheet.Cells( 7, 6).Value2  = found_bel_
	local found_total_ = found_227_+found_2251_+found_2252_+found_bel_
	worksheet.Cells( 8, 6).Value2  = found_total_	
	
	
	local auto_227  = get_AutoCount(NAME_UIC_227) 
	local auto_2251 = get_AutoCount(NAME_UIC_2251)  
	local auto_2252 = get_AutoCount(NAME_UIC_2252)
	local auto_bel  = get_AutoCount(NAME_BELGROSPI)
	
	worksheet.Cells( 4, 7).Value2  = string.format('%d', auto_227    )  
	worksheet.Cells( 5, 7).Value2  = string.format('%d', auto_2251  )  
	worksheet.Cells( 6, 7).Value2  = string.format('%d', auto_2252  )  
	worksheet.Cells( 7, 7).Value2  = string.format('%d', auto_bel    ) 
	local auto_total = auto_227+auto_2251+auto_2252+auto_bel 
	worksheet.Cells( 8, 7).Value2  = string.format('%d',  auto_total )  	

	worksheet.Cells( 4, 8).Value2  = string.format('%d', auto_227  - found_227  )  
	worksheet.Cells( 5, 8).Value2  = string.format('%d', auto_2251 - found_2251 )  
	worksheet.Cells( 6, 8).Value2  = string.format('%d', auto_2252 - found_2252 )  
	worksheet.Cells( 7, 8).Value2  = string.format('%d', auto_bel  - found_bel  )  
	worksheet.Cells( 8, 8).Value2  = string.format('%d', auto_total - found_total )  	
	
	worksheet.Cells( 4, 9).Value2  = string.format('%7.3f', (auto_227  - found_227 )*1000000/last_mark_sys_coord  )  
	worksheet.Cells( 5, 9).Value2  = string.format('%7.3f', (auto_2251 - found_2251)*1000000/last_mark_sys_coord  )  
	worksheet.Cells( 6, 9).Value2  = string.format('%7.3f', (auto_2252 - found_2252)*1000000/last_mark_sys_coord  )  
	worksheet.Cells( 7, 9).Value2  = string.format('%7.3f', (auto_bel  -  found_bel)*1000000/last_mark_sys_coord  )  
	worksheet.Cells( 8, 9).Value2  = string.format('%7.3f', (auto_total - found_total)*1000000/last_mark_sys_coord )  	
	
	
	excel:SaveAndShow()
end



-- =========================================================== --

local function AppendReports(reports)
	local name_pref = 'HUN Surface defects|'
	
	local local_reports = 
	{
		{name = name_pref..'All',    			fn = report_Simple, 	},
	}

	for _, report in ipairs(local_reports) do
		if report.fn then
			report.guids = keys(video_hun_juids),
			table.insert(reports, report)
		end
	end
end

-- тестирование
if not ATAPE then
	test_report  = require('test_report')
	
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	--test_report('D:/ATapeXP/Main/HUN_RECOG/HUN_RECOG_n/2019_11_15/Avikon-03H/16695/UH_MAV_70_J_2_28_1_19_1.xml') 
	
	report_Simple()
end


return {
	AppendReports = AppendReports,
	videogram = videogram,
}