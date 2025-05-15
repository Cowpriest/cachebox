@echo off
setlocal enabledelayedexpansion

:: sync_all.bat <uploaderUid> <uploaderName> <serverBase>

if "%~1"=="" (
  echo Usage: %~nx0 uploaderUid uploaderName serverBase
  goto :eof
)
:: strip quotes from args
set "UPLOADER_UID=%~1"
set "UPLOADER_NAME=%~2"
set "SERVER_BASE=%~3"

:: apply defaults if empty
if "%UPLOADER_NAME%"=="" set "UPLOADER_NAME=Admin"
if "%SERVER_BASE%"=="" set "SERVER_BASE=http://localhost:3000"

echo Uploader UID:    %UPLOADER_UID%
echo Uploader Name:   %UPLOADER_NAME%
echo Server Base URL: %SERVER_BASE%
echo.

:: loop each group folder under uploads\
for /D %%G in ("%~dp0uploads\*") do (
  set "GROUP_ID=%%~nxG"
  set "LOCAL_DIR=%%~fG"

  echo 🔄 Syncing group !GROUP_ID!…
  node "%~dp0sync_upload.js" ^
    "!GROUP_ID!" ^
    "!LOCAL_DIR!" ^
    "%UPLOADER_UID%" ^
    "%UPLOADER_NAME%" ^
    "%SERVER_BASE%"
  echo.
)

echo 🎉 All done!
endlocal
pause
