@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat" >nul 2>&1
"C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe" ReadEOD.dproj /p:Config=Debug /p:Platform=Win32 /v:m /nologo
