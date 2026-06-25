@echo off
cd /d %~dp0
D:\flutter\bin\flutter.bat clean
D:\flutter\bin\flutter.bat build apk --debug
echo EXIT_CODE=%ERRORLEVEL%
