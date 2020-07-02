local function copy_update(src, new)
	local res = {}
	for n, v in pairs(src) do res[n] = v end
	for n, v in pairs(new) do res[n] = v end
	return res
end

-- =========================================================== 
-- ============== описание инструментов ====================== 
-- =========================================================== 

local DRAW_TOOL =
{
	
	gape = {
		sign = "gape", 
		fig  = "rect", 
		line_color = {r=255, g=0, b=0, a=100},
		fill_color = {r=0, g=0, b=0, a=0},
		name = 'Зазор',
		tooltip = 'Рисование зазора',
	},
	fishplate = {
		sign = "fishplate", 
		fig  = "rect", 
		line_color = {r=0, g=255, b=0, a=100},
		fill_color = {r=0, g=255, b=0, a=50},
		name = 'Накладка',
		tooltip = 'Рисование накладки',
	},
	fishplate_fault = {
		sign = "fishplate_fault", 
		fig  = "line", 
		line_color = {r=255, g=0, b=0, a=250},
		name = 'Дефект накладки',
	},
	joint = {
		sign = "joint", 
		fig  = "ellipse", 
		line_color = {r=255, g=255, b=255, a=255},
		fill_color = {r=0, g=0, b=0, a=0},
		name = 'Болтовое отверстие',
		tooltip = 'Рисование болтового отверстия',
	},
	surface = {
		sign = "surface", 
		fig  = "rect", 
		line_color = {r=192, g=0, b=192, a=150},
		fill_color = {r=192, g=0, b=192, a=10},
		name = 'Поверхностный дефект',
		tooltip = 'Рисование поверхностного дефекта',
	},
	beacon = {
		sign = "beacon", 
		fig  = "rect", 
		line_color = {r=67, g=149, b=209},
		name = 'Маячная отметка',
		tooltip = 'Установка маячной отметки',
	},
	rect_defect = 
	{
		sign = "defect", 
		fig  = "rect", 
		line_color = {r=255, g=0, b=0, a=200},
		fill_color = {r=255, g=0, b=0, a=10},
		name = 'Область Дефекта',
		tooltip = 'Рисование области дефекта',
	}
}
DRAW_TOOL.uic = copy_update(DRAW_TOOL.gape, {name = 'UIC', tooltip = 'Draw Area'})

DRAW_TOOL.joint_ok = copy_update(DRAW_TOOL.joint, {sign="joint_ok", name = 'Нормальный болт',   tooltip = '', line_color={r=128, g=128, b=255}})
DRAW_TOOL.joint_fl = copy_update(DRAW_TOOL.joint, {sign="joint_fl", name = 'Отсутсвующий болт', tooltip = '', line_color={r=255, g=0,   b=0  }})


-- =========================================================== 
-- ================ описание дефектов ======================== 
-- =========================================================== 

local DEFECTS =
{
	{
		group = "Венгры", 
		name = "UIC_2251", 
		tools = {DRAW_TOOL.uic}, 
		fn = make_recog_mark, 
		action_result = 'Surface_SLEEPAGE_SKID_UIC_2251', 
		guid = '{41486CAC-EBE9-46FF-ACCA-041AFAFFC531}'
	},
	{
		group = "Венгры", 
		name = "UIC_2252", 
		tools = {DRAW_TOOL.uic},
		fn = make_recog_mark, 
		action_result = 'Surface_SLEEPAGE_SKID_UIC_2252', 
		guid = '{3401C5E7-7E98-4B4F-A364-701C959AFE99}'
	},
	{
		group = "Венгры", 
		name = "UIC_227",  
		tools = {DRAW_TOOL.uic}, 
		fn = make_recog_mark, 
		action_result = 'Surface_SQUAT_UIC_227',          
		guid = '{13A7906C-BBFB-4EB3-86FA-FA74B77F5F35}'
	},
	
	{
		group = "Видео", 
		name = "АТС",  
		tools = {DRAW_TOOL.fishplate}, 
		fn = make_recog_mark, 
		guid = '{CBD41D28-9308-4FEC-A330-35EAED9FC805}'
	},
	{
		group = "Видео", 
		name = "Стык",  
		tools = {DRAW_TOOL.gape, DRAW_TOOL.joint_ok, DRAW_TOOL.joint_fl, DRAW_TOOL.fishplate, DRAW_TOOL.fishplate_fault}, 
		fn = make_recog_mark, 
		guid = '{CBD41D28-9308-4FEC-A330-35EAED9FC803}',
		action_result = 'CalcRailGap_User',
	},
	{
		group = "Видео", 
		name = "Поверхностный",  
		tools = {DRAW_TOOL.surface}, 
		fn = make_recog_mark, 
		guid = '{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}',
		action_result = 'Surface',
	},
	{
		group = "Видео", 
		name = "Маячная отметка",  
		tools = {DRAW_TOOL.beacon}, 
		fn = make_recog_mark, 
		guid = '{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}',
	},

}

