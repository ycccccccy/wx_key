#include <iostream>
#include <windows.h>
#include <string>
#include <vector>
#include <tlhelp32.h>
#include <fstream>
#include <chrono>
#include <thread>
#include <shlwapi.h>
#include <algorithm>
#include <wininet.h>

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "wininet.lib")

const char* TARGET_PROCESS_NAME = "Weixin.exe";
const char* CONFIG_FILE_NAME = "config.txt";

// --- Function Declarations ---
// Core Logic
std::wstring GetWeChatPath(int argc, char* argv[]);
std::wstring GetWeChatVersion(const std::wstring& wechatDir);
bool DownloadDll(const std::wstring& version, std::wstring& outDllPath);
void MonitorLogFile(const std::string& logPath);

// Path and Config
void SavePathToConfig(const std::wstring& path);
std::wstring LoadPathFromConfig();
std::wstring FindWeChatExePath();
std::wstring SearchUninstallKeys();
std::wstring SearchAppPaths();
std::wstring SearchTencentKeys();
std::wstring ScanCommonPaths();
std::wstring ReadRegValue(HKEY hRootKey, const std::wstring& keyPath, const std::wstring& valueName);
std::wstring ParsePathFromRegValue(const std::wstring& rawValue, const std::wstring& valueName);

// Process and Injection
bool GetProcessIdByName(const char* processName, DWORD& processId);
bool TerminateProcessByName(const char* processName);
bool WaitForWindow(DWORD processId, int timeoutSeconds);
void EnableDebugPrivilege();
bool InjectDll(DWORD processId, const std::wstring& dllPath);
std::string GetLogFilePath();
std::wstring CharToWstring(const char* str);

