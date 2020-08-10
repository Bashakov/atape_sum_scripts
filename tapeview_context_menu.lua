local sum_group_marks = require 'sum_group_marks'


local function add_scan_gruop_defects_menu(menu_items)
	local types = {
        {lbl = 'Все'},
        {lbl = ''},
		{lbl = 'Слепые зазоры', param = {'{B6BAB49E-4CEC-4401-A106-355BFB2E0001}'}},
		{lbl = 'Шпалы',         param = {'{B6BAB49E-4CEC-4401-A106-355BFB2E0011}'}},
		{lbl = 'Скрепления',    param = {'{B6BAB49E-4CEC-4401-A106-355BFB2E0021}'}},
    }
    local prefix = 'Сформировать групповые отметки|'
    for _, t in ipairs(types) do
        local text = prefix .. t.lbl
        local fn = function ()
            sum_group_marks.SearchGroupAutoDefects(t.param)
        end
        table.insert(menu_items, {name=text, fn=fn})
    end
    table.insert(menu_items, {name=prefix})
    table.insert(menu_items, {name=prefix .. 'Удалить Автоматические', fn = function ()
        local marks = Driver:GetMarks{
            ListType = 'all',
            GUIDS = {
                 '{B6BAB49E-4CEC-4401-A106-355BFB2E0001}',
                 '{B6BAB49E-4CEC-4401-A106-355BFB2E0011}',
                 '{B6BAB49E-4CEC-4401-A106-355BFB2E0021}',
            },
        }
        for _, mark in ipairs(marks) do
            mark:Delete()
        end
     end})
end

-- =============== EXPORT ===============

function GetMenuItems()
    local menu_items = {}
    add_scan_gruop_defects_menu(menu_items)
    return menu_items
end
