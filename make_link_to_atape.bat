set ATAPE_DIR="%ProgramFiles(x86)%\ATapeXP"

IF not exist %ATAPE_DIR% (
	set ATAPE_DIR="%ProgramFiles%\ATapeXP"
)

IF not exist %ATAPE_DIR% (
	echo "can not fined dst dir"
	exit 1
)

mklink /D /J %ATAPE_DIR%\Scripts Scripts