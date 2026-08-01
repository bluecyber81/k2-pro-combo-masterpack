@echo off
setlocal EnableExtensions

set "ESTIMATOR=%~dp0klipper_estimator-k2pro.exe"
set "HYBRID=%~dp0K2Pro-Hybrid-Time.ps1"
set "CALIBRATION=%~dp0K2Pro-Time-Calibration.json"
set "MOONRAKER_URL=http://192.168.178.74:7125"
set "MOONRAKER_CACHE=%~dp0k2pro_moonraker_cache.json"

if "%~1"=="" (
  echo K2 Pro Estimator: no G-code file was supplied.
  exit /b 2
)

if not exist "%~1" (
  echo K2 Pro Estimator: file not found: %~1
  exit /b 3
)

if not exist "%ESTIMATOR%" (
  echo K2 Pro Estimator: executable not found: %ESTIMATOR%
  exit /b 4
)

if not exist "%MOONRAKER_CACHE%" (
  echo K2 Pro Estimator: fallback config not found: %MOONRAKER_CACHE%
  exit /b 5
)

if not exist "%HYBRID%" (
  echo K2 Pro Estimator: hybrid post-processor not found: %HYBRID%
  exit /b 6
)

if not exist "%CALIBRATION%" (
  echo K2 Pro Estimator: calibration file not found: %CALIBRATION%
  exit /b 7
)

findstr /C:"K2PRO_HYBRID_TIME" "%~1" >nul 2>&1
if not errorlevel 1 (
  echo K2 Pro Estimator: file already has a hybrid estimate; leaving it unchanged.
  exit /b 0
)

findstr /C:"Processed by klipper_estimator" "%~1" >nul 2>&1
if not errorlevel 1 (
  echo K2 Pro Estimator: estimator-only file has no recoverable Creality CFS timeline.
  echo Re-slice the model or use the original G-code backup before processing it again.
  exit /b 8
)

set "ORIGINAL_COPY=%TEMP%\k2pro-estimator-%RANDOM%-%RANDOM%.gcode"
copy /b "%~1" "%ORIGINAL_COPY%" >nul
if errorlevel 1 (
  echo K2 Pro Estimator: could not create the temporary original copy.
  exit /b 9
)

"%ESTIMATOR%" --config_moonraker_url "%MOONRAKER_URL%" --config_moonraker_cache_file "%MOONRAKER_CACHE%" --config_moonraker_ignore_error -c "mm_per_arc_segment=0.9" post-process "%~1"
set "RESULT=%ERRORLEVEL%"

if not "%RESULT%"=="0" (
  echo K2 Pro Estimator failed with exit code %RESULT%.
  copy /b "%ORIGINAL_COPY%" "%~1" >nul
  del /q "%ORIGINAL_COPY%" >nul 2>&1
  exit /b %RESULT%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HYBRID%" -Original "%ORIGINAL_COPY%" -Estimated "%~1" -Calibration "%CALIBRATION%" -Output "%~1"
set "RESULT=%ERRORLEVEL%"

if not "%RESULT%"=="0" (
  echo K2 Pro Estimator: hybrid calibration failed with exit code %RESULT%; restoring the original file.
  copy /b "%ORIGINAL_COPY%" "%~1" >nul
  del /q "%ORIGINAL_COPY%" >nul 2>&1
  exit /b %RESULT%
)

del /q "%ORIGINAL_COPY%" >nul 2>&1
exit /b 0
