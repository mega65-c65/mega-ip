@echo off
rem Run the unit tests (they run on a Python MEGA65 simulator; no Xemu needed).
rem
rem   test.bat            simulator self-tests, then the mega-ip tests
rem   test.bat coverage   mega-ip tests with an instruction coverage report
rem                       (written to target\coverage.txt)
rem   test.bat mutate     mutation testing; slow, extra arguments go to
rem                       tests\mutate.py (e.g. test.bat mutate --sample 50)
rem
rem Exits with errorlevel 1 if any test fails.
setlocal
cd /d "%~dp0"

if /i "%~1"=="coverage" goto coverage
if /i "%~1"=="mutate" goto mutate

echo Running simulator self-tests...
python -m unittest discover -s tools\sim\tests
if errorlevel 1 goto failed
echo Running mega-ip unit tests...
python -m unittest discover -s tests
if errorlevel 1 goto failed
echo.
echo All tests passed.
exit /b 0

:coverage
shift
python tests\coverage.py %1 %2 %3 %4 %5 %6 %7 %8 %9
exit /b %errorlevel%

:mutate
shift
python tests\mutate.py %1 %2 %3 %4 %5 %6 %7 %8 %9
exit /b %errorlevel%

:failed
echo.
echo *** Tests failed. ***
exit /b 1
