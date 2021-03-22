local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
local sumPOV = require "sumPOV"
require "ExitScope"


local test_report  = require('test_report')
test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 100000})

local template_path = Driver:GetAppPath() .. 'Scripts/'  .. 'СВОДНАЯ ВЕДОМОСТЬ ОТСТУПЛЕНИЙ.xlsx'

local excel = excel_helper(template_path, nil, false)
excel:ApplyPassportValues(mark_helper.GetExtPassport(Passport))

local user_range = excel._worksheet.UsedRange
local rr = user_range.Rows(8)
for col = 1, rr.Columns.count do
	local cell = rr.Columns(col)
	local val = cell.Value2
	print(col, val)
end