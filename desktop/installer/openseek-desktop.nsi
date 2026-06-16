Unicode True
ManifestDPIAware True
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetOverwrite on

!ifndef APP_VERSION
!define APP_VERSION "0.1.0"
!endif

!ifndef SOURCE_DIR
!define SOURCE_DIR "dist\windows-x64\OpenSeek Desktop"
!endif

!ifndef OUTPUT_DIR
!define OUTPUT_DIR "dist"
!endif

!define APP_NAME "OpenSeek Desktop"
!define APP_PUBLISHER "OpenSeek"
!define APP_EXE "openseek-desktop.exe"
!define APP_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\OpenSeek Desktop"

!include "MUI2.nsh"

Name "${APP_NAME}"
OutFile "${OUTPUT_DIR}\OpenSeek-Desktop-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\OpenSeek Desktop"
BrandingText "${APP_NAME}"

VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} installer"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" "${APP_PUBLISHER}"

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${APP_NAME}"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "OpenSeek Desktop" SecInstall
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  SectionIn RO

  Delete "$INSTDIR\toolchains\moonbit\windows-x64\.openseek-toolchain-marker"
  Delete "$INSTDIR\toolchains\moonbit\windows-x64\.openseek-toolchain-ready"

  File /r "${SOURCE_DIR}\*"

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\OpenSeek"
  CreateShortcut "$SMPROGRAMS\OpenSeek\OpenSeek Desktop.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\OpenSeek\Uninstall OpenSeek Desktop.lnk" "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "${APP_UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${APP_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${APP_UNINSTALL_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKCU "${APP_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${APP_UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${APP_UNINSTALL_KEY}" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegDWORD HKCU "${APP_UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${APP_UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section /o "Desktop Shortcut" SecDesktopShortcut
  SetShellVarContext current
  CreateShortcut "$DESKTOP\OpenSeek Desktop.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
SectionEnd

Section "Uninstall"
  SetShellVarContext current

  Delete "$DESKTOP\OpenSeek Desktop.lnk"
  Delete "$SMPROGRAMS\OpenSeek\OpenSeek Desktop.lnk"
  Delete "$SMPROGRAMS\OpenSeek\Uninstall OpenSeek Desktop.lnk"
  RMDir "$SMPROGRAMS\OpenSeek"

  DeleteRegKey HKCU "${APP_UNINSTALL_KEY}"
  RMDir /r "$INSTDIR"
SectionEnd
