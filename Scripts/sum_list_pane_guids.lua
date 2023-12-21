local TYPES = require 'sum_types'

local function array_concat(...)
	local res = {}
	for _, t in ipairs{...} do
		for _, v in ipairs(t) do table.insert(res, v) end
	end
	return res
end

NPU_guids = {
	TYPES.PRE_NPU, -- НПУ auto
	TYPES.NPU, -- НПУ
	TYPES.NPU2, -- НПУ БС
}

recognition_guids = {
	TYPES.VID_INDT_1,
	TYPES.VID_INDT_2,
	TYPES.VID_INDT_3,
	TYPES.VID_INDT_ATS,
	TYPES.VID_ISO, -- ИзоСтык(Видео)
}

recognition_surface_defects = {
	TYPES.VID_SURF,
}

recognition_uic_surface_defects = {
	TYPES.SQUAT,
	TYPES.BELGROSPI,
	TYPES.SLEEPAGE_SKID_1,
	TYPES.SLEEPAGE_SKID_2,
	TYPES.HC,

	TYPES.SQUAT_USER,
	TYPES.BELGROSPI_USER,
	TYPES.SLEEPAGE_SKID_1_USER,
	TYPES.SLEEPAGE_SKID_2_USER,
	TYPES.HC_USER,
}

group_defects =
{
	TYPES.GROUP_GAP_AUTO,
	TYPES.GROUP_GAP_USER,
	TYPES.GROUP_SPR_AUTO,
	TYPES.GROUP_SPR_USER,
	TYPES.GROUP_FSTR_AUTO,
	TYPES.GROUP_FSTR_USER,
}

local JAT_CONN = {
	TYPES.JAT_RAIL_CONN_CHOKE,
	TYPES.JAT_RAIL_CONN_WELDED,
	TYPES.JAT_RAIL_CONN_PLUG,
}

local JAT_SCB = {
	TYPES.JAT_SCB_CRS_ABCS,
	TYPES.JAT_SCB_CRS_RSCMD,
}

local JAT = array_concat(JAT_CONN, JAT_SCB)


return
{
	NPU_guids = NPU_guids,
	recognition_guids = recognition_guids,
	recognition_surface_defects = recognition_surface_defects,
	recognition_uic_surface_defects = recognition_uic_surface_defects,
	group_defects = group_defects,
	JAT_CONN = JAT_CONN,
	JAT_SCB = JAT_SCB,
	JAT = JAT,
}