-- ====================================================
-- 2019.10.03 Инциденты. Постановка пользователя.docx
-- ====================================================

local FASTENER_TOOL = {
	rect_defect = 
		DRAW_TOOL.rect_defect,
	rect_defect_slpr_plmnt = copy_update(DRAW_TOOL.rect_defect, {options={
		{"sleeper_count",   "Кол-во шпал",   {"", 1,2,3,4,5,6,7,8,9}},
		{"sleeper_placment", 'Расположение', {"", "прямая", "кривая", "подход к мосту или тоннелю"}}
	}}),
	rect_defect_cnctr = copy_update(DRAW_TOOL.rect_defect, {options={
		{"connector_type",      "тип скр.",     {"", "КБ-65", "Аpc", "ДО", "КД"}},
		{"connector_count",     "кол-во скр.",  {"", 1,2,3,4,5,6,7,8,9}},
		{"connector_placmaent", "расположение", {"", "прямая", "С.П. прямое", "С.П. боковое", "R<650", "R>650"}},
	}}),
}

local fastener_template =
{
	group = "Скрепления", 
	fn = make_simple_defect, 
	guid = '{3601038C-A561-46BB-8B0F-F896C2130001}',
}

table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000457", name="Выход подошвы рельса из реборд подкладок", tools={FASTENER_TOOL.rect_defect_slpr_plmnt}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000389", name="Дефектные клеммы", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000402", name="Дефектные подкладки", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004015853", name="Клемма под подошвой рельса", tools={FASTENER_TOOL.rect_defect}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000400", name="Наддернутые костыли", tools={FASTENER_TOOL.rect_defect}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000384", name="Отсутствие гаек на закладных болтах", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000395", name="Отсутствие гаек на клеммных болтах", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000409", name="Отсутствие или повреждение подрельсовой резины", tools={FASTENER_TOOL.rect_defect}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004003539", name="Отсутствует скрепление", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000394", name="Отсутствуют клеммы", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000385", name="Отсутствуют закладные болты", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000397", name="Отсутствуют клеммные болты", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000405", name="Отсутствуют подкладки", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000401", name="Отсутствующие или изломанные костыли", tools={FASTENER_TOOL.rect_defect_cnctr}}))
table.insert(DEFECTS, copy_update(fastener_template, {ekasui_code="090004000478", name="Отсутствующие или изломанные шурупы", tools={FASTENER_TOOL.rect_defect_cnctr}}))


local sleeper_template = 
{
	group = "Шпалы", 
	fn = make_simple_defect, 
	guid = '{3601038C-A561-46BB-8B0F-F896C2130002}',
	tools = {DRAW_TOOL.rect_defect},
}
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004015004", name="Дефектная деревянная шпала"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004015005", name="Дефектная железобетонная шпала"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004000369", name="Негодная деревянная шпала"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004000374", name="Негодная железобетонная шпала"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004000370", name="Отклонение от эпюрных значений укладки деревянных шпал"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004000375", name="Отклонения от эпюрных значений укладки железобетонных шпал"}))


