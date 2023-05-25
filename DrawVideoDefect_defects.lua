-- luacheck: ignore 631

local GUIDS = require "sum_types"

local function copy_update(src, new)
	local res = {}
	for n, v in pairs(src) do res[n] = v end
	for n, v in pairs(new or {}) do res[n] = v end
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
		action_result = 'Surface_SLEEPAGE_SKID_UIC_2251_USER',
		guid = GUIDS.SLEEPAGE_SKID_1_USER,
	},
	{
		group = "Венгры",
		name = "UIC_2252",
		tools = {DRAW_TOOL.uic},
		fn = make_recog_mark,
		action_result = 'Surface_SLEEPAGE_SKID_UIC_2252_USER',
		guid = GUIDS.SLEEPAGE_SKID_2_USER,
	},
	{
		group = "Венгры",
		name = "UIC_227",
		tools = {DRAW_TOOL.uic},
		fn = make_recog_mark,
		action_result = 'Surface_SQUAT_UIC_227_USER',
		guid = GUIDS.SQUAT_USER,
	},

	{
		group = "Видео",
		name = "АТС",
		tools = {DRAW_TOOL.fishplate},
		fn = make_recog_mark,
		guid = GUIDS.VID_INDT_ATS_USER,
	},
	{
		group = "Видео",
		name = "Стык",
		tools = {DRAW_TOOL.gape, DRAW_TOOL.joint_ok, DRAW_TOOL.joint_fl, DRAW_TOOL.fishplate, DRAW_TOOL.fishplate_fault},
		fn = make_recog_mark,
		guid = GUIDS.VID_INDT_3,
		action_result = 'CalcRailGap_User',
	},
	{
		group = "Видео",
		name = "ИзоСтык",
		tools = {DRAW_TOOL.gape, DRAW_TOOL.joint_ok, DRAW_TOOL.joint_fl, DRAW_TOOL.fishplate, DRAW_TOOL.fishplate_fault},
		fn = make_recog_mark,
		guid = GUIDS.VID_ISO,
		action_result = 'CalcRailGap_User',
	},
	{
		group = "Видео",
		name = "Поверхностный",
		tools = {DRAW_TOOL.surface},
		fn = make_recog_mark,
		guid = GUIDS.VID_SURF,
		action_result = 'Surface',
	},
	{
		group = "Видео",
		name = "Маячная отметка",
		tools = {DRAW_TOOL.beacon},
		fn = make_recog_mark,
		guid = GUIDS.M_SPALA,
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
	fn=make_simple_defect,
	guid = GUIDS.FASTENER_USER,
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
	fn=make_simple_defect,
	guid = GUIDS.SLEEPER_USER,
	tools = {DRAW_TOOL.rect_defect},
}
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004015004", name="Дефектная деревянная шпала"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004015005", name="Дефектная железобетонная шпала"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004000369", name="Негодная деревянная шпала"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004000374", name="Негодная железобетонная шпала"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004000370", name="Нарушение эпюры: ДШ"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004000375", name="Нарушение эпюры: ЖБШ"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004017133", name="Разворот ДШ от своей оси"}))
table.insert(DEFECTS, copy_update(sleeper_template, {ekasui_code="090004017132", name="Разворот ЖБШ от своей оси"}))


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
	fn=make_simple_defect,
	guid = GUIDS.RAIL_JOINT_USER,
	tools = {RAIL_JOINT_TOOL.rect_defect},
}

DRAW_TOOL.rect_defect_rail_joint = copy_update(DRAW_TOOL.rect_defect, {options={}})

table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004012058", name="Вертикальная ступенька в стыке"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004012059", name="Горизонтальная ступенька в стыке"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000474", name="Изломанная или дефектная стыковая накладка", tools={RAIL_JOINT_TOOL.fishplate_defect}, speed_limit="0"}))
-- https://bt.abisoft.spb.ru/view.php?id=765
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000475", name="Излом одной  накладки в стыке", tools={RAIL_JOINT_TOOL.fishplate_defect}, speed_limit="0"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000476", name="Излом 2-х накладок в стыке", tools={RAIL_JOINT_TOOL.fishplate_defect}, speed_limit="0"}))

