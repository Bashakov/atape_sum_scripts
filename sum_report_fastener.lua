if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

local template_name =  'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ СКРЕПЛЕНИЙ.xlsm'

-- ========================================================================= 

local function report_fastener()
	iup.Message('Error', "Отчет не реализован")
end

-- ========================================================================= 

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании скреплений|'
	
	local sleppers_reports = 
	{
		{name = name_pref..'Определение параметров и состояния рельсовых скреплений (наличие визуально фиксируемых ослабленных скреплений, сломанных подкладок, отсутствие болтов, негодные прокладки, закладные и клеммные болты, шурупы, клеммы, анкеры)',    					fn=report_fastener, 			},
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids=guigs_sleepers
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then
	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	report_fastener()
end

return {
	AppendReports = AppendReports,
}