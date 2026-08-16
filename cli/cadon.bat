@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0new-addon.ps1" -ProjectName "%~1"