// --- Main Function ---
int main(int argc, char* argv[]) {
    std::wcout.imbue(std::locale(""));
    std::wcin.imbue(std::locale(""));
    std::cout << "WeChat Key Launcher - Final Networked Version" << std::endl;
    std::cout << "---------------------------------------------" << std::endl;

    EnableDebugPrivilege();

    // 1. Get WeChat Path
    std::wstring wechatExePath = GetWeChatPath(argc, argv);
    if (wechatExePath.empty() || !PathFileExistsW(wechatExePath.c_str())) {
        std::wcerr << L"ERROR: WeChat path is invalid or not found. Exiting." << std::endl;
        system("pause");
        return 1;
    }
    std::wcout << L"SUCCESS: Using WeChat path: " << wechatExePath << std::endl;

    // 2. Get WeChat Version
    wchar_t wechatDir[MAX_PATH];
    wcscpy_s(wechatDir, wechatExePath.c_str());
    PathRemoveFileSpecW(wechatDir);
    std::wstring version = GetWeChatVersion(wechatDir);
    if (version.empty()) {
        std::wcerr << L"ERROR: Could not determine WeChat version from directory: " << wechatDir << std::endl;
        system("pause");
        return 1;
    }
    std::wcout << L"SUCCESS: Detected WeChat version: " << version << std::endl;

    // 3. Download the corresponding DLL
    std::wstring dllPath;
    std::wcout << L"INFO: Attempting to download DLL for version " << version << L"..." << std::endl;
    if (!DownloadDll(version, dllPath)) {
        std::wcerr << L"ERROR: Failed to download DLL. Please check your network connection or if the version is supported." << std::endl;
        system("pause");
        return 1;
    }
    std::wcout << L"SUCCESS: DLL is ready at: " << dllPath << std::endl;

    // --- Automation Flow ---
    std::cout << "INFO: Checking for running WeChat process..." << std::endl;
    if (TerminateProcessByName(TARGET_PROCESS_NAME)) {
        std::cout << "SUCCESS: Existing WeChat process terminated. Waiting..." << std::endl;
        Sleep(2000);
    } else {
        std::cout << "INFO: WeChat is not running." << std::endl;
    }

    std::cout << "INFO: Starting new WeChat process..." << std::endl;
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = { 0 };
    if (!CreateProcessW(wechatExePath.c_str(), NULL, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        std::cerr << "ERROR: Failed to start WeChat process. Error: " << GetLastError() << std::endl;
        system("pause");
        return 1;
    }
    std::cout << "SUCCESS: WeChat started (PID: " << pi.dwProcessId << ")." << std::endl;

    std::cout << "INFO: Waiting for WeChat window to be ready..." << std::endl;
    if (!WaitForWindow(pi.dwProcessId, 30)) {
        std::cerr << "ERROR: Timed out waiting for WeChat window." << std::endl;
        TerminateProcess(pi.hProcess, 1);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        system("pause");
        return 1;
    }
    std::cout << "SUCCESS: WeChat window is ready." << std::endl;
    Sleep(1000);

    std::wcout << L"INFO: Injecting DLL: " << dllPath << std::endl;
    if (!InjectDll(pi.dwProcessId, dllPath)) {
        std::cerr << "ERROR: DLL injection failed. Please run as Administrator." << std::endl;
        system("pause");
        return 1;
    }
    std::cout << "SUCCESS: DLL injected. Waiting for key..." << std::endl;
    
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    MonitorLogFile(GetLogFilePath());

    system("pause");
    return 0;
}

// --- Core Logic: Version Detection and Download ---
std::wstring GetWeChatVersion(const std::wstring& wechatDir) {
    WIN32_FIND_DATAW findFileData;
    HANDLE hFind = FindFirstFileW((wechatDir + L"\\*").c_str(), &findFileData);
    if (hFind == INVALID_HANDLE_VALUE) return L"";
    do {
        if (findFileData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            std::wstring dirName = findFileData.cFileName;
            if (dirName.length() > 5 && dirName[0] >= L'0' && dirName[0] <= L'9' && std::count(dirName.begin(), dirName.end(), L'.') == 3) {
                FindClose(hFind);
                return dirName;
            }
        }
    } while (FindNextFileW(hFind, &findFileData) != 0);
    FindClose(hFind);
    return L"";
}

bool DownloadDll(const std::wstring& version, std::wstring& outDllPath) {
    wchar_t tempPath[MAX_PATH];
    GetTempPathW(MAX_PATH, tempPath);
    std::wstring dllFileName = L"wx_key-" + version + L".dll";
    outDllPath = std::wstring(tempPath) + dllFileName;

    if (PathFileExistsW(outDllPath.c_str())) {
        std::wcout << L"INFO: DLL already exists locally." << std::endl;
        return true;
    }

    std::wstring url = L"https://hk.gh-proxy.com/github.com/ycccccccy/wx_key/releases/download/dlls/" + dllFileName;
    std::wcout << L"INFO: Downloading from: " << url << std::endl;

    HINTERNET hInternet = InternetOpenW(L"WeChatKeyLauncher/1.0", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
    if (!hInternet) return false;

    HINTERNET hConnect = InternetOpenUrlW(hInternet, url.c_str(), NULL, 0, INTERNET_FLAG_RELOAD, 0);
    if (!hConnect) {
        InternetCloseHandle(hInternet);
        return false;
    }

    DWORD statusCode = 0;
    DWORD statusCodeSize = sizeof(statusCode);
    HttpQueryInfoW(hConnect, HTTP_QUERY_STATUS_CODE | HTTP_QUERY_FLAG_NUMBER, &statusCode, &statusCodeSize, NULL);
    if (statusCode != 200) {
        std::wcerr << L"ERROR: Server returned HTTP status " << statusCode << std::endl;
        InternetCloseHandle(hConnect);
        InternetCloseHandle(hInternet);
        return false;
    }

    HANDLE hFile = CreateFileW(outDllPath.c_str(), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        InternetCloseHandle(hConnect);
        InternetCloseHandle(hInternet);
        return false;
    }

    char buffer[4096];
    DWORD bytesRead, bytesWritten;
    while (InternetReadFile(hConnect, buffer, sizeof(buffer), &bytesRead) && bytesRead > 0) {
        WriteFile(hFile, buffer, bytesRead, &bytesWritten, NULL);
    }

    CloseHandle(hFile);
    InternetCloseHandle(hConnect);
    InternetCloseHandle(hInternet);
    return true;
}

// --- Path and Config Logic ---
std::wstring GetWeChatPath(int argc, char* argv[]) {
    std::wstring wechatExePath;
    if (argc > 1) {
        wechatExePath = CharToWstring(argv[1]);
        if (PathFileExistsW(wechatExePath.c_str())) {
            SavePathToConfig(wechatExePath);
            return wechatExePath;
        }
    }
    wechatExePath = LoadPathFromConfig();
    if (!wechatExePath.empty() && PathFileExistsW(wechatExePath.c_str())) return wechatExePath;
    wechatExePath = FindWeChatExePath();
    if (!wechatExePath.empty() && PathFileExistsW(wechatExePath.c_str())) {
        SavePathToConfig(wechatExePath);
        return wechatExePath;
    }
    std::cerr << "ERROR: Could not find WeChat automatically." << std::endl;
    std::cout << "INFO: Please provide the full path to WeChat.exe:" << std::endl;
    std::getline(std::wcin, wechatExePath);
    if (!wechatExePath.empty() && wechatExePath.front() == L'"' && wechatExePath.back() == L'"') {
        wechatExePath = wechatExePath.substr(1, wechatExePath.length() - 2);
    }
    if (PathFileExistsW(wechatExePath.c_str())) {
        SavePathToConfig(wechatExePath);
        return wechatExePath;
    }
    return L"";
}

void SavePathToConfig(const std::wstring& path) {
    std::wofstream configFile(CONFIG_FILE_NAME);
    if (configFile.is_open()) {
        configFile << path;
        configFile.close();
    }
}

std::wstring LoadPathFromConfig() {
    std::wifstream configFile(CONFIG_FILE_NAME);
    if (configFile.is_open()) {
        std::wstring path;
        std::getline(configFile, path);
        configFile.close();
        return path;
    }
    return L"";
}

std::wstring FindWeChatExePath() {
    std::wstring path;
    path = SearchUninstallKeys(); if (!path.empty()) return path;
    path = SearchAppPaths(); if (!path.empty()) return path;
    path = SearchTencentKeys(); if (!path.empty()) return path;
    path = ScanCommonPaths(); if (!path.empty()) return path;
    return L"";
}

std::wstring SearchUninstallKeys() {
    const std::vector<HKEY> rootKeys = { HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER };
    const std::vector<std::wstring> uninstallPaths = {
        L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
        L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
    };
    const std::vector<std::wstring> valueNames = {
        L"InstallLocation", L"InstallPath", L"DisplayIcon", L"UninstallString", L"InstallDir"
    };
    for (HKEY rootKey : rootKeys) {
        for (const auto& uninstallPath : uninstallPaths) {
            HKEY hKey;
            if (RegOpenKeyExW(rootKey, uninstallPath.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS) continue;
            DWORD index = 0;
            wchar_t subKeyName[256];
            DWORD subKeyNameSize = 256;
            while (RegEnumKeyExW(hKey, index, subKeyName, &subKeyNameSize, NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
                std::wstring subKeyNameStr = subKeyName;
                std::transform(subKeyNameStr.begin(), subKeyNameStr.end(), subKeyNameStr.begin(), ::towlower);
                if (subKeyNameStr.find(L"weixin") != std::wstring::npos) {
                    std::wstring fullSubKeyPath = uninstallPath + L"\\" + subKeyName;
                    for (const auto& valueName : valueNames) {
                        std::wstring rawValue = ReadRegValue(rootKey, fullSubKeyPath, valueName);
                        if (!rawValue.empty()) {
                            std::wstring finalPath = ParsePathFromRegValue(rawValue, valueName);
                            if (!finalPath.empty() && PathFileExistsW(finalPath.c_str())) {
                                RegCloseKey(hKey);
                                return finalPath;
                            }
                        }
                    }
                }
                subKeyNameSize = 256;
                index++;
            }
            RegCloseKey(hKey);
        }
    }
    return L"";
}

std::wstring SearchAppPaths() {
    const std::vector<HKEY> rootKeys = { HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER };
    const std::vector<std::wstring> appNames = { L"Weixin.exe" };
    for (HKEY rootKey : rootKeys) {
        for (const auto& appName : appNames) {
            std::wstring keyPath = L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\" + appName;
            std::wstring path = ReadRegValue(rootKey, keyPath, L"");
            if (!path.empty() && PathFileExistsW(path.c_str())) return path;
        }
    }
    return L"";
}

std::wstring SearchTencentKeys() {
    const std::vector<HKEY> rootKeys = { HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER };
    const std::vector<std::wstring> keyPaths = {
        L"Software\\Tencent\\Weixin"
    };
    for (HKEY rootKey : rootKeys) {
        for (const auto& keyPath : keyPaths) {
            std::wstring path = ReadRegValue(rootKey, keyPath, L"InstallPath");
            if (!path.empty()) {
                path += L"\\Weixin.exe";
                if (PathFileExistsW(path.c_str())) return path;
            }
        }
    }
    return L"";
}

std::wstring ScanCommonPaths() {
    const std::vector<std::wstring> drives = { L"C:", L"D:", L"E:", L"F:" };
    const std::vector<std::wstring> commonPaths = {
        L"\\Program Files\\Tencent\\Weixin\\Weixin.exe",
        L"\\Program Files (x86)\\Tencent\\Weixin\\Weixin.exe"
    };
    for (const auto& drive : drives) {
        for (const auto& commonPath : commonPaths) {
            std::wstring fullPath = drive + commonPath;
            if (PathFileExistsW(fullPath.c_str())) return fullPath;
        }
    }
    return L"";
}

std::wstring ReadRegValue(HKEY hRootKey, const std::wstring& keyPath, const std::wstring& valueName) {
    HKEY hKey;
    if (RegOpenKeyExW(hRootKey, keyPath.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS) return L"";
    wchar_t buffer[MAX_PATH];
    DWORD bufferSize = sizeof(buffer);
    if (RegQueryValueExW(hKey, valueName.c_str(), NULL, NULL, (LPBYTE)buffer, &bufferSize) == ERROR_SUCCESS) {
        RegCloseKey(hKey);
        return buffer;
    }
    RegCloseKey(hKey);
    return L"";
}

std::wstring ParsePathFromRegValue(const std::wstring& rawValue, const std::wstring& valueName) {
    std::wstring cleanedPath = rawValue;
    if (valueName == L"DisplayIcon" || valueName == L"UninstallString") {
        size_t pos = cleanedPath.find(L",");
        if (pos != std::wstring::npos) cleanedPath = cleanedPath.substr(0, pos);
        if (!cleanedPath.empty() && cleanedPath.front() == L'"') cleanedPath.erase(0, 1);
        if (!cleanedPath.empty() && cleanedPath.back() == L'"') cleanedPath.pop_back();
    }
    if (PathIsDirectoryW(cleanedPath.c_str())) {
        wchar_t finalPath[MAX_PATH];
        PathCombineW(finalPath, cleanedPath.c_str(), L"Weixin.exe");
        return finalPath;
    }
    if (PathFindFileNameW(cleanedPath.c_str()) != cleanedPath.c_str()) {
         return cleanedPath;
    }
    return L"";
}

// --- Other Helper Functions ---
std::wstring CharToWstring(const char* str) {
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, str, -1, &wstrTo[0], size_needed);
    if (!wstrTo.empty() && wstrTo.back() == L'\0') wstrTo.pop_back();
    return wstrTo;
}

void MonitorLogFile(const std::string& logPath) {
    std::cout << "INFO: Monitoring log file: " << logPath << std::endl;
    std::ifstream logStream(logPath);
    auto startTime = std::chrono::steady_clock::now();
    while (std::chrono::steady_clock::now() - startTime < std::chrono::seconds(60)) {
        std::string line;
        while (std::getline(logStream, line)) {
            std::cout << "LOG: " << line << std::endl;
            if (line.rfind("KEY:", 0) == 0) {
                std::cout << "\n==================== KEY FOUND ====================" << std::endl;
                std::cout << "  " << line << std::endl;
                std::cout << "===================================================" << std::endl;
                logStream.close();
                return;
            }
        }
        if (logStream.eof()) logStream.clear();
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
    std::cerr << "ERROR: Timed out waiting for key (60s)." << std::endl;
    logStream.close();
}

std::string GetLogFilePath() {
    char tempPath[MAX_PATH];
    GetTempPathA(MAX_PATH, tempPath);
    return std::string(tempPath) + "wx_key_status.log";
}

bool GetProcessIdByName(const char* processName, DWORD& processId) {
    PROCESSENTRY32 pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32);
    HANDLE hProcessSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hProcessSnap == INVALID_HANDLE_VALUE) return false;
    if (Process32First(hProcessSnap, &pe32)) {
        do {
            if (_stricmp(pe32.szExeFile, processName) == 0) {
                processId = pe32.th32ProcessID;
                CloseHandle(hProcessSnap);
                return true;
            }
        } while (Process32Next(hProcessSnap, &pe32));
    }
    CloseHandle(hProcessSnap);
    return false;
}

bool TerminateProcessByName(const char* processName) {
    DWORD pid = 0;
    if (!GetProcessIdByName(processName, pid)) return false;
    HANDLE hProcess = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
    if (hProcess == NULL) return false;
    bool result = TerminateProcess(hProcess, 1);
    CloseHandle(hProcess);
    return result;
}

struct EnumData { DWORD processId; bool found; };
BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lParam) {
    EnumData* pData = (EnumData*)lParam;
    DWORD windowProcessId;
    GetWindowThreadProcessId(hwnd, &windowProcessId);
    if (pData->processId == windowProcessId) {
        pData->found = true;
        return FALSE;
    }
    return TRUE;
}

bool WaitForWindow(DWORD processId, int timeoutSeconds) {
    EnumData data = { processId, false };
    auto startTime = std::chrono::steady_clock::now();
    while (std::chrono::steady_clock::now() - startTime < std::chrono::seconds(timeoutSeconds)) {
        EnumWindows(EnumWindowsProc, (LPARAM)&data);
        if (data.found) return true;
        Sleep(500);
    }
    return false;
}

void EnableDebugPrivilege() {
    HANDLE hToken;
    LUID luid;
    TOKEN_PRIVILEGES tkp;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) return;
    if (!LookupPrivilegeValue(NULL, SE_DEBUG_NAME, &luid)) { CloseHandle(hToken); return; }
    tkp.PrivilegeCount = 1;
    tkp.Privileges[0].Luid = luid;
    tkp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    AdjustTokenPrivileges(hToken, FALSE, &tkp, sizeof(tkp), NULL, NULL);
    CloseHandle(hToken);
}

bool InjectDll(DWORD processId, const std::wstring& dllPath) {
    HANDLE hProcess = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ, FALSE, processId);
    if (!hProcess) return false;
    
    size_t dllPathSize = (dllPath.length() + 1) * sizeof(wchar_t);
    LPVOID pRemoteBuf = VirtualAllocEx(hProcess, NULL, dllPathSize, MEM_COMMIT, PAGE_READWRITE);
    if (!pRemoteBuf) { CloseHandle(hProcess); return false; }

    if (!WriteProcessMemory(hProcess, pRemoteBuf, dllPath.c_str(), dllPathSize, NULL)) {
        VirtualFreeEx(hProcess, pRemoteBuf, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        return false;
    }

    HMODULE hKernel32 = GetModuleHandleW(L"kernel32.dll");
    FARPROC pLoadLibraryW = GetProcAddress(hKernel32, "LoadLibraryW");

    HANDLE hRemoteThread = CreateRemoteThread(hProcess, NULL, 0, (LPTHREAD_START_ROUTINE)pLoadLibraryW, pRemoteBuf, 0, NULL);
    if (!hRemoteThread) {
        VirtualFreeEx(hProcess, pRemoteBuf, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        return false;
    }

    WaitForSingleObject(hRemoteThread, INFINITE);
    VirtualFreeEx(hProcess, pRemoteBuf, 0, MEM_RELEASE);
    CloseHandle(hRemoteThread);
    CloseHandle(hProcess);
    return true;
}