-- https://bt.abisoft.spb.ru/view.php?id=765
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004012061", name="Наличие двух подряд слитых зазоров"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004015838", name="Три и более слепых (нулевых) зазоров подряд по левой нити"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004015839", name="Три и более слепых (нулевых) зазоров подряд по правой нити"}))

-- https://bt.abisoft.spb.ru/view.php?id=765
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000466", name="Отсутствие болтов: ХОО-ООО", tools={RAIL_JOINT_TOOL.fishplate_bolt}}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000467", name="Отсутствие болтов: ХХ-ОО, ХХХ-000", tools={RAIL_JOINT_TOOL.fishplate_bolt}, speed_limit="0"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000471", name="Отсутствие болтов: ХО-ОО, ХХО-ООО", tools={RAIL_JOINT_TOOL.fishplate_bolt}, speed_limit="25"}))

table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000477", name="Отсутствует стыковая накладка", speed_limit="0"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004000509", name="Отсутствующие или неисправные элементы изолирующего стыка"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004016149", name="Превышение конструктивной величины стыкового зазора левой нити", add_width_from_user_rect=true}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004016150", name="Превышение конструктивной величины стыкового зазора правой нити", add_width_from_user_rect=true}))

table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004017121", name="Металлическая пластина между головкой рельса и стыковой накладкой", add_width_from_user_rect=true, speed_limit="40"}))
table.insert(DEFECTS, copy_update(rail_joint_template, {ekasui_code="090004017122", name="Нетиповые и посторонние предметы в стыке", add_width_from_user_rect=true}))

table.insert(DEFECTS,  {guid=GUIDS.RAIL_DEFECTS_USER, group="Дефекты рельсов", ekasui_code="090004012002", name="Дефекты и повреждения подошвы рельса", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="15"})
table.insert(DEFECTS,  {guid=GUIDS.RAIL_DEFECTS_USER, group="Дефекты рельсов", ekasui_code="090004012004", name="Излом рельса", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, "0"})
table.insert(DEFECTS,  {guid=GUIDS.RAIL_DEFECTS_USER, group="Дефекты рельсов", ekasui_code="090004012001", name="Поверхностный дефект рельса", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid=GUIDS.RAIL_DEFECTS_USER, group="Дефекты рельсов", ekasui_code="090004012008", name="Поперечные трещины головки рельса", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="15"})
table.insert(DEFECTS,  {guid=GUIDS.RAIL_DEFECTS_USER, group="Дефекты рельсов", ekasui_code="090004012009", name="Продольные трещины головки рельса", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="15"})

--!!! изменен код table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004000482", name="Выплеск", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, ""})   зависит от длины выплеска 2,5-5 метров "60" и "40" на стыке; 5-7,5 "40" и "25" на стыке; более 7,5 "25" в обычном пути и "15" на стыке;
table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004017135", name="Выплеск в плети 2,5-5 метров", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="60"})
table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004017135", name="Выплеск в плети 5-7,5 метров", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="40"})
table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004017135", name="Выплеск в плети более 7,5 метров", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="25"})

table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004017136", name="Выплеск в стыке 2,5-5 метров", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="40"})
table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004017136", name="Выплеск в стыке 5-7,5 метров", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="25"})
table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004017136", name="Выплеск в стыке более 7,5 метров", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}, speed_limit="15"})

table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004000484", name="Недостаточное количество балласта в шпальном ящике", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004000486", name="Отсутствие подрезки балласта", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid=GUIDS.BALLAST_USER, group="Балласт", ekasui_code="090004000494", name="Растительность", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})

-- https://bt.abisoft.spb.ru/view.php?id=765 3 новых кода взамен старого:
table.insert(DEFECTS,  {guid=GUIDS.USER_JOINTLESS_DEFECT, group="Бесстыковой путь", ekasui_code="090004015469", name="Угон плети до 5мм включительно", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid=GUIDS.USER_JOINTLESS_DEFECT, group="Бесстыковой путь", ekasui_code="090004015470", name="Угон плети более 5 до 10мм",     fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid=GUIDS.USER_JOINTLESS_DEFECT, group="Бесстыковой путь", ekasui_code="090004015508", name="Угон плети более 10 мм",         fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})

