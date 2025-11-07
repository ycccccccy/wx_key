    #ifndef STRING_OBFUSCATOR_H
    #define STRING_OBFUSCATOR_H

    #include <string>
    #include <array>

    // 编译时字符串加密 - XOR加密
    template<size_t N>
    class ObfuscatedString {
    private:
        std::array<char, N> data;
        
        constexpr char decrypt_char(char c, size_t i) const {
            return c ^ static_cast<char>(0xAA + (i % 256));
        }
        
    public:
        template<size_t... I>
        constexpr ObfuscatedString(const char* str, std::index_sequence<I...>)
            : data{ {static_cast<char>(str[I] ^ static_cast<unsigned char>(0xAA + (I % 256)))...} } {}
        
        std::string decrypt() const {
            std::string result;
            if (N > 0) {
                result.reserve(N - 1);
                for (size_t i = 0; i < N - 1; ++i) {
                    result.push_back(decrypt_char(data[i], i));
                }
            }
            return result;
        }
    };

    // 辅助宏定义
    #define OBFUSCATE_STR(str) \
        ([]() { \
            constexpr auto size = sizeof(str); \
            return ObfuscatedString<size>(str, std::make_index_sequence<size>{}); \
        }().decrypt())

    // 常用字符串的加密版本
    namespace ObfuscatedStrings {
        inline std::string GetSharedMemoryName() {
            return OBFUSCATE_STR("Global\\WxKeySharedMemory_{GUID}");
        }
        
        inline std::string GetEventName() {
            return OBFUSCATE_STR("Global\\WxKeyEvent_{GUID}");
        }
        
        inline std::string GetWeixinDllName() {
            return OBFUSCATE_STR("Weixin.dll");
        }
        
        inline std::string GetNtdllName() {
            return OBFUSCATE_STR("ntdll.dll");
        }
    }

    #endif // STRING_OBFUSCATOR_H

