local types =
{

-- =========== MK ======================== --

	ISOSTYK					=	"{19253263-2C0B-41EE-8EAA-000000000010}",	 -- Изостык(МK)
	PSEUDOSTYK				=	"{19253263-2C0B-41EE-8EAA-000000000040}",	 -- Стык(МK)
	NAKLADKA				=	"{19253263-2C0B-41EE-8EAA-000000000080}",	 -- Накладка(МK)
	SVARKA					=	"{19253263-2C0B-41EE-8EAA-000000000100}",	 -- Cварка(МK)
	SVARKA_NST				=	"{19253263-2C0B-41EE-8EAA-000000000200}",	 -- Cварка н(МK)
	SVARKA_REG				=	"{19253263-2C0B-41EE-8EAA-000000000400}",	 -- Cварка.(МK)
	SVARKA_REG_NST			=	"{19253263-2C0B-41EE-8EAA-000000000800}",	 -- Cварка..(МK)

	DEF						=	"{19253263-2C0B-41EE-8EAA-000000001000}",	 -- Дефектоподобный

	NO_1					=	"{19253263-2C0B-41EE-8EAA-000000010000}",	 -- Поверхностный дефект(МK)
	NO_2					=	"{19253263-2C0B-41EE-8EAA-000000020000}",	 -- Неопознанный объект
	XX_000000040000			=	"{19253263-2C0B-41EE-8EAA-000000040000}",	 -- XX-000000040000

	STRELKA1				=	"{19253263-2C0B-41EE-8EAA-000000100000}",	 -- Стрелка пошерстно слева
	STRELKA2				=	"{19253263-2C0B-41EE-8EAA-000000200000}",	 -- Стрелка противошерстно налево
	STRELKA3				=	"{19253263-2C0B-41EE-8EAA-000000400000}",	 -- Стрелка пошерстно справа
	STRELKA4				=	"{19253263-2C0B-41EE-8EAA-000000800000}",	 -- Стрелка противошерстно направо

	OSTR					=	"{19253263-2C0B-41EE-8EAA-000010000000}",	 -- Остряк(МK)

	STRELKA1_2768			=	"{19253263-2C0B-41EE-8EAA-000100100000}",	 -- Стрелка 2768 пошерстно слева
	STRELKA2_2768			=	"{19253263-2C0B-41EE-8EAA-000100200000}",	 -- Стрелка 2768 противошерстно налево
	STRELKA3_2768			=	"{19253263-2C0B-41EE-8EAA-000100400000}",	 -- Стрелка 2768 пошерстно справа
	STRELKA4_2768			=	"{19253263-2C0B-41EE-8EAA-000100800000}",	 -- Стрелка 2768 противошерстно направо

	STRELKA1_2750			=	"{19253263-2C0B-41EE-8EAA-000200100000}",	 -- Стрелка 2750 пошерстно слева
	STRELKA2_2750			=	"{19253263-2C0B-41EE-8EAA-000200200000}",	 -- Стрелка 2750 противошерстно налево
	STRELKA3_2750			=	"{19253263-2C0B-41EE-8EAA-000200400000}",	 -- Стрелка 2750 пошерстно справа
	STRELKA4_2750			=	"{19253263-2C0B-41EE-8EAA-000200800000}",	 -- Стрелка 2750 противошерстно направо

	STRELKA1_2769			=	"{19253263-2C0B-41EE-8EAA-000300100000}",	 -- Стрелка 2769 пошерстно слева
	STRELKA2_2769			=	"{19253263-2C0B-41EE-8EAA-000300200000}",	 -- Стрелка 2769 противошерстно налево
	STRELKA3_2769			=	"{19253263-2C0B-41EE-8EAA-000300400000}",	 -- Стрелка 2769 пошерстно справа
	STRELKA4_2769			=	"{19253263-2C0B-41EE-8EAA-000300800000}",	 -- Стрелка 2769 противошерстно направо


	CHROM					=	"{19253263-2C0B-41EE-8EAA-000020000000}",	 -- Хромо-никелевая вставка

-- =========== MK ======================== -->
	MMK_10					=	"{19253263-2C0B-41EE-8EAD-000000000010}",	 -- MMK-Изостык
	MMK_40					=	"{19253263-2C0B-41EE-8EAD-000000000040}",	 -- MMK-Стык
	MMK_80					=	"{19253263-2C0B-41EE-8EAD-000000000080}",	 -- MMK-Накладка
	MMK_100					=	"{19253263-2C0B-41EE-8EAD-000000000100}",	 -- MMK-Cварка
	MMK_200					=	"{19253263-2C0B-41EE-8EAD-000000000200}",	 -- MMK-Cварка н
	MMK_400					=	"{19253263-2C0B-41EE-8EAD-000000000400}",	 -- MMK-Cварка.
	MMK_800					=	"{19253263-2C0B-41EE-8EAD-000000000800}",	 -- MMK-Cварка..

	XX_MMK_10000			=	"{19253263-2C0B-41EE-8EAD-000000010000}",	 -- MMK-10000??? -(ММK)
	XX_MMK_40000			=	"{19253263-2C0B-41EE-8EAD-000000040000}",	 -- MMK-000000040000

	MMK_000010000000		=	"{19253263-2C0B-41EE-8EAD-000010000000}",	 -- MMK_Остряк(ММK)

	MMK_000100100000		=	"{19253263-2C0B-41EE-8EAD-000100100000}",	 -- MMK-Стрелка 2768 пошерстно слева
	MMK_000100200000		=	"{19253263-2C0B-41EE-8EAD-000100200000}",	 -- MMK-Стрелка 2768 противошерстно налево
	MMK_000100400000		=	"{19253263-2C0B-41EE-8EAD-000100400000}",	 -- MMK-Стрелка 2768 пошерстно справа
	MMK_000100800000		=	"{19253263-2C0B-41EE-8EAD-000100800000}",	 -- MMK-Стрелка 2768 противошерстно направо

	MMK_000200100000		=	"{19253263-2C0B-41EE-8EAD-000200100000}",	 -- MMK-Стрелка 2750 пошерстно слева
	MMK_000200200000		=	"{19253263-2C0B-41EE-8EAD-000200200000}",	 -- MMK-Стрелка 2750 противошерстно налево
	MMK_000200400000		=	"{19253263-2C0B-41EE-8EAD-000200400000}",	 -- MMK-Стрелка 2750 пошерстно справа
	MMK_000200800000		=	"{19253263-2C0B-41EE-8EAD-000200800000}",	 -- MMK-Стрелка 2750 противошерстно направо

	MMK_CHROM				=	"{19253263-2C0B-41EE-8EAD-000020000000}",	 -- MMK-Хромо-никелевая вставка

-- ============= Atape ====================== --

--	MAG_SURF				=	"{0D2B4C26-6915-471A-8B1E-99E6C35841CB}",	 -- Поверх.(Магн.)

	Test					=	"{DC2B75B8-EEEA-403C-8C7C-012DBBCF23C5}",	 -- Тестовая отметка
	T1231					=	"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C5}",	 -- Отметка пользователя
	T1232					=	"{804DFA9E-035D-4170-B729-39DEDAB18B9D}",	 -- Конвертированная особая

	PRE_NPU					=	"{19FF08BB-C344-495B-82ED-10B6CBAD508F}",	 -- НПУ auto
	NPU						=	"{19FF08BB-C344-495B-82ED-10B6CBAD5090}",	 -- НПУ
	NPU2					=	"{19FF08BB-C344-495B-82ED-10B6CBAD5091}",	 -- НПУ БС

-- =========== VIDEO ======================== --

	RUN_RECOGNITIONS 		=	"{1D5095ED-AF51-43C2-AA13-6F6C86302FB0}",	-- "Запуски распознавания"

	UNSPC_OBJ				=	"{0860481C-8363-42DD-BBDE-8A2366EFAC90}",	 -- Ненормативный объект
	VID_INDT_1				=	"{CBD41D28-9308-4FEC-A330-35EAED9FC801}",	 -- Стык(Видео)
	VID_INDT_2				=	"{CBD41D28-9308-4FEC-A330-35EAED9FC802}",	 -- Стык(Видео)
	VID_INDT_3				=	"{CBD41D28-9308-4FEC-A330-35EAED9FC803}",	 -- СтыкЗазор(Пользователь)
	VID_INDT_ATS			=	"{CBD41D28-9308-4FEC-A330-35EAED9FC804}",	 -- АТСтык(Видео)
	VID_INDT_ATS_USER		=	"{CBD41D28-9308-4FEC-A330-35EAED9FC805}",	 -- АТСтык(Пользователь)
	VID_BEACON_INDT			=	"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",	 -- Маячная
	FASTENER				=	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",	 -- Скрепление
	VID_SURF				=	"{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}",	 -- Поверх.(Видео)
	VID_NF_JOINT			=	"{CC8B0BF6-719A-4252-8CA7-2991D226C4EF}",	 -- Нерасп. Стык
	VID_NF_ATS				=	"{FC2F2752-9383-45A4-8D0B-29851F3DD805}",	 -- Нерасп. АТСтык
	VID_NF_SURF				=	"{1F3BDFD2-112F-499A-9CD3-30DF28DDF6D3}",	 -- Нерасп. П.Деф.
	M_SPALA					=	"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}",	 -- Маячная(Пользователь)
	VID_CREWJOINT_MANUAL	=	"{28C82406-2773-48CB-8E7D-61089EEB86ED}",	 -- Болты(Пользователь)

	VID_ISO					=	"{64B5F99E-75C8-4386-B191-98AD2D1EEB1A}",	 -- ИзоСтык(Видео)

	SLEEPER					=	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",	 -- Шпалы
	SLEEPER_DEFECT			=	"{1DEFC4BD-FDBB-4AC7-9008-BEEB56048131}",	 -- Дефекты шпал
	SLEEPER_TOP				=	"{53987511-8176-470D-BE43-A39C1B6D12A3}",	 -- Шпалы(сверху)


	VID_BEACON_FIRTREE_MARK	=	"{D3736670-0C32-46F8-9AAF-3816DE00B755}",	 -- Маячная Ёлка

	FASTENER_USER			=	"{3601038C-A561-46BB-8B0F-F896C2130001}",	 -- Скрепления(Пользователь)
	SLEEPER_USER			=	"{3601038C-A561-46BB-8B0F-F896C2130002}",	 -- Шпалы(Пользователь)
	RAIL_JOINT_USER			=	"{3601038C-A561-46BB-8B0F-F896C2130003}",	 -- Рельсовые стыки(Пользователь)
	RAIL_DEFECTS_USER		=	"{3601038C-A561-46BB-8B0F-F896C2130004}",	 -- Дефекты рельсов(Пользователь)
	BALLAST_USER			=	"{3601038C-A561-46BB-8B0F-F896C2130005}",	 -- Балласт(Пользователь)
	USER_JOINTLESS_DEFECT	=	"{3601038C-A561-46BB-8B0F-F896C2130006}",	 -- Бесстыковой путь(Пользователь)

		-- групповые отметки  --

	GROUP_GAP_AUTO			=	"{B6BAB49E-4CEC-4401-A106-355BFB2E0001}",	 -- Групповые дефекты нулевых зазоров (Авто)
	GROUP_GAP_USER			=	"{B6BAB49E-4CEC-4401-A106-355BFB2E0002}",	 -- Групповые дефекты нулевых зазоров(Пользователь)
	GROUP_SPR_AUTO			=	"{B6BAB49E-4CEC-4401-A106-355BFB2E0011}",	 -- Групповые дефекты шпал (Авто)
	GROUP_SPR_USER			=	"{B6BAB49E-4CEC-4401-A106-355BFB2E0012}",	 -- Групповые дефекты шпал (Пользователь)
	GROUP_FSTR_AUTO			=	"{B6BAB49E-4CEC-4401-A106-355BFB2E0021}",	 -- Групповые дефекты скреплений (Авто)
	GROUP_FSTR_USER			=	"{B6BAB49E-4CEC-4401-A106-355BFB2E0022}",	 -- Групповые дефекты скреплений (Пользователь)

	-- ЖАТ --

	JAT_RAIL_CONN_CHOKE		= 	"{46DB5861-E172-49A7-B877-A9CA11700101}",	-- ЖАТ: Рельсовые соединители: дроссельные
	JAT_RAIL_CONN_WELDED	= 	"{46DB5861-E172-49A7-B877-A9CA11700102}",	-- ЖАТ: Рельсовые соединители: приварные
	JAT_RAIL_CONN_PLUG		= 	"{46DB5861-E172-49A7-B877-A9CA11700103}",	-- ЖАТ: Рельсовые соединители: штепсельные
	JAT_SCB_CRS_ABCS		= 	"{46DB5861-E172-49A7-B877-A9CA11700201}",	-- ЖАТ: Устройства СЦБ, КПС: САУТ
	JAT_SCB_CRS_RSCMD		= 	"{46DB5861-E172-49A7-B877-A9CA11700202}",	-- ЖАТ: Устройства СЦБ, КПС: УКСПС

	TURNOUT					=	"{EE2FD277-0776-429F-87C4-F435B9A6F760}", 	-- стрелка
	CABLE_CONNECTOR 		=	"{2DD3CE7E-5F38-4118-A795-D55B0E10653A}",	-- Тросовая (бутлежная) перемычка

-- =========== VIDEO_HUN ======================== -->

	SQUAT					=	"{DE548D8F-4E0C-4644-8DB3-B28AE8B17431}",	 -- UIC_227
	BELGROSPI				=	"{BB144C42-8D1A-4FE1-9E84-E37E0A47B074}",	 -- BELGROSPI
	SLEEPAGE_SKID_1			=	"{EBAB47A8-0CDC-4102-B21F-B4A90F9D873A}",	 -- UIC_2251
	SLEEPAGE_SKID_2			=	"{54188BA4-E88A-4B6E-956F-29E8035684E9}",	 -- UIC_2252
	HC						=	"{7EF92845-226D-4D07-AC50-F23DD8D53A19}",	 -- HC

	SQUAT_USER				=	"{13A7906C-BBFB-4EB3-86FA-FA74B77F5F35}",	 -- UIC_227(User)
	BELGROSPI_USER			=	"{981F7780-500C-47CD-978A-B9F3A91C37FE}",	 -- BELGROSPI(User)
	SLEEPAGE_SKID_1_USER	=	"{41486CAC-EBE9-46FF-ACCA-041AFAFFC531}",	 -- UIC_2251(User)
	SLEEPAGE_SKID_2_USER	=	"{3401C5E7-7E98-4B4F-A364-701C959AFE99}",	 -- UIC_2252(User)
	HC_USER					=	"{515FA798-3893-41CA-B4C3-6E1FEAC8E12F}",	 -- HC(User)

-- ============== UZK ===================== -->

	MOVE_BACKWARD1			=	"{D4607B05-17C2-4c30-A303-69005A08C000}",	 -- Зона движения назад
	MOVE_BACKWARD2			=	"{D4607B05-17C2-4c30-A303-69005A08C001}",	 -- Зона движения назад

-- ============== UZK for HUN ===================== --

    OTMETKA_01				=	"{29FF08BB-C344-495B-82ED-000000000001}",	 -- Возм.места дефект
	OTMETKA_02				=	"{29FF08BB-C344-495B-82ED-000000000002}",	 -- Пачка сигналов

-- ============== UZK for HUN ===================== --

	OTMETKA_03				=	"{29FF08BB-C344-495B-82ED-000000000003}",	 -- Участок, не подл.анализу
	OTMETKA_05				=	"{29FF08BB-C344-495B-82ED-000000000005}",	 -- Одиночное отверстие
	OTMETKA_06				=	"{29FF08BB-C344-495B-82ED-000000000006}",	 -- Констр.отраж. в зоне од.отверстий
	OTMETKA_07				=	"{29FF08BB-C344-495B-82ED-000000000007}",	 -- Паразит.пачка в зоне од.отверстий
	OTMETKA_08				=	"{29FF08BB-C344-495B-82ED-000000000008}",	 -- Дефектоподобн.пачка в од.отверстий
	OTMETKA_09				=	"{29FF08BB-C344-495B-82ED-000000000009}",	 -- Болтовой стык
	OTMETKA_10				=	"{29FF08BB-C344-495B-82ED-00000000000A}",	 -- Отраж. от отв. в зоне болт.стыка
	OTMETKA_33				=	"{29FF08BB-C344-495B-82ED-000000000021}",	 -- Отраж. от торца в зоне болт.стыка
	OTMETKA_34				=	"{29FF08BB-C344-495B-82ED-000000000022}",	 -- Отраж. от уголка в зоне болт.стыка
	OTMETKA_11				=	"{29FF08BB-C344-495B-82ED-00000000000B}",	 -- Паразит.пачка в зоне болт.стыка
	OTMETKA_12				=	"{29FF08BB-C344-495B-82ED-00000000000C}",	 -- Дефектоподобн.пачка в зоне болт.стыка
	OTMETKA_13				=	"{29FF08BB-C344-495B-82ED-00000000000D}",	 -- Стрелочный перевод
	OTMETKA_14				=	"{29FF08BB-C344-495B-82ED-00000000000E}",	 -- Алюминотерм.сварной стык
	OTMETKA_15				=	"{29FF08BB-C344-495B-82ED-00000000000F}",	 -- Участки чистого рельса
	OTMETKA_16				=	"{29FF08BB-C344-495B-82ED-000000000010}",	 -- Дефектоподобн.пачка в Ч/Р
	OTMETKA_17				=	"{29FF08BB-C344-495B-82ED-000000000011}",	 -- Зона отс.дон.сигнала в Ч/Р
	OTMETKA_18				=	"{29FF08BB-C344-495B-82ED-000000000012}",	 -- Бездеф. участок в Ч/Р
	OTMETKA_20				=	"{29FF08BB-C344-495B-82ED-000000000014}",	 -- Сигналы от верх.выкружки
	OTMETKA_21				=	"{29FF08BB-C344-495B-82ED-000000000015}",	 -- Сигналы от подг.грани
	OTMETKA_22				=	"{29FF08BB-C344-495B-82ED-000000000016}",	 -- Unknow-22
	OTMETKA_23				=	"{29FF08BB-C344-495B-82ED-000000000017}",	 -- Зоны ударов
	OTMETKA_24				=	"{29FF08BB-C344-495B-82ED-000000000018}",	 -- Пачки/значимые участки
	OTMETKA_25				=	"{29FF08BB-C344-495B-82ED-000000000019}",	 -- Сигналы от перехода головки в шейку
	OTMETKA_26				=	"{29FF08BB-C344-495B-82ED-00000000001A}",	 -- Реверберационные сигналы в ближней зоне
	OTMETKA_27				=	"{29FF08BB-C344-495B-82ED-00000000001B}",	 -- Поверхностные волны в каналах 70
	OTMETKA_28				=	"{29FF08BB-C344-495B-82ED-00000000001C}",	 -- Электроконтактная сварка
	OTMETKA_29				=	"{29FF08BB-C344-495B-82ED-00000000001D}",	 -- Электрические наводки
	OTMETKA_30				=	"{29FF08BB-C344-495B-82ED-00000000001E}",	 -- Смещения искательной системы
	OTMETKA_32				=	"{29FF08BB-C344-495B-82ED-000000000020}",	 -- Сигналы от подошвы
	OTMETKA_44				=	"{29FF08BB-C344-495B-82ED-00000000002C}",	 -- Непроконтролированное отверстие

-- ============== UZK ===================== --
}

return types
