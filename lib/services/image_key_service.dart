import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:path/path.dart' as path;
import 'package:pointycastle/export.dart';
import 'dll_injector.dart';

final class MEMORY_BASIC_INFORMATION extends Struct {
  @IntPtr()
  external int BaseAddress;
  
  @IntPtr()
  external int AllocationBase;
  
  @Uint32()
  external int AllocationProtect;
  
  @IntPtr()
  external int RegionSize;
  
  @Uint32()
  external int State;
  
  @Uint32()
  external int Protect;
  
  @Uint32()
  external int Type;
}

class ImageKeyResult {
  final int? xorKey;
  final String? aesKey;
  final String? error;
  final bool success;

  ImageKeyResult.success(this.xorKey, this.aesKey)
      : success = true,
        error = null;

  ImageKeyResult.failure(this.error)
      : success = false,
        xorKey = null,
        aesKey = null;
}

class ImageKeyService {
  /// 获取微信缓存目录
  static Future<String?> getWeChatCacheDirectory() async {
    try {
      final documentsPath = Platform.environment['USERPROFILE'];
      
      if (documentsPath == null) {
        return null;
      }

      final wechatFilesPath = path.join(documentsPath, 'Documents', 'xwechat_files');
      
      final wechatFilesDir = Directory(wechatFilesPath);

      if (!await wechatFilesDir.exists()) {
        return null;
      }

      // 首先尝试原始方式：查找 wxid_* 或其他符合条件的目录
      await for (var entity in wechatFilesDir.list()) {
        if (entity is Directory) {
          final dirName = path.basename(entity.path);
          
          // 检查是否是微信账号目录（以wxid_开头，或者符合其他条件）
          if (dirName.startsWith('wxid_') || 
              (dirName.length > 5 && 
               !dirName.toLowerCase().startsWith('all') && 
               !dirName.toLowerCase().startsWith('applet') &&
               !dirName.toLowerCase().startsWith('backup') &&
               !dirName.toLowerCase().startsWith('wmpf'))) {
            
            // 不再检查特定的子目录结构，而是检查是否有 *_t.dat 文件
            try {
              await for (var file in Directory(entity.path).list(recursive: true)) {
                if (file is File && path.basename(file.path).endsWith('_t.dat')) {
                  return entity.path;
                }
              }
            } catch (e) {
              continue;
            }
          }
        }
      }

      // 如果原始方式找不到，使用备选方式：查找包含 db_storage 文件夹的目录
      await for (var entity in wechatFilesDir.list()) {
        if (entity is Directory) {
          final dirName = path.basename(entity.path);
          
          // 跳过特定的系统目录
          if (dirName.toLowerCase().startsWith('all') || 
              dirName.toLowerCase().startsWith('applet') ||
              dirName.toLowerCase().startsWith('backup') ||
              dirName.toLowerCase().startsWith('wmpf')) {
            continue;
          }
          
          // 检查该目录下是否有 db_storage 文件夹
          try {
            final dbStoragePath = path.join(entity.path, 'db_storage');
            final dbStorageDir = Directory(dbStoragePath);
            if (await dbStorageDir.exists()) {
              return entity.path;
            }
          } catch (e) {
            continue;
          }
        }
      }

      return null;
    } catch (e, _) {
      return null;
    }
  }

  /// 查找所有 *_t.dat 文件（递归搜索整个目录）
  static Future<List<File>> _findTemplateDatFiles(String userDir) async {
    final files = <File>[];
    try {
      
      final userDirEntity = Directory(userDir);
      if (!await userDirEntity.exists()) {
        return [];
      }
      
      // 递归搜索所有 *_t.dat 文件
      await for (var entity in userDirEntity.list(recursive: true)) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          if (fileName.endsWith('_t.dat')) {
            files.add(entity);
          }
        }
      }
      
      
      if (files.isEmpty) {
        return [];
      }
      
      // 按日期排序（降序）
      files.sort((a, b) {
        final pathA = a.path;
        final pathB = b.path;
        final regExp = RegExp(r'(\d{4}-\d{2})');
        final matchA = regExp.firstMatch(pathA);
        final matchB = regExp.firstMatch(pathB);
        if (matchA != null && matchB != null) {
          return matchB.group(1)!.compareTo(matchA.group(1)!);
        }
        return 0;
      });
      
