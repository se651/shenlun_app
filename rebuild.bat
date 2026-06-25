@echo off
cd /d %~dp0
set JAVA_HOME=C:\jdk17_real
D:\flutter\bin\flutter.bat build apk --debug
echo EXIT=%ERRORLEVEL%
