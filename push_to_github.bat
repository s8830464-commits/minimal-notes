@echo off
chcp 65001 > nul
echo =======================================================
echo   Подготовка и отправка NotesApp в ваш GitHub
echo =======================================================
echo.

if not exist .git (
    echo Инициализация локального репозитория git...
    git init
    git branch -M main
)

echo Добавление файлов проекта...
git add .
git commit -m "Initial commit: Minimal Notes iOS app with GitHub Actions IPA build"

echo.
echo Введите URL вашего репозитория на GitHub:
echo (Например: https://github.com/ваш-логин/minimal-notes.git)
set /p REPO_URL="URL: "

if "%REPO_URL%"=="" (
    echo Репозиторий не указан. Завершение.
    pause
    exit /b
)

git remote remove origin 2>nul
git remote add origin %REPO_URL%
echo.
echo Отправка кода на GitHub...
git push -u origin main

echo.
echo =======================================================
echo   Готово! Перейдите во вкладку 'Actions' на GitHub,
echo   чтобы увидеть сборку IPA файла.
echo =======================================================
pause
