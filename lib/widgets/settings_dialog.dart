import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/key_storage.dart';
import '../services/app_logger.dart';

/// 设置弹窗页面
class SettingsDialog extends StatefulWidget {
  final VoidCallback? onWechatDirectoryChanged;

  const SettingsDialog({
    super.key,
    this.onWechatDirectoryChanged,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  String? _currentWechatDir;
  String? _logFileSize;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final wechatDir = await KeyStorage.getWechatDirectory();
    final logSize = await AppLogger.getLogFileSize();
    
    if (mounted) {
      setState(() {
        _currentWechatDir = wechatDir;
        _logFileSize = logSize;
      });
    }
  }

  Future<void> _selectWechatDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择微信安装目录',
      );

      if (result == null) {
        return;
      }

      final weixinPath = '$result\\Weixin.exe';
      final wechatPath = '$result\\WeChat.exe';
      
      if (!File(weixinPath).existsSync() && !File(wechatPath).existsSync()) {
        if (mounted) {
          _showMessage('所选目录中未找到微信程序', isError: true);
        }
        await AppLogger.warning('用户选择了无效的微信目录: $result');
        return;
      }

      final saved = await KeyStorage.saveWechatDirectory(result);
      if (saved) {
        await AppLogger.success('用户手动设置微信目录: $result');
        setState(() {
          _currentWechatDir = result;
        });
        if (mounted) {
          _showMessage('微信目录已保存');
          widget.onWechatDirectoryChanged?.call();
        }
      } else {
        if (mounted) {
          _showMessage('保存目录失败', isError: true);
        }
        await AppLogger.error('保存微信目录失败');
      }
    } catch (e, stackTrace) {
      await AppLogger.error('选择微信目录时出错', e, stackTrace);
      if (mounted) {
        _showMessage('选择目录失败: $e', isError: true);
      }
    }
  }

  

  Future<void> _openLogFile() async {
    try {
      await AppLogger.info('用户请求打开应用日志文件');
      final success = await AppLogger.openLogFile();
      
      if (!success && mounted) {
        _showMessage('打开日志文件失败', isError: true);
      }
    } catch (e, stackTrace) {
      await AppLogger.error('打开日志文件时出错', e, stackTrace);
      if (mounted) {
        _showMessage('打开日志失败: $e', isError: true);
      }
    }
  }

  Future<void> _clearLogFile() async {
    final confirmed = await _showConfirmDialog(
      title: '确认清空日志',
      content: '这将清空所有应用日志记录。\n是否继续？',
    );

    if (!confirmed) return;

    try {
      await AppLogger.clearLog();
      await _loadCurrentSettings();
      
      if (mounted) {
        _showMessage('日志已清空');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('清空日志失败: $e', isError: true);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'HarmonyOS_SansSC',
          ),
        ),
        content: Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'HarmonyOS_SansSC',
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '取消',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontFamily: 'HarmonyOS_SansSC',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF07c160),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text(
              '确认',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'HarmonyOS_SansSC',
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 500,
          maxHeight: 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF07c160).withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07c160).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.settings,
                      color: Color(0xFF07c160),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '设置',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'HarmonyOS_SansSC',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),

            // 设置内容
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 微信目录设置
                    _buildSectionTitle('微信目录'),
                    const SizedBox(height: 12),
                    _buildSettingCard(
                      icon: Icons.folder_open,
                      iconColor: Colors.blue,
                      title: '选择微信目录',
                      subtitle: _currentWechatDir ?? '未设置（将自动检测）',
                      onTap: _selectWechatDirectory,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // 应用日志
                    _buildSectionTitle('应用日志'),
                    const SizedBox(height: 12),
                    _buildSettingCard(
                      icon: Icons.description_outlined,
                      iconColor: Colors.green,
                      title: '打开日志文件',
                      subtitle: _logFileSize != null ? '当前大小: $_logFileSize' : '查看应用运行日志',
                      onTap: _openLogFile,
                    ),
                    const SizedBox(height: 12),
                    _buildSettingCard(
                      icon: Icons.clear_all,
                      iconColor: Colors.red,
                      title: '清空日志',
                      subtitle: '清除所有应用日志记录',
                      onTap: _clearLogFile,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
        fontFamily: 'HarmonyOS_SansSC',
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.grey.shade200,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'HarmonyOS_SansSC',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontFamily: 'HarmonyOS_SansSC',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing
              else
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

