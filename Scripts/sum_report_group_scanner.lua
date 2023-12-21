local OOP = require "OOP"
-- local mark_helper = require 'sum_mark_helper'


-- построение распределения групповых отметок и потом поиск по нему
local GroupMarkSearch = OOP.class
{
	ctor = function(self, guids_group, check_defect_code)
		self._groups = {}
		self._guids_group = {}
        for _, g in ipairs(guids_group) do
            self._guids_group[g] = true
        end
        self._check_defect_code = check_defect_code
	end,

	add_groups = function (self, rows)
		for _, row in ipairs(rows) do
			if self:_is_group_mark(row) then
				local params = self._get_row_param(row)
		        table.insert(self._groups, params)
			end
		end
        -- table.sort(self._groups, function (m1, m2)
        --     return m1.from < m2.from
        -- end)
        return #self._groups ~= 0
	end,

    scan = function (self, row)
        if not self:_is_group_mark(row) then
            for _, group in ipairs(self._groups) do
                local row_desc = self._get_row_param(row)
                if self:_is_include(row_desc, group) then
                    return true
                end
            end
        end
		return false
	end,

    _is_include = function (self, row_desc, group)
        return
            (not self._check_defect_code or row_desc.code == group.code) and
            bit32.btest(row_desc.rail, group.rail) and
            row_desc.to >= group.from and
            row_desc.from <= group.to
    end,

	_is_group_mark = function (self, row)
        return self._guids_group[row.GUID]
	end,

	_get_row_param = function (row)
        return {
            from = row.SYS,
            to = row.SYS + row.LENGTH,
            rail = bit32.band(row.RAIL_RAW_MASK, 0x03),
            code = row.DEFECT_CODE,
        }
	end,
}

-- проверяем отметки на включение в групповые, выкидываем такие
local function remove_grouped_marks(rows, guids_group, check_defect_code)
    local searcher = GroupMarkSearch(guids_group, check_defect_code)
    if searcher:add_groups(rows) then
        local res = {}
        for _, row in ipairs(rows) do
            if not searcher:scan(row) then
                table.insert(res, row)
            end
        end
        rows = res
    end
    return rows
end

return remove_grouped_marks
