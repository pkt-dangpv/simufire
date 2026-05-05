@echo off
setlocal
pushd "%~dp0"

call "C:\Program Files\firemodels\FDS6\bin\fdsinit.bat"
"C:\Program Files\firemodels\FDS6\bin\fds_openmp.exe" simufire_simple_house_default.fds
set "FDS_EXIT_CODE=%ERRORLEVEL%"

if not "%FDS_EXIT_CODE%"=="0" (
    echo FDS failed with exit code %FDS_EXIT_CODE%.
    popd
    exit /b %FDS_EXIT_CODE%
)

if exist "C:\Program Files\firemodels\FDS6\bin\smokeview.exe" (
    "C:\Program Files\firemodels\FDS6\bin\smokeview.exe" simufire_simple_house_default.smv
) else if exist "C:\Program Files\firemodels\SMV6\smokeview.exe" (
    "C:\Program Files\firemodels\SMV6\smokeview.exe" simufire_simple_house_default.smv
) else (
    echo Smokeview was not found. Open simufire_simple_house_default.smv manually with Smokeview.
)

popd
endlocal