table.insert(DEFECTS,  {guid=GUIDS.USER_JOINTLESS_DEFECT, group="Бесстыковой путь", ekasui_code="090004015367", name="Отсутствует/нечитаемая маркировка маячных шпал", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})
table.insert(DEFECTS,  {guid=GUIDS.USER_JOINTLESS_DEFECT, group="Бесстыковой путь", ekasui_code="090004015467", name="Нарушения крепления маячной шпалы", fn=make_simple_defect, tools = {DRAW_TOOL.rect_defect}})


-- ================= групповые дефекты =================

local group_defect_desc = {

	{GUIDS.GROUP_GAP_USER, 2, '090004012061', 'Стыки', '2 слитых зазора подряд'}, --Наличие двух подряд слитых зазоров
	{GUIDS.GROUP_GAP_USER, 2, '090004000795', 'Стыки', '2 слитых зазора подряд на рельсе 25 м'}, --Наличие двух подряд слитых зазоров при длине рельсов 25 м
	{GUIDS.GROUP_GAP_USER, 3, '090004015838', 'Стыки', '3 слитых зазора подряд: левая нить'}, --Три и более слепых (нулевых) зазоров подряд по левой нити
	{GUIDS.GROUP_GAP_USER, 3, '090004015839', 'Стыки', '3 слитых зазора подряд: правая нить'}, --Три и более слепых (нулевых) зазоров подряд по правой нити

	--!!! {GUIDS.GROUP_SPR_USER, 3, '090004000348', 'Шпалы', 'Куст: 3 дер.ш.: Р50 и легче: прямая, кривая R>650м'},  --«Куст» из 3-х негодных деревянных шпал при рельсах Р50, Р65  и легче (прямая или кривая радиусом более 650м)
	--!!! {GUIDS.GROUP_SPR_USER, 3, '090004000355', 'Шпалы', 'Куст: 3 дер.ш.: Р50 и легче: кривая R<650м'}, --«Куст» из 3-х негодных деревянных шпал при рельсах Р50, Р65 и  легче (кривая радиусом менее 650м)
	--!!! {GUIDS.GROUP_SPR_USER, 3, '090004000347', 'Шпалы', 'Куст: 3 дер.ш.: Р65, Р75: прямая, кривая R>650м'},--«Куст» из 3-х негодных деревянных шпал при рельсах Р65, Р75 (прямая или кривая радиусом более 650м)
	--!!! {GUIDS.GROUP_SPR_USER, 4, '090004000357', 'Шпалы', 'Куст: 4 дер.ш.: Р50 и легче: кривая R<650м'}, --«Куст» из 4-х негодных деревянных шпал при рельса Р50 и легче (кривая радиусом менее 650м)
	--!!! {GUIDS.GROUP_SPR_USER, 4, '090004000350', 'Шпалы', 'Куст: 4 дер.ш.: Р50 и легче: прямая, кривая R>650м'}, --«Куст» из 4-х негодных деревянных шпал при рельса Р50 и легче (прямая или кривая радиусом более 650м)
	{GUIDS.GROUP_SPR_USER, 4, '090004000354', 'Шпалы', 'Куст: 4 дер.ш.: Р65, Р75: кривая R<650м', "40/25"},  --«Куст» из 4-х негодных деревянных шпал при рельсах Р65, Р75 (кривая радиусом менее 650м)
	{GUIDS.GROUP_SPR_USER, 4, '090004000349', 'Шпалы', 'Куст: 4 дер.ш.: Р65, Р75: прямая, кривая R>650м', "60/40"}, --«Куст» из 4-х негодных деревянных шпал при рельсах Р65, Р75 (прямая или кривая радиусом более 650м)
	{GUIDS.GROUP_SPR_USER, 4, '090004017125', 'Шпалы', 'Куст: 4 жб.ш.: Р65, Р75: кривая R<650м', "40/25"},  --«Куст» из 4-х негодных железобетонных шпал при рельсах Р65, Р75 (кривая радиусом менее 650м)
	{GUIDS.GROUP_SPR_USER, 4, '090004017126', 'Шпалы', 'Куст: 4 жб.ш.: Р65, Р75: прямая, кривая R>650м', "60/40"}, --«Куст» из 4-х негодных железобетонных шпал при рельсах Р65, Р75 (прямая или кривая радиусом более 650м)
	--{GUIDS.GROUP_SPR_USER, 5, '090004000353', 'Шпалы', 'Куст: 5 дер.ш.: Р50 и легче: прямая, кривая R>650м'}, --«Куст» из 5-ти негодных деревянных шпал и более при рельсах Р50  и легче (прямая или кривая радиусом более 650м)
	{GUIDS.GROUP_SPR_USER, 5, '090004000356', 'Шпалы', 'Куст: 5 дер.ш.: Р65, Р75: кривая R<650м', "15"},  --«Куст» из 5-ти негодных деревянных шпал и более при рельсах Р65, Р75 (кривая радиусом менее 650м)
	{GUIDS.GROUP_SPR_USER, 5, '090004000351', 'Шпалы', 'Куст: 5 дер.ш.: Р65, Р75: прямая, кривая R>650м', "40/25"}, --«Куст» из 5-ти негодных деревянных шпал при рельсах Р65, Р75 (прямая или кривая радиусом более 650м)
	{GUIDS.GROUP_SPR_USER, 5, '090004017127', 'Шпалы', 'Куст: 5 жб.ш.: Р65, Р75: кривая R<650м', "15"},  --«Куст» из 5-ти негодных железобетонных шпал и более при рельсах Р65, Р75 (кривая радиусом менее 650м)
	{GUIDS.GROUP_SPR_USER, 5, '090004017129', 'Шпалы', 'Куст: 5 жб.ш.: Р65, Р75: прямая, кривая R>650м', "40/25"}, --«Куст» из 5-ти негодных железобетонных шпал при рельсах Р65, Р75 (прямая или кривая радиусом более 650м)
	--{GUIDS.GROUP_SPR_USER, 6, '090004000352', 'Шпалы', 'Куст: 6 дер.ш. и более: Р65, Р75: кривая R<650м'}, --«Куст» из 6-ти  негодных деревянных шпал и более при рельсах Р65, Р75 (кривая радиусом менее 650м)
	{GUIDS.GROUP_SPR_USER, 6, '090004000352', 'Шпалы', 'Куст: 6 дер.ш. и более: прямая, кривая R>650м', "15"},  --«Куст» из 6-ти негодных деревянных брусьев и более при рельсах Р65 (прямая или кривая радиусом более 650м)
	{GUIDS.GROUP_SPR_USER, 6, '090004017130', 'Шпалы', 'Куст: 6 жб.ш. и более: прямая, кривая R>650м', "15"},  --«Куст» из 6-ти негодных железобетонных брусьев и более при рельсах Р65 (прямая или кривая радиусом более 650м)
	{GUIDS.GROUP_SPR_USER, 2, '090004017134', 'Шпалы', 'Куст в стыке: 2 дер.ш.,брус', "40"},  --Два подряд и более негодных деревянных шпал (брусьев) в стыке для путей 1-3 классов
	{GUIDS.GROUP_SPR_USER, 2, '090004017124', 'Шпалы', 'Куст в стыке: 2 жб.ш.,брус', "40"},  --Два подряд и более негодных железобетонных шпал (брусьев) в стыке для путей 1-3 классов

	{GUIDS.GROUP_FSTR_USER, 3, '090004017091', 'Скрепления', 'Выход подошвы из реборд: 3 шп. подряд: кривая, 200м от моста/тунеля 25<l<100м, 500м от моста/тунеля >100м', "25"},  --Выход подошвы рельса из реборд подкладок на 3-х шпалах (брусьях) подряд на кривых участках, на подходах к мостам и тунелям протяжением по 200 м при длине мостов и тоннелей от 25 до 100 м и по 500 м при длине мостов и тоннелейболее 100 м
	{GUIDS.GROUP_FSTR_USER, 3, '090004000458', 'Скрепления', 'Выход подошвы из реборд: 3 шп. подряд: наружная сторона прямых', "60"},  --Выход подошвы рельса из реборд подкладок на 3-х шпалах (брусьях) подряд с наружной стороны прямых участков, исключая подходы к мостам и тунелям
	{GUIDS.GROUP_FSTR_USER, 4, '090004017092', 'Скрепления', 'Выход подошвы из реборд: 4 шп. подряд: прямая', "40"}, --Выход подошвы рельса из реборд подкладок на 4-х шпалах (брусьях) подряд на  прямых участках
	{GUIDS.GROUP_FSTR_USER, 4, '090004017093', 'Скрепления', 'Выход подошвы из реборд: 4 шп. подряд: кривая, наружная сторона прямых на подходе к мосту/тунелю', "0"},  --Выход подошвы рельса из реборд подкладок на 4-х шпалах (брусьях)на кривых, а так же на прямых на подходах к мостам и тоннелям подряд с наружной стороны прямых участков, исключая подходы к мостам и тунелям
	{GUIDS.GROUP_FSTR_USER, 5, '090004017094', 'Скрепления', 'Выход подошвы рельса из реборд: 5 шп. подряд', "0"},  --Выход подошвы рельса из реборд подкладок на 5 шпалах (брусьях) подряд

	--{GUIDS.GROUP_FSTR_USER, 3, '090004000882', 'Скрепления', 'Зазор/напрессовка снега между рельсом и подкладками: 3 шп. и более'}, --Зазор между рельсом и подкладками (провис рельса) или напрессовка снега или льда между рельсом и подкладками на 3-х и более брусьях
	--{GUIDS.GROUP_FSTR_USER, 3, '090004000460', 'Скрепления', 'Зазор/напрессовка снега между рельсом и подкладками: 3 шп. и более: кривая R<650м'}, --Зазор между рельсом и подкладками (провис рельса) или напрессовка снега или льда между рельсом и подкладками на 3-х и более шпалах в кривых радиусом 650 м и менее

	{GUIDS.GROUP_FSTR_USER, 6, '090004017095', 'Скрепления', 'Деф.скр.: 6 шп. и более: одна нить: кривая R<650м', "15"},  --Отсутствует или дефектное скрепление скрепление в кривых радиусом 650 м и менее более чем на 5 шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 4, '090004017096', 'Скрепления', 'Деф.скр.: 4 шп.: одна нить: кривая R<650м', "25"},  --Отсутствует или дефектное скрепление скрепление в кривых радиусом 650 м и менее на 4-х шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 5, '090004017097', 'Скрепления', 'Деф.скр.: 5 шп.: одна нить: кривая R<650м', "40"},  --Отсутствует или дефектное скрепление скрепление в кривых радиусом 650 м и менее на 5 шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 6, '090004017098', 'Скрепления', 'Деф.скр.: 6 шп. и более: одна нить: кривая R>650м', "15"},  --Отсутствует или дефектное скрепление скрепление в прямых и кривых радиусом более 650 м более чем на 6 шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 4, '090004017099', 'Скрепления', 'Деф.скр.: 4 шп.: одна нить: прямая, кривая R>650м', "60"},  --Отсутствует или дефектное скрепление скрепление в прямых и кривых радиусом более 650 м на 4-х шпалах подряд  по одной нити
	{GUIDS.GROUP_FSTR_USER, 5, '090004017100', 'Скрепления', 'Деф.скр.: 5 шп.: одна нить: прямая, кривая R>650м', "40"},  --Отсутствует или дефектное скрепление скрепление в прямых и кривых радиусом более 650 м на 5 шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 6, '090004017101', 'Скрепления', 'Деф.скр.: 6 шп.: одна нить: прямая, кривая R>650м', "25"},  --Отсутствует или дефектное скрепление скрепление в прямых и кривых радиусом более 650 м на 6 шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 3, '090004017102', 'Скрепления', 'Деф.бесподкл.скр.: 3 шп.: одна нить', "40"},  --Отсутствует или дефектное скрепление скрепление на бесподкладочных скреплениях  на 3-х шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 4, '090004017103', 'Скрепления', 'Деф.бесподкл.скр.: 4 шп.: одна нить', "25"},  --Отсутствует или дефектное скрепление скрепление на бесподкладочных скреплениях  на 4-х шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 5, '090004017104', 'Скрепления', 'Деф.бесподкл.скр.: 5 шп. и более: одна нить', "15"},  --Отсутствует или дефектное скрепление скрепление на бесподкладочных скреплениях  на 5 и более шпалах подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 2, '090004017105', 'Скрепления', 'Деф.скр.стрелка: 2 шп.: одна нить', "60/40"},  --Отсутствует или дефектное скрепление скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити  на 2-х брусьях подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 3, '090004017106', 'Скрепления', 'Деф.скр.стрелка: 3 шп.: одна нить', "40/25"},  --Отсутствует или дефектное скрепление скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити  на 3-х брусьях подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 4, '090004017107', 'Скрепления', 'Деф.скр.стрелка: 4 шп.: одна нить', "25/15"},  --Отсутствует или дефектное скрепление скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити  на 4-х брусьях подряд по одной нити
	{GUIDS.GROUP_FSTR_USER, 5, '090004017108', 'Скрепления', 'Деф.скр.стрелка: 5 шп. и более: одна нить', "15/0"},  --Отсутствует или дефектное скрепление скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити  на 5 и более брусьях подряд
}