      return files.take(16).toList();
    } catch (e, _) {
      return [];
    }
  }

  /// 获取XOR密钥
  static Future<int?> _getXorKey(List<File> templateFiles) async {
    try {
      final lastBytesMap = <String, int>{};

      for (var file in templateFiles) {
        try {
          final bytes = await file.readAsBytes();
          if (bytes.length >= 2) {
            final lastTwo = bytes.sublist(bytes.length - 2);
            final key = '${lastTwo[0]}_${lastTwo[1]}';
            lastBytesMap[key] = (lastBytesMap[key] ?? 0) + 1;
          }
        } catch (e) {
          continue;
        }
      }

      if (lastBytesMap.isEmpty) {
        return null;
      }

      var maxCount = 0;
      String? mostCommon;
      lastBytesMap.forEach((key, count) {
        if (count > maxCount) {
          maxCount = count;
          mostCommon = key;
        }
      });

      if (mostCommon != null) {
        final parts = mostCommon!.split('_');
        final x = int.parse(parts[0]);
        final y = int.parse(parts[1]);
        
        final xorKey = x ^ 0xFF;
        final check = y ^ 0xD9;
        
        if (xorKey == check) {
          return xorKey;
        }
      }

      return null;
    } catch (e, _) {
      return null;
    }
  }

  /// 从模板文件读取加密的AES数据
  static Future<Uint8List?> _getCiphertextFromTemplate(List<File> templateFiles) async {
    try {
      
      for (var file in templateFiles) {
        final bytes = await file.readAsBytes();
        
        if (bytes.length < 8) {
          continue;
        }
        
        final header = bytes.sublist(0, 6);
        
        if (header[0] == 0x07 && header[1] == 0x08 && 
            header[2] == 0x56 && header[3] == 0x32 && 
            header[4] == 0x08 && header[5] == 0x07) {
          
          if (bytes.length >= 0x1F) {
            final ciphertext = bytes.sublist(0xF, 0x1F);
            return ciphertext;
          }
        }
      }
      
      return null;
    } catch (e, _) {
      return null;
    }
  }

  /// 验证密钥是否正确（完全按照Python版本实现）
  static bool _verifyKey(Uint8List encrypted, Uint8List aesKey) {
    try {
      final key = aesKey.sublist(0, 16); // aes_key = key[:16]
      
      // cipher = AES.new(aes_key, AES.MODE_ECB)
      final cipher = ECBBlockCipher(AESEngine());
      cipher.init(false, KeyParameter(key)); 
      
      // text = cipher.decrypt(encrypted)
      final decrypted = Uint8List(encrypted.length);
      for (var offset = 0; offset < encrypted.length; offset += 16) {
        cipher.processBlock(encrypted, offset, decrypted, offset);
      }
      
      // if text.startswith(b"\xff\xd8\xff"):
      if (decrypted.length >= 3 && 
          decrypted[0] == 0xFF && 
          decrypted[1] == 0xD8 && 
          decrypted[2] == 0xFF) {
        // 找到有效密钥，打印信息
        return true;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 从微信进程内存中搜索AES密钥
  static Future<String?> _getAesKeyFromMemory(int pid, Uint8List ciphertext) async {
    
    final hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (hProcess == 0) {
      return null;
    }

    try {
      final memoryRegions = _getMemoryRegions(hProcess);

      for (var region in memoryRegions) {
        final baseAddress = region.$1;
        final regionSize = region.$2;
        
        // 跳过太大的内存区域
        if (regionSize > 100 * 1024 * 1024) {
          continue;
        }
        
        final memory = _readProcessMemory(hProcess, baseAddress, regionSize);
        if (memory == null) continue;

        // 直接在原始字节中搜索32字节的小写字母数字序列
        // 类似YARA规则: /[^a-z0-9][a-z0-9]{32}[^a-z0-9]/
        for (var i = 0; i < memory.length - 34; i++) {
          final byte = memory[i];
          
          // 检查前导字符（不是小写字母或数字）
          if (_isAlphaNumLower(byte)) continue;
          
          // 检查接下来32个字节是否都是小写字母或数字
          var isValid = true;
          for (var j = 1; j <= 32; j++) {
            if (i + j >= memory.length || !_isAlphaNumLower(memory[i + j])) {
              isValid = false;
              break;
            }
          }
          
          if (!isValid) continue;
          
          // 检查尾部字符（不是小写字母或数字）
          if (i + 33 < memory.length && _isAlphaNumLower(memory[i + 33])) {
            continue;
          }
          
          try {
            final keyBytes = memory.sublist(i + 1, i + 33);
            
            if (_verifyKey(ciphertext, keyBytes)) {
              CloseHandle(hProcess);
              return String.fromCharCodes(keyBytes);
            }
          } catch (e) {
            continue;
          }
        }
      }

      CloseHandle(hProcess);
      return null;
    } catch (e, _) {
      CloseHandle(hProcess);
      return null;
    }
  }
  
  /// 检查字节是否是小写字母或数字
  static bool _isAlphaNumLower(int byte) {
    return (byte >= 0x61 && byte <= 0x7A) || // a-z
           (byte >= 0x30 && byte <= 0x39);    // 0-9
  }

  /// 获取进程的内存区域
  static List<(int, int)> _getMemoryRegions(int hProcess) {
    final regions = <(int, int)>[];
    var address = 0;
    final mbi = calloc<MEMORY_BASIC_INFORMATION>();

    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final virtualQueryEx = kernel32.lookupFunction<
          IntPtr Function(IntPtr, Pointer, Pointer<MEMORY_BASIC_INFORMATION>, IntPtr),
          int Function(int, Pointer, Pointer<MEMORY_BASIC_INFORMATION>, int)>(
          'VirtualQueryEx');

      // 遍历整个地址空间（64位）
      while (address >= 0 && address < 0x7FFFFFFFFFFF) {
        final result = virtualQueryEx(
          hProcess,
          Pointer.fromAddress(address),
          mbi,
          sizeOf<MEMORY_BASIC_INFORMATION>(),
        );

        if (result == 0) {
          // 没有更多内存区域了
          break;
        }

        // 只收集已提交的私有内存
        if (mbi.ref.State == MEM_COMMIT && mbi.ref.Type == MEM_PRIVATE) {
          regions.add((mbi.ref.BaseAddress, mbi.ref.RegionSize));
        }

        // 移动到下一个内存区域
        final nextAddress = address + mbi.ref.RegionSize;
        if (nextAddress <= address) {
          // 防止溢出
          break;
        }
        address = nextAddress;
      }
      
    } finally {
      free(mbi);
    }

    return regions;
  }

  /// 读取进程内存
  static Uint8List? _readProcessMemory(int hProcess, int address, int size) {
    final buffer = calloc<Uint8>(size);
    final bytesRead = calloc<SIZE_T>();

    try {
      final result = ReadProcessMemory(
        hProcess,
        Pointer.fromAddress(address),
        buffer,
        size,
        bytesRead,
      );

      if (result == 0) {
        return null;
      }

      return Uint8List.fromList(buffer.asTypedList(size));
    } catch (e) {
      return null;
    } finally {
      free(buffer);
      free(bytesRead);
    }
  }

  /// 获取图片密钥（XOR和AES）
  static Future<ImageKeyResult> getImageKeys() async {
    try {
      
      final cacheDir = await getWeChatCacheDirectory();
      if (cacheDir == null) {
        return ImageKeyResult.failure('未找到微信缓存目录，请查看日志获取详细信息');
      }


      final templateFiles = await _findTemplateDatFiles(cacheDir);
      if (templateFiles.isEmpty) {
        return ImageKeyResult.failure('未找到模板文件，可能该微信账号没有图片缓存');
      }


      final xorKey = await _getXorKey(templateFiles);
      if (xorKey == null) {
        return ImageKeyResult.failure('无法获取XOR密钥');
      }


      final ciphertext = await _getCiphertextFromTemplate(templateFiles);
      if (ciphertext == null) {
        return ImageKeyResult.failure('无法读取加密数据');
      }


      final pids = DllInjector.findProcessIds('Weixin.exe');
      if (pids.isEmpty) {
        return ImageKeyResult.failure('微信进程未运行');
      }


      final aesKey = await _getAesKeyFromMemory(pids.first, ciphertext);
      if (aesKey == null) {
        return ImageKeyResult.failure('无法从内存中获取AES密钥');
      }


      return ImageKeyResult.success(xorKey, aesKey.substring(0, 16));
    } catch (e, _) {
      return ImageKeyResult.failure('获取密钥失败: $e');
    }
  }
}

