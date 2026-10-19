@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title NikaView - Publicar en GitHub

echo ================================================
echo        NIKAVIEW - REPOSITORIO PUBLICO
echo ================================================
echo.
echo Este proceso hara PUBLICO el codigo de esta carpeta.
echo Verifica que NO haya fotos, claves o archivos privados.
echo.
if not exist "SolidSecViewer.xcodeproj\project.pbxproj" goto :invalid
where git >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Instala Git for Windows primero.
  goto :error
)
where gh >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Instala GitHub CLI ^(gh^) primero.
  goto :error
)

gh auth status >nul 2>&1
if errorlevel 1 (
  gh auth login
  if errorlevel 1 goto :error
)

for /f "usebackq delims=" %%A in (`gh api user --jq .login`) do set "GH_LOGIN=%%A"
for /f "usebackq delims=" %%A in (`gh api user --jq .id`) do set "GH_ID=%%A"
if not defined GH_LOGIN goto :error
if not defined GH_ID goto :error

set "REPO_FULL=!GH_LOGIN!/NikaView"
gh repo view "!REPO_FULL!" >nul 2>&1
if not errorlevel 1 (
  echo [AVISO] Ya existe !REPO_FULL!.
  echo No voy a modificarlo ni reemplazar archivos automaticamente.
  echo Comparte ese enlace en el chat para actualizarlo de forma segura.
  goto :error
)
if exist ".git" (
  echo [ERROR] La carpeta ya tiene un repositorio Git.
  echo No publicare encima de un repositorio preexistente.
  goto :error
)

echo Repo nuevo: !REPO_FULL!
set /p "CONFIRM=Escribe PUBLICAR para confirmar: "
if /I not "!CONFIRM!"=="PUBLICAR" (
  echo Cancelado.
  exit /b 0
)

git init || goto :error
git branch -M main || goto :error
git config user.name "!GH_LOGIN!" || goto :error
git config user.email "!GH_ID!+!GH_LOGIN!@users.noreply.github.com" || goto :error
git add -A || goto :error
git diff --cached --check || goto :error
git commit -m "Initial public NikaView source" || goto :error
gh repo create NikaView --public --source=. --remote=origin --push
if errorlevel 1 (
  echo [ERROR] No se pudo crear o subir el repositorio.
  echo Los archivos siguen en esta carpeta; revisa la salida anterior.
  goto :error
)

if not exist "%LOCALAPPDATA%\SolidSecViewer" mkdir "%LOCALAPPDATA%\SolidSecViewer"
> "%LOCALAPPDATA%\SolidSecViewer\github_repo.txt" echo !REPO_FULL!
echo.
echo [LISTO] https://github.com/!REPO_FULL!
echo Para futuras actualizaciones revisa el archivo ACTUALIZAR_GITHUB.bat.
pause
exit /b 0

:invalid
echo [ERROR] No encuentro el proyecto Xcode en esta carpeta.
:error
echo.
echo Revisa los mensajes y tu cuenta de GitHub antes de reintentar.
pause
exit /b 1