for _, gd in ipairs(group_defect_desc) do
	table.insert(DEFECTS, {
		group = "Групповые дефекты",
		fn = make_group_defect,
		tools = {DRAW_TOOL.rect_defect},
		guid = gd[1],
		objects_count = gd[2],
		ekasui_code = gd[3],
		--name = gd[4] .. ':' .. gd[5]
		name = gd[5],
		speed_limit = gd[6],
	})
end

-- ================= ЖАТ =================

local JAT_TOOL = {
	way = {
		sign = "jat_way",
		fig  = "rect",
		line_color = {r=255, g=0, b=0, a=200},
		fill_color = {r=255, g=0, b=0, a=10},
		name = 'Расположение дефекта: ПУТЬ',
		tooltip = 'Рисование дефекта тип: ПУТЬ',
		icon = "file:Scripts/жат_путь.png",
		options = {},
		static_options = {
			RAILWAY_TYPE = "путь",	-- путь
			RAILWAY_HOUSE = "П", 	-- хозяйство пути.
		},
	},
	joint = {
		sign = "jat_joint",
		fig  = "rect",
		line_color = {r=0, g=0, b=255, a=200},
		fill_color = {r=0, g=0, b=255, a=10},
		name = 'Расположение дефекта: СТРЕЛКА',
		tooltip = 'Рисование дефекта тип: СТРЕЛКА',
		icon = "file:Scripts/жат_стрелка.png",
		options = {},
		static_options = {
			RAILWAY_TYPE = "стрелка",	-- стрелка
			RAILWAY_HOUSE = "П", 		-- хозяйство пути.
		},
	},
	scb = {
		sign = "jat_scb",
		fig  = "rect",
		line_color = {r=0, g=255, b=0, a=200},
		fill_color = {r=0, g=255, b=0, a=10},
		name = 'Расположение дефекта СЦБ',
		tooltip = 'Расположение дефекта: СЦБ',
		icon = "file:Scripts/жат_СЦБ.png",
		options = {},
		static_options = {
			RAILWAY_TYPE = "СЦБ",	-- сигнализация, централизация, блокировка
			RAILWAY_HOUSE = "Ш", 	-- хозяйство напольной автоматики и телемеханики
		},
	},
}

