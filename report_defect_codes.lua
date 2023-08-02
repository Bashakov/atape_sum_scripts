local codes = {

	-- 1.1 Определение и вычисление размеров поверхностных дефектов рельсов, седловин, в том числе в местах сварки, пробуксовок (длина, ширина и площадь).
	RAIL_DEFECT_BASE 			=	{ "090004012002", "Дефект/повреждение подошвы рельса"},
	RAIL_BREAK 					=	{ "090004012004", "Излом рельса"},
	RAIL_SURF_DEFECT 			= 	{ "090004012001",  "Поверхностный дефект рельса"},
	RAIL_DEFECT_HEAD 			=	{ "090004012008", "Поперечная трещина/излом головки рельса"},



	-- 1.2 Ширина стыкового зазора, мм
	JOINT_EXCEED_GAP_WIDTH		=	{ "090004012062", "Превышение конструктивной величины стыкового зазора"},
	--[[ https://bt.abisoft.spb.ru/view.php?id=722#c3398
		https://bt.abisoft.spb.ru/view.php?id=765
		1. новый прикол дефект 090004012062 разнесен по 2 ниткам.
		Превышение конструктивной ширины зазора левой нити(90004016149) и правой нити(90004016150).	]]
	JOINT_EXCEED_GAP_WIDTH_LEFT		=	{ "90004016149", "Превышение конструктивной величины стыкового зазора левой нити"},
	JOINT_EXCEED_GAP_WIDTH_RIGHT	=	{ "90004016150", "Превышение конструктивной величины стыкового зазора правой нити"},

	-- 1.3 Определение двух подряд и более нулевых зазоров
	JOINT_NEIGHBO_BLIND_GAP		=	{ "090004015840", "Нулевой зазор"},
	-- https://bt.abisoft.spb.ru/view.php?id=765
	JOINT_NEIGHBO_BLIND_GAP_TWO		=	{ "090004012061", "Слепой зазор: два подряд"},
	JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT	=	{ "090004015838", "Слепой зазор: три и более подряд: левая нить"},
	JOINT_NEIGHBO_BLIND_GAP_MORE_RIGHT	=	{ "090004015839", "Слепой зазор: три и более подряд: правая нить"},


	-- 1.4 Горизонтальные ступеньки в стыках, мм
	-- -- https://bt.abisoft.spb.ru/view.php?id=765 2 новых кода взамен старого: "В/Г ступенька: t >= 25град."	"090004000334", "В/Г ступенька: t < 25град."	"090004000338"
	JOINT_VER_STEP 				=	{ "090004012058", "Вертикальная ступенька в стыке"}, --!!! код удален из классификатора
	JOINT_HOR_STEP				=	{ "090004012059", "Горизонтальная ступенька в стыке"}, --!!! код удален из классификатора

	JOINT_STEP_VH_GE25 			=	{ "090004000334", "В/Г ступенька: t >= 25град."},
	JOINT_STEP_VH_LT25			=	{ "090004000338", "В/Г ступенька: t < 25град."},

	-- 1.5 Определение наличия и состояния (надрыв, трещина, излом) накладок	Закрытие движения при изломе накладки.
	JOINT_FISHPLATE_DEFECT 		= 	{ "090004000474", "Надрыв/дефект стыковой накладки"},
	JOINT_FISHPLATE_MISSING		= 	{ "090004000477", "Отсутствует стыковая накладка"},
	-- https://bt.abisoft.spb.ru/view.php?id=765  2 новых кода дополнительно: "Излом одной  накладки в стыке"	"090004000475", "Излом 2-х накладок в стыке"	"090004000476"
	JOINT_FISHPLATE_DEFECT_SINGLE 	= 	{ "090004000475", "Излом одной  накладки в стыке"},
	JOINT_FISHPLATE_DEFECT_BOTH		= 	{ "090004000476", "Излом 2-х накладок в стыке"},

	-- 1.6 Определение наличия и состояния (ослаблен, раскручен, не типовой) стыковых болтов
	JOINT_MISSING_BOLT			=	{ "090004000465", "Отсутствие стыкового болта"},
	-- https://bt.abisoft.spb.ru/view.php?id=765 3 новых кода взамен старого
	JOINT_MISSING_BOLT_TWO_GOOD		=	{ "090004000466", "Отсутствие болтов: ХОО-ООО"},
	JOINT_MISSING_BOLT_NO_GOOD		=	{ "090004000467", "Отсутствие болтов: ХХ-ОО, ХХХ-ООО"},
	JOINT_MISSING_BOLT_ONE_GOOD		=	{ "090004000471", "Отсутствие болтов: ХО-ОО, ХХО-ООО"},

	-- 1.7 Определение наличия и состояния рельсовых соединителей
	JOINT_WELDED_BOND_FAULT   		=	{ "090004000521", "Дефектный соединитель"}, -- https://bt.abisoft.spb.ru/view.php?id=765#c3706

	-- 1.9 Определение параметров и состояния рельсовых скреплений (наличие визуально фиксируемых ослабленных скреплений, сломанных подкладок, отсутствие болтов, негодные прокладки, закладные и клеммные болты, шурупы, клеммы, анкеры)
--	FASTENER_ = 	{ "090004000457", "Выход подошвы рельса из реборд подкладок"},
--	FASTENER_ = 	{ "090004000389", "Дефектные клеммы"},
--	FASTENER_ = 	{ "090004000402", "Дефектные подкладки"},
--	FASTENER_ = 	{ "090004000400", "Наддернутые костыли"},
--	FASTENER_ = 	{ "090004000384", "Отсутствие гаек на закладных болтах"},
--	FASTENER_ = 	{ "090004000395", "Отсутствие гаек на клеммных болтах"},
--	FASTENER_ = 	{ "090004000409", "Отсутствие или повреждение подрельсовой резины"},
--	FASTENER_ = 	{ "090004003539", "Отсутствует скрепление"},
	FASTENER_MISSING_CLAMP = 		{ "090004003539", "Отсутствует скрепление"}, --!!! для скрепления АРС отсутствие клеммы меняем на "Отсутствует скрепление" 090004003539, для скрепления КБ
	FASTENER_MISSING_BOLT = 		{ "090004000394", "Отсутствует закладной болт"}, --!!! заменен на альтернативный
	FASTENER_MISSING_CLAMP_BOLT = 	{ "090004000394", "Отсутствует клеммный болт"}, --!!! заменен на альтернативный
--	FASTENER_ = 	{ "090004000401", "Отсутствуют костыли"},
--	FASTENER_ = 	{ "090004000405", "Отсутствуют подкладки"},
--	FASTENER_ = 	{ "090004000401", "Отсутствующие или изломанные костыли"},
--	FASTENER_ = 	{ "090004000478", "Отсутствующие или изломанные шурупы"},

	-- https://bt.abisoft.spb.ru/view.php?id=925

	FASTENER_DEFECT_CURVE_GROUP_6 		= { "090004017095", "Отсутствует или дефектное скрепление в кривых радиусом 650 м и менее более чем на 5 шпалах подряд по одной нити"},
	FASTENER_DEFECT_CURVE_GROUP_4 		= { "090004017096", "Отсутствует или дефектное скрепление в кривых радиусом 650 м и менее на 4-х шпалах подряд по одной нити"},
	FASTENER_DEFECT_CURVE_GROUP_5 		= { "090004017097", "Отсутствует или дефектное скрепление в кривых радиусом 650 м и менее на 5 шпалах подряд по одной нити"},

	FASTENER_DEFECT_STRAIGHT_GROUP_7 	= { "090004017098", "Отсутствует или дефектное скрепление в прямых и кривых радиусом более 650 м более чем на 6 шпалах подряд по одной нити"},
	FASTENER_DEFECT_STRAIGHT_GROUP_4 	= { "090004017099", "Отсутствует или дефектное скрепление в прямых и кривых радиусом более 650 м на 4-х шпалах подряд по одной нити"},
	FASTENER_DEFECT_STRAIGHT_GROUP_5 	= { "090004017100", "Отсутствует или дефектное скрепление в прямых и кривых радиусом более 650 м на 5 шпалах подряд по одной нити"},
	FASTENER_DEFECT_STRAIGHT_GROUP_6 	= { "090004017101", "Отсутствует или дефектное скрепление в прямых и кривых радиусом более 650 м на 6 шпалах подряд по одной нити"},

	FASTENER_DEFECT_UNLINED_GROUP_3 	= { "090004017102", "Отсутствует или дефектное скрепление на бесподкладочных скреплениях на 3-х шпалах подряд по одной нити"},
	FASTENER_DEFECT_UNLINED_GROUP_4 	= { "090004017103", "Отсутствует или дефектное скрепление на бесподкладочных скреплениях на 4-х шпалах подряд по одной нити"},
	FASTENER_DEFECT_UNLINED_GROUP_5 	= { "090004017104", "Отсутствует или дефектное скрепление на бесподкладочных скреплениях на 5 и более шпалах подряд по одной нити"},

	FASTENER_DEFECT_SWITCH_GROUP_2	 	= { "090004017105", "Отсутствует или дефектное скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити на 2-х брусьях подряд"},
	FASTENER_DEFECT_SWITCH_GROUP_3 		= { "090004017106", "Отсутствует или дефектное скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити на 3-х брусьях подряд"},
	FASTENER_DEFECT_SWITCH_GROUP_4 		= { "090004017107", "Отсутствует или дефектное скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити на 4-х брусьях подряд"},
	FASTENER_DEFECT_SWITCH_GROUP_5 		= { "090004017108", "Отсутствует или дефектное скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити на 5 и более брусьях подряд "},


	-- 2021.02.18 Классфикатор ред для ATape.xlsx
	SLEEPER_FRACTURE_FERROCONCRETE ={ "090004000374", "Негодная железобетонная шпала"}, --!!! заменен код
	SLEEPER_CHIP_FERROCONCRETE 	= 	{ "090004015005", "Дефектная железобетонная шпала"},
	SLEEPER_CRACK_WOOD			= 	{ "090004015004", "Дефектная деревянная шпала"},
	SLEEPER_ROTTENNESS_WOOD 	= 	{ "090004000369", "Негодная деревянная шпала"},

	-- 1.10 Отслеживание соблюдения эпюры шпал
	SLEEPER_DISTANCE_WOODEN   	=	{ "090004000370", "Нарушение эпюры: ДШ"}, --!!! изменено название
	SLEEPER_DISTANCE_CONCRETE 	=	{ "090004000375", "Нарушение эпюры: ЖБШ"},  --!!! изменено название

	-- 1.11		Перпендикулярность шпалы относительно оси пути, рад
	-- https://bt.abisoft.spb.ru/view.php?id=765 2 новых кода взамен старого 090004000999
	SLEEPER_ANGLE_WOOD         	=	{ "090004012308", "Разворот ДШ"},
	SLEEPER_ANGLE_CONCRETE    	=	{ "090004000373", "Разворот ЖБШ"},

	-- https://bt.abisoft.spb.ru/view.php?id=925
	-- Стык
	SLEEPER_GROUP_JOINT_WOOD        	=	{ "090004017134", "Два подряд и более негодных деревянных шпал (брусьев) в стыке для путей 1-3 классов"},
	SLEEPER_GROUP_JOINT_CONCRETE       	=	{ "090004017124", "Два подряд и более негодных железобетонных шпал (брусьев) в стыке для путей 1-3 классов"},
	-- Прямая дерево
	SLEEPER_GROUP_STRAIGHT_WOOD_4       =	{ "090004000349", "«Куст» из 4-х негодных деревянных шпал (брусьев) при рельсах Р65, Р75 (прямая или кривая радиусом 650м и более)"},
	SLEEPER_GROUP_STRAIGHT_WOOD_5       =	{ "090004000351", "«Куст» из 5-ти негодных деревянных шпал (брусьев) при рельсах Р65, Р75 (прямая или кривая радиусом 650м и более)"},
	SLEEPER_GROUP_STRAIGHT_WOOD_6       =	{ "090004000352", "«Куст» из 6-ти негодных деревянных шпал (брусьев) и более при рельсах Р65, Р75 (прямая или кривая радиусом 650м и более)"},
	-- Прямая ЖБ
	SLEEPER_GROUP_STRAIGHT_CONCRETE_4   =	{ "090004017126", "«Куст» из 4-х негодных железобетонных шпал при рельсах Р65, Р75 (прямая или кривая радиусом 650м и более)"},
	SLEEPER_GROUP_STRAIGHT_CONCRETE_5   =	{ "090004017129", "«Куст» из 5-ти негодных железобетонных шпал при рельсах Р65, Р75 (прямая или кривая радиусом 650м и более)"},
	SLEEPER_GROUP_STRAIGHT_CONCRETE_6   =	{ "090004017130", "«Куст» из 6-ти  негодных железобетонных шпал и более при рельсах Р65, Р75 (прямая или кривая радиусом 650м и более)"},
	-- Кривая
	SLEEPER_GROUP_CURVE_WOOD_4        	=	{ "090004000354", "«Куст» из 4-х негодных деревянных шпал (брусьев) при рельсах Р65, Р75 (кривая радиусом менее 650м)"},
	SLEEPER_GROUP_CURVE_CONCRETE_4      =	{ "090004017125", "«Куст» из 4-х негодных железобетонных шпал при рельсах Р65, Р75 (кривая радиусом менее 650м)"},
	SLEEPER_GROUP_CURVE_WOOD_5        	=	{ "090004000356", "«Куст» из 5-ти негодных деревянных шпал (брусьев) и более при рельсах Р65, Р75 (кривая радиусом менее 650м)"},
	SLEEPER_GROUP_CURVE_CONCRETE_5      =	{ "090004017127", "«Куст» из 5-ти негодных железобетонных шпал и более при рельсах Р65, Р75 (кривая радиусом менее 650м)"},


	-- 1.12 Бесстыковой путь МАЯЧНЫЕ ОТМЕТКИ
	-- https://bt.abisoft.spb.ru/view.php?id=765 3 новых кода взамен старого:
	BEACON_UBNORMAL_MOVED_LE_5  =   { "090004015469", "Угон плети до 5мм включительно"},
	BEACON_UBNORMAL_MOVED_LE_10 =   { "090004015470", "Угон плети более 5 до 10мм"},
	BEACON_UBNORMAL_MOVED_GT_10 =   { "090004015508", "Угон плети более 10мм"},
	BEACON_MISSING_LINE  		=   { "090004015367", "Отсутствует маркировка «маячных» шпал"},
}

local _code2desc_tbl = {}

for _, value in pairs(codes) do
	if type(value) == 'table' and #value == 2 then
		_code2desc_tbl[value[1]] = value[2]
	end
end

codes.code2desc = function (code)
	return _code2desc_tbl[code]
end

return codes
