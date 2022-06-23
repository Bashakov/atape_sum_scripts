local TYPES = require 'sum_types'

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

return
{
	NPU_guids = NPU_guids,
	recognition_guids = recognition_guids,
	recognition_surface_defects = recognition_surface_defects,
	recognition_uic_surface_defects = recognition_uic_surface_defects,
}