local RAIL_JOINT_TOOL = {
	rect_defect = 
		DRAW_TOOL.rect_defect,
	fishplate_defect = copy_update(DRAW_TOOL.rect_defect, {options={
		{"fishplate_defect_type",   "тип повреждения",  {"", "излом", "трещина"}},
	}}),
	fishplate_bolt = copy_update(DRAW_TOOL.rect_defect, {options={
		{"fishplate_type",     "тип накладки",  {"", "4", "6"}},
		{"joint_missing_bolt", 'Отсутствуют',   {"", 1,2,3,4,5,6,7,8,9}}
	}}),
--	joint_width = copy_update(DRAW_TOOL.rect_defect, {options={
--		{"joint_width",     "Ширина зазора",  {"", "24<x<26", "26<x<30", "30<x<35", "35<x"}},
--	}}),
}
local rail_joint_template = 
{
	group = "Рельсовые стыки", 
	fn = make_simple_defect, 
	guid = '{3601038C-A561-46BB-8B0F-F896C2130003}',
	tools = {RAIL_JOINT_TOOL.rect_defect},
}

DRAW_TOOL.rect_defect_rail_joint = copy_update(DRAW_TOOL.rect_defect, {options={}})

table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004012058", name="Вертикальная ступенька в стыке"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004012059", name="Горизонтальная ступенька в стыке"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000474", name="Изломанная или дефектная стыковая накладка", tools={RAIL_JOINT_TOOL.fishplate_defect}}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004015840", name="Нулевые зазоры"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000465", name="Отсутствие стыковых болтов", tools={RAIL_JOINT_TOOL.fishplate_bolt}}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000477", name="Отсутствует стыковая накладка"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000509", name="Отсутствующие или неисправные элементы изолирующего стыка"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004012062", name="Превышение конструктивной величины стыкового зазора", add_width_from_user_rect=true}))

table.insert(DEFECTS,  {guid='{3601038C-A561-46BB-8B0F-F896C2130004}', group="Дефекты рельсов", ekasui_code="090004012002", name="Дефекты и повреждения подошвы рельса", fn = make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid='{3601038C-A561-46BB-8B0F-F896C2130004}', group="Дефекты рельсов", ekasui_code="090004012004", name="Излом рельса", fn = make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid='{3601038C-A561-46BB-8B0F-F896C2130004}', group="Дефекты рельсов", ekasui_code="090004012001", name="Поверхностный дефект рельса", fn = make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid='{3601038C-A561-46BB-8B0F-F896C2130004}', group="Дефекты рельсов", ekasui_code="090004012008", name="Поперечные трещины и изломы головки рельса", fn = make_simple_defect, tools = {DRAW_TOOL.rect_defect}})

table.insert(DEFECTS,  {guid='{3601038C-A561-46BB-8B0F-F896C2130005}', group="Балласт", ekasui_code="090004000482", name="Выплеск", fn = make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid='{3601038C-A561-46BB-8B0F-F896C2130005}', group="Балласт", ekasui_code="090004000484", name="Недостаточное количество балласта в шпальном ящике", fn = make_simple_defect, tools = {DRAW_TOOL.rect_defect}})

table.insert(DEFECTS,  {guid='{3601038C-A561-46BB-8B0F-F896C2130006}', group="Бесстыковой путь", ekasui_code="000000000000", name="Ненормативные подвижки бесстыкового пути", fn = make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid='{3601038C-A561-46BB-8B0F-F896C2130006}', group="Бесстыковой путь", ekasui_code="090004015367", name="Отсутствует/нечитаемая маркировка маячных шпал", fn = make_simple_defect, tools = {DRAW_TOOL.rect_defect}})

return DEFECTS