local function _append_jat_defect(tmpl, desc, variants, value_desc)
	local src = tmpl.src and tmpl.src .. ": " or ""

	local defect = copy_update(tmpl, {
		fn = make_jat_defect,
		name = src .. desc,
		tools = {},
		ekasui_code_list = {},
		desc = desc,
	})
	for _, variant in ipairs(variants) do
		local cur_tool = copy_update(variant.tool)
		table.insert(defect.tools, cur_tool)
		table.insert(defect.ekasui_code_list, variant.code)

		if value_desc then
			table.insert(cur_tool.options, {"JAT_VALUE", value_desc, {""}})
			cur_tool.static_options.JAT_VALUE_DESC=value_desc
		end
	end

	table.insert(DEFECTS, defect)
end


--дроссельные
local jat_rcc_tmpl = {guid = GUIDS.JAT_RAIL_CONN_CHOKE, group = "ЖАТ: Рельсовые соединители", src="Дроссельный"}

_append_jat_defect(jat_rcc_tmpl, "обрыв троса полн/частич", {
	{tool = JAT_TOOL.way,   code = "090004012111"},
	{tool = JAT_TOOL.joint, code = "090004012383"},
	{tool = JAT_TOOL.scb,   code = "090004003599"},
})
_append_jat_defect(jat_rcc_tmpl, "нет гаек на штепселе", {
	{tool = JAT_TOOL.way,   code = "090004012114"},
	{tool = JAT_TOOL.joint, code = "090004012386"},
	{tool = JAT_TOOL.scb,   code = "090004007699"},
}, "Количество гаек")
_append_jat_defect(jat_rcc_tmpl, "засыпана перемычка", {
	{tool = JAT_TOOL.scb,   code = "090004003597"},
})

