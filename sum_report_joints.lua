if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf


local video_joints_juids = 
{
	"{CBD41D28-9308-4FEC-A330-35EAED9FC801}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC804}",
}

-- ============================================================================= 


local function GetMarks()
	local marks = Driver:GetMarks{GUIDS=video_joints_juids}
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end


local function MakeJointMarkRow(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	row.SPEED_LIMIT = ''
	row.GAP_WIDTH = ''
	row.BLINK_GAP_COUNT = ''
	return row
end


local function scan_for_neigh_blind_joint(marks, dlg)
	
	local width_threshold = 3
	
	-- класс для поиска слепых зазоров по одному рельсу
	local BlickGapSearcher = OOP.class
	{
		-- инициализация
		ctor = function(self, groups)
			self.groups = groups	-- хранение найденных групп 
			self.cur_group = {}		-- текущая обрабатываемая группа, найденные слепые зазоры
		end,
		
		-- проверить очередной стык на рельсе
		append = function(self, mark)
			local width = mark_helper.GetGapWidth(mark) or 100000	
			if width <= width_threshold then
				table.insert(self.cur_group, mark)
			else 
				self:close()
			end
		end,
		
		-- закрыть поиск, выгрузить последнюю найденную группу
		close = function(self)
			if #self.cur_group > 1 then
				table.insert(self.groups, self.cur_group)
			end
			self.cur_group = {}
		end,
	}
	
	local groups = {}
	local rails = {}
	
	marks = mark_helper.sort_mark_by_coord(marks)
	for i, mark in ipairs(marks) do
		local rm = mark.prop.RailMask
		local r = rails[rm]
		if not r then
			r = BlickGapSearcher(groups)
			rails[rm] = r
		end
		r:append(mark)
		if dlg and i % 20 == 0 then
			dlg:step(i / #marks, string.format('Поиск %d / %d', i, #marks))
		end
	end
	
	for _, r in pairs(rails) do
		r:close()
	end
	
	groups = mark_helper.sort_stable(groups, function(group)
		local c = group[1].prop.SysCoord
		return c
	end)
	
	for n, g in ipairs(groups) do
		print(n)
		local s = g[1].prop.SysCoord
		for _, m in ipairs(g) do
			print('\t', m.prop.ID, m.prop.SysCoord, m.prop.SysCoord - s, m.prop.RailMask)
			s = m.prop.SysCoord
		end
	end
	
	return groups
end

-- ============================================================================= 

local function generate_rows_joint_width(marks, dlgProgress)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		local gap_width = mark_helper.GetGapWidth(mark)
		if gap_width and gap_width > 24 then
			local row = MakeJointMarkRow(mark)
			row.DEFECT_CODE = DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH[1]
			row.DEFECT_DESC = DEFECT_CODES.JOINT_EXCEED_GAP_WIDTH[2]
			row.GAP_WIDTH = gap_width
			
			if     gap_width <= 26 then 					row.SPEED_LIMIT = '100'
			elseif gap_width > 26 and gap_width <=30 then	row.SPEED_LIMIT = '60'
			elseif gap_width > 30 and gap_width <=35 then	row.SPEED_LIMIT = '25'
			else											row.SPEED_LIMIT = 'Движение закрывается'
			end
			
			table.insert(report_rows, row)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then 
			return
		end
	end
	
	return report_rows
end	


local function generate_rows_neigh_blind_joint(marks, dlgProgress)
	local groups = scan_for_neigh_blind_joint(marks, dlgProgress)
	
	local report_rows = {}
	for i, group in ipairs(groups) do
		local row = MakeJointMarkRow(group[1])
		
		row.DEFECT_CODE = DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP[1]
		row.DEFECT_DESC = DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP[2]
		row.BLINK_GAP_COUNT = #group
	    
		local to_report = 0 
		RAIL_12500_LENGTH_MIN = 10500
		RAIL_12500_LENGTH_MAX = 14500
		RAIL_25000_LENGTH_MIN = 23000
		RAIL_25000_LENGTH_MAX = 27000
		
		local temperature = mark_helper.GetTemperature(group[1]) or 0
		if temperature > 0 then                     -- считаем, при 20 градусах лето ???		
			SysCoord1 = group[1].prop.SysCoord
			SysCoord2 = group[#group].prop.SysCoord		
			
			local rail_max_length = 0 -- максимальная длина из группы 
			for j = 1, #group-1 do
				rail_max_length	= math.max(rail_max_length, group[j+1].prop.SysCoord - group[j].prop.SysCoord)
			end
			
			local rail_group_length = 0	
			rail_group_length = math.max( rail_group_length,  SysCoord2 - SysCoord1 )
			local rail_average_length = rail_group_length/(#group-1)
		
			-- ограничиваем по длине отметки включаемые в отчет
			-- если максимальная длина звена в диапазоне и 12.5 и 25 звеньев - то в отчет 
			if ( rail_max_length > RAIL_12500_LENGTH_MIN and rail_max_length < RAIL_25000_LENGTH_MAX) then
				to_report = 1
			end
				
			print( "****", #group, rail_group_length, rail_max_length, rail_average_length, SysCoord1, SysCoord1, to_report )		
		
			-- определеям является ли звено 25-метровым - находится в диапазоне. 
	        if ( rail_max_length > RAIL_25000_LENGTH_MIN and  rail_max_length< RAIL_25000_LENGTH_MAX ) then
				if  #group >= 2 then -- ограничение для 25 метрового: звена  больше 2-ух подряд 
					row.SPEED_LIMIT = 'ЗАПРЕЩЕНО'
					to_report = 1
				end	
			end	        
			-- определеям является ли звено 12.5-метровым - находится в диапазоне. 
			if ( rail_max_length > RAIL_12500_LENGTH_MIN and  rail_max_length< RAIL_12500_LENGTH_MAX ) then
				if  #group >= 4 then -- ограничение для 12.5 метрового: звена  больше 4-ух подряд 
					row.SPEED_LIMIT = 'ЗАПРЕЩЕНО'
					to_report = 1
				end	
			end					
			
		end
		-- добавляем в отчет
		if ( to_report == 1 ) then
			table.insert(report_rows, row)		
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Отработка %d / %d отметок, найдено %d', i, #groups, #report_rows)) then 
			return
		end
	end
	
	return report_rows
end


local function generate_rows_joint_step(marks, dlgProgress)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		local step_vert = mark_helper.GetRailGapStep(mark) or 0
		step_vert = math.abs(step_vert)
		if step_vert > 1 then
			local row = MakeJointMarkRow(mark)
			row.DEFECT_CODE = DEFECT_CODES.JOINT_HOR_STEP[1]
			row.DEFECT_DESC = DEFECT_CODES.JOINT_HOR_STEP[2]
			row.GAP_WIDTH = mark_helper.GetGapWidth(mark) or ''
			local temperature = mark_helper.GetTemperature(mark) or 0
			
			if     step_vert > 1 and step_vert <= 2 then	row.SPEED_LIMIT = temperature > 25 and '80' or '50' 
			elseif step_vert > 2 and step_vert <= 4 then	row.SPEED_LIMIT = temperature > 25 and '40' or '25'
			elseif step_vert > 4 and step_vert <= 5 then	row.SPEED_LIMIT = '15' 
			else                                         	row.SPEED_LIMIT = 'Движение закрывается' 	end
			table.insert(report_rows, row)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then 
			return
		end
	end
	
	return report_rows
end


local function generate_rows_fishplate(marks, dlgProgress)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		
--		local fishpalte_fault_str = {
--			[0] = 'испр.',
--			[1] = 'надр.',
--			[3] = 'трещ.',
--			[4] = 'изл.',
--		}

--[[ Дмитрий 14:23
	Закрытие движения при изломе накладки. 
	Замечание при трещине одной накладки.
	40 км/ч при трещине двух накладок.
]]
		local fishpalte_fault, fishpalte_fault_cnt = mark_helper.GetFishplateState(mark)
		if fishpalte_fault and fishpalte_fault > 0 then 
			local row = MakeJointMarkRow(mark)
			row.DEFECT_CODE = DEFECT_CODES.JOINT_FISHPLATE_DEFECT[1]
			row.DEFECT_DESC = DEFECT_CODES.JOINT_FISHPLATE_DEFECT[2]
			if fishpalte_fault == 4 then
				row.SPEED_LIMIT = 'Движение закрывается'
			elseif fishpalte_fault == 3 then
				if fishpalte_fault_cnt > 1 then
					row.SPEED_LIMIT = '40'
				else
					row.SPEED_LIMIT = 'Замечание'
				end
			end
			table.insert(report_rows, row)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then 
			return
		end
	end
	
	return report_rows
end


local function generate_rows_missing_bolt(marks, dlgProgress)
	local report_rows = {}
	for i, mark in ipairs(marks) do
	
		local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
		if valid_on_half and valid_on_half < 2 then
			local row = MakeJointMarkRow(mark)
			row.DEFECT_CODE = DEFECT_CODES.JOINT_MISSING_BOLT[1]
			row.DEFECT_DESC = DEFECT_CODES.JOINT_MISSING_BOLT[2]
			
			if valid_on_half == 1 then
				row.SPEED_LIMIT = '25'
			elseif valid_on_half == 0 then	
				row.SPEED_LIMIT = 'Закрытие движения'
			else
				row.SPEED_LIMIT = '??'
			end
			table.insert(report_rows, row)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then 
			return
		end
	end
	return report_rows
end

local function generate_rows_WeldedBond(marks, dlgProgress)
	local report_rows = {}
	for i, mark in ipairs(marks) do
		
		local status = mark_helper.GetWeldedBondStatus(mark)
		if status == 1 then  -- <PARAM name='ConnectorFault' value='1' value_='0-исправен, 1-неисправен'/>
			local row = MakeJointMarkRow(mark)
			row.DEFECT_CODE = DEFECT_CODES.JOINT_WELDED_BOND_FAULT[1]
			row.DEFECT_DESC = DEFECT_CODES.JOINT_WELDED_BOND_FAULT[2]
			table.insert(report_rows, row)
		end
		
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d отметок, найдено %d', i, #marks, #report_rows)) then 
			return
		end
	end
	return report_rows
end


local function report_broken_insulation()
	iup.Message('Error', "Отчет не реализован")
end

-- ============================================================================= 

local function make_report_generator(...)
	
	local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ РЕЛЬСОВЫХ СТЫКОВ.xlsm'
	local sheet_name = 'В2 СТК'
	
	return AVIS_REPORT.make_report_generator(GetMarks, 
		report_template_name, sheet_name, ...)
end

local function make_report_ekasui(...)
	return EKASUI_REPORT.make_ekasui_generator(GetMarks, ...)
end	

local function make_report_videogram(...)
	local row_generators = {...}
		
	function gen(mark)
		local report_rows = {}
		if mark and mark_helper.table_find(video_joints_juids, mark.prop.Guid) then
			for _, fn_gen in ipairs(row_generators) do
				local cur_rows = fn_gen({mark}, nil)
				for _, row in ipairs(cur_rows) do
					table.insert(report_rows, row)
				end
			end
		end
		return report_rows
	end
	
	return gen
end	

-- ============================================================================= 

local all_generators = {
	generate_rows_joint_width, 
	generate_rows_neigh_blind_joint, 
	generate_rows_joint_step, 
	generate_rows_fishplate, 
	generate_rows_missing_bolt, 
	generate_rows_WeldedBond
}

local report_joint_width = make_report_generator(generate_rows_joint_width)
local report_neigh_blind_joint = make_report_generator(generate_rows_neigh_blind_joint)
local report_joint_step = make_report_generator(generate_rows_joint_step)
local report_fishplate = make_report_generator(generate_rows_fishplate)
local report_missing_bolt = make_report_generator(generate_rows_missing_bolt)
local report_WeldedBond = make_report_generator(generate_rows_WeldedBond)
local report_ALL = make_report_generator(
	table.unpack(all_generators)
)

local ekasui_joint_width = make_report_ekasui(generate_rows_joint_width)
local ekasui_neigh_blind_joint = make_report_ekasui(generate_rows_neigh_blind_joint)
local ekasui_joint_step = make_report_ekasui(generate_rows_joint_step)
local ekasui_fishplate = make_report_ekasui(generate_rows_fishplate)
local ekasui_missing_bolt = make_report_ekasui(generate_rows_missing_bolt)
local ekasui_WeldedBond = make_report_ekasui(generate_rows_WeldedBond)
local ekasui_ALL = make_report_ekasui( 
	table.unpack(all_generators)
)


local videogram = make_report_videogram(
	table.unpack(all_generators)
)


-- ============================================================================= 


local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании рельсовых стыков|'
	
	local sleppers_reports = 
	{
		{name = name_pref..'ВСЕ',    																	fn = report_ALL, 				},
		{name = name_pref..'Ширина стыкового зазора, мм',    											fn = report_joint_width, 				},
		{name = name_pref..'Определение двух подряд и более нулевых зазоров',    						fn = report_neigh_blind_joint,			},
		{name = name_pref..'Горизонтальные ступеньки в стыках, мм',    									fn = report_joint_step,					},
		{name = name_pref..'Определение наличия и состояния (надрыв, трещина, излом) накладок',			fn = report_fishplate,					},
		{name = name_pref..'Определение наличия и состояния (ослаблен, раскручен, не типовой) стыковых болтов',		fn = report_missing_bolt,	},
		{name = name_pref..'Определение наличия и состояния приварных рельсовых соединителей',    		fn = report_WeldedBond, 				},
		{name = name_pref..'*Определение наличия и видимых повреждений изоляции в изолирующих стыках',	fn = report_broken_insulation,			},
		
		{name = name_pref..'ЕКАСУИ ВСЕ',																		fn = ekasui_ALL,			},
		{name = name_pref..'ЕКАСУИ Ширина стыкового зазора, мм',    											fn = ekasui_joint_width, 				},
		{name = name_pref..'ЕКАСУИ Определение двух подряд и более нулевых зазоров',    						fn = ekasui_neigh_blind_joint,			},
		{name = name_pref..'ЕКАСУИ  ступеньки в стыках, мм',    												fn = ekasui_joint_step,					},
		{name = name_pref..'ЕКАСУИ Определение наличия и состояния (надрыв, трещина, излом) накладок',			fn = ekasui_fishplate,					},
		{name = name_pref..'ЕКАСУИ Определение наличия и состояния (ослаблен, раскручен, не типовой) стыковых болтов',		fn = ekasui_missing_bolt,	},
		{name = name_pref..'ЕКАСУИ Определение наличия и состояния приварных рельсовых соединителей',    		fn = ekasui_WeldedBond, 				},
	}

	for _, report in ipairs(sleppers_reports) do
		if report.fn then
			report.guids = video_joints_juids
			table.insert(reports, report)
		end
	end
end

-- тестирование
if not ATAPE then
	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
    --test_report('D:/ATapeXP/Main/TEST/ZeroGap/2019_06_13/Avikon-03M/6284/[494]_2017_06_14_03.xml')	

	--report_ALL()
	--ekasui_ALL()
	report_neigh_blind_joint()
end



return {
	AppendReports = AppendReports,
	videogram = videogram,
}