--приварные
local jat_rcw_tmpl = {guid = GUIDS.JAT_RAIL_CONN_WELDED, group = "ЖАТ: Рельсовые соединители", src="Приварной"}

_append_jat_defect(jat_rcw_tmpl, "дефектный соединитель", {
	{tool = JAT_TOOL.way,   code = "090004000521"},
	{tool = JAT_TOOL.joint, code = "090004000995"},
})
_append_jat_defect(jat_rcw_tmpl, "отсутствует соединитель", {
	{tool = JAT_TOOL.way,   code = "090004004928"},
	{tool = JAT_TOOL.joint, code = "090004012367"},
	{tool = JAT_TOOL.scb,   code = "090004003583"},
})

--штепсельные
local jat_rcp_tmpl = {guid = GUIDS.JAT_RAIL_CONN_PLUG, group = "ЖАТ: Рельсовые соединители", src="Штепсельный"}

_append_jat_defect(jat_rcp_tmpl, "дефектный соединитель", {
	{tool = JAT_TOOL.way,   code = "090004000520"},
	{tool = JAT_TOOL.joint, code = "090004000994"},
})
_append_jat_defect(jat_rcp_tmpl, "засыпан соединитель", {
	{tool = JAT_TOOL.scb,   code = "090004003990"},
})
_append_jat_defect(jat_rcp_tmpl, "нет гаек", {
	{tool = JAT_TOOL.scb,   code = "090004003582"},
})
_append_jat_defect(jat_rcp_tmpl, "нет отверстий", {
	{tool = JAT_TOOL.way,   code = "090004004926"},
})
_append_jat_defect(jat_rcp_tmpl, "нет соединителя", {
	{tool = JAT_TOOL.way,   code = "090004004927"},
	{tool = JAT_TOOL.joint, code = "090004012371"},
	{tool = JAT_TOOL.scb,   code = "090004003581"},
})

-- САУТ
local jat_scb_abcs_tmpl = {guid = GUIDS.JAT_SCB_CRS_ABCS, group = "ЖАТ: Устройства СЦБ, КПС", src = "САУТ"}

_append_jat_defect(jat_scb_abcs_tmpl, "нарушена норма укладки перемычек", {
	{tool = JAT_TOOL.scb,   code = "090004004573"},
})
_append_jat_defect(jat_scb_abcs_tmpl, "нарушено расст. от 1-й точки до изостыка", {
	{tool = JAT_TOOL.scb,   code = "090004003767"},
})

-- УКСПС
local jat_scb_rscmd_tmpl = {guid = GUIDS.JAT_SCB_CRS_RSCMD, group = "ЖАТ: Устройства СЦБ, КПС"}

_append_jat_defect(jat_scb_rscmd_tmpl, "Плохое сост. планки УКСПС", {
	{tool = JAT_TOOL.scb,   code = "090004006853"},
})
_append_jat_defect(jat_scb_rscmd_tmpl, "Датчики УКСПС не по эпюре", {
	{tool = JAT_TOOL.scb,   code = "090004003777"},
})


return DEFECTS
