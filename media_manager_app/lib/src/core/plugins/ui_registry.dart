import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'ui_models.dart';

/// 插件UI注册表
/// 
/// 负责加载和管理所有插件的UI配置
class PluginUIRegistry {
  static final PluginUIRegistry _instance = PluginUIRegistry._internal();
  factory PluginUIRegistry() => _instance;
  static PluginUIRegistry get instance => _instance;
  PluginUIRegistry._internal();

  final Map<String, PluginUIManifest> _manifests = {};
  final Map<String, List<UIElement>> _injectionPoints = {};
  final Map<String, UIDialog> _dialogs = {};

  /// 加载插件UI配置
  /// 
  /// [pluginId] 插件ID
  /// [manifestPath] 配置文件路径（相对于assets）
  Future<void> loadPluginUI(String pluginId, String manifestPath) async {
    try {
      print('🔌 Loading plugin UI: $pluginId from $manifestPath');
      
      // 加载YAML文件
      final yamlString = await rootBundle.loadString(manifestPath);
      
      if (yamlString.isEmpty) {
        print('⚠️ Warning: Plugin UI config file is empty: $pluginId');
        return;
      }
      
      final yamlDoc = loadYaml(yamlString);
      
      // 转换为Map
      final yamlMap = _convertYamlToMap(yamlDoc);
      
      // 验证必需字段
      if (!_validateManifestStructure(yamlMap, pluginId)) {
        print('❌ Error: Plugin UI config has missing required fields: $pluginId');
        return;
      }
      
      // 解析为Manifest对象
      final manifest = PluginUIManifest.fromYaml(yamlMap);
      _manifests[pluginId] = manifest;
      
      // 输出解析结果
      print('   Parsed ${manifest.buttons.length} button(s)');
      for (final button in manifest.buttons) {
        print('     - ${button.id} -> ${button.injectionPoint}');
      }
      print('   Parsed ${manifest.dialogs.length} dialog(s)');
      
      // 注册UI元素到注入点
      _registerUIElements(manifest);
      
      print('✅ Successfully loaded plugin UI: $pluginId');
    } on FlutterError catch (e) {
      // 文件不存在
      print('⚠️ Warning: Plugin UI config file not found: $pluginId at $manifestPath');
      print('   This plugin will not have UI elements.');
    } on YamlException catch (e) {
      // YAML格式错误
      print('❌ Error: Invalid YAML format in plugin UI config: $pluginId');
      print('   Error: $e');
    } on FormatException catch (e) {
      // 格式错误
      print('❌ Error: Invalid format in plugin UI config: $pluginId');
      print('   Error: $e');
    } catch (e, stackTrace) {
      // 其他错误
      print('❌ Error: Failed to load plugin UI: $pluginId');
      print('   Error: $e');
      if (e.toString().contains('required')) {
        print('   Hint: Check if all required fields are present in the config file');
      }
      // 只在调试模式下打印堆栈跟踪
      assert(() {
        print('   Stack trace: $stackTrace');
        return true;
      }());
    }
  }

  /// 验证manifest结构是否包含必需字段
  bool _validateManifestStructure(Map<String, dynamic> yamlMap, String pluginId) {
    // 检查顶层必需字段
    if (!yamlMap.containsKey('plugin')) {
      print('❌ Missing required field: plugin');
      return false;
    }
    if (!yamlMap.containsKey('ui_elements')) {
      print('❌ Missing required field: ui_elements');
      return false;
    }
    if (!yamlMap.containsKey('permissions')) {
      print('❌ Missing required field: permissions');
      return false;
    }
    
    // 检查plugin字段
    final plugin = yamlMap['plugin'] as Map<String, dynamic>?;
    if (plugin == null) {
      print('❌ Invalid plugin field: must be a map');
      return false;
    }
    if (!plugin.containsKey('id') || !plugin.containsKey('name') || !plugin.containsKey('version')) {
      print('❌ Missing required fields in plugin: id, name, or version');
      return false;
    }
    
    return true;
  }

  /// 将YamlMap转换为普通Map
  dynamic _convertYamlToMap(dynamic yaml) {
    if (yaml is YamlMap) {
      final map = <String, dynamic>{};
      yaml.forEach((key, value) {
        map[key.toString()] = _convertYamlToMap(value);
      });
      return map;
    } else if (yaml is YamlList) {
      return yaml.map((e) => _convertYamlToMap(e)).toList();
    } else {
      return yaml;
    }
  }

  /// 注册UI元素到注入点
  void _registerUIElements(PluginUIManifest manifest) {
    int registeredButtons = 0;
    int skippedButtons = 0;
    
    // 注册按钮
    for (final button in manifest.buttons) {
      // 检查权限
      if (!manifest.permissions.hasInjectionPointAccess(button.injectionPoint)) {
        print(
            '⚠️ Warning: Plugin ${manifest.pluginId} does not have permission to access injection point ${button.injectionPoint}');
        print('   Button "${button.id}" will not be registered');
        skippedButtons++;
        continue;
      }

      final injectionPoint = button.injectionPoint;
      _injectionPoints.putIfAbsent(injectionPoint, () => []);
      _injectionPoints[injectionPoint]!.add(button);
      registeredButtons++;
    }

    // 注册对话框（用于快速查找）
    for (final dialog in manifest.dialogs) {
      _dialogs[dialog.id] = dialog;
    }
    
    // 输出注册统计
    if (manifest.buttons.isNotEmpty) {
      print('   Registered $registeredButtons button(s), skipped $skippedButtons button(s)');
    }
    if (manifest.dialogs.isNotEmpty) {
      print('   Registered ${manifest.dialogs.length} dialog(s)');
    }
  }

  /// 获取指定注入点的UI元素
  /// 
  /// [injectionPoint] 注入点ID
  /// 返回该注入点的所有UI元素列表（已过滤权限）
  List<UIElement> getUIElements(String injectionPoint) {
    final elements = _injectionPoints[injectionPoint] ?? [];
    
    if (elements.isEmpty) {
      // 注入点不存在或没有UI元素 - 这是正常情况，不需要警告
      return [];
    }
    
    // 二次权限检查：确保返回的元素都有权限访问该注入点
    return elements.where((element) {
      // 查找该元素所属的插件
      final manifest = _findManifestForElement(element);
      if (manifest == null) {
        print('⚠️ Warning: Cannot find manifest for element ${element.id}');
        print('   This element will not be rendered');
        return false;
      }
      
      // 检查权限
      if (!manifest.permissions.hasInjectionPointAccess(injectionPoint)) {
        print(
            '⚠️ Warning: Plugin ${manifest.pluginId} does not have permission to access injection point $injectionPoint');
        print('   Element "${element.id}" will not be rendered');
        return false;
      }
      
      return true;
    }).toList();
  }

  /// 获取指定注入点的按钮
  /// 
  /// [injectionPoint] 注入点ID
  /// 返回该注入点的所有按钮列表（已过滤权限）
  List<UIButton> getButtons(String injectionPoint) {
    final elements = getUIElements(injectionPoint);
    return elements.whereType<UIButton>().toList();
  }

  /// 获取指定注入点的按钮（根据后端已安装插件过滤）
  /// 
  /// [injectionPoint] 注入点ID
  /// [installedPluginIds] 后端已安装的插件ID集合
  /// 返回该注入点中，对应后端插件已安装的按钮列表
  List<UIButton> getButtonsFiltered(String injectionPoint, Set<String> installedPluginIds) {
    final buttons = getButtons(injectionPoint);
    return buttons.where((button) {
      // 查找该按钮所属的插件
      final manifest = _findManifestForElement(button);
      if (manifest == null) return false;
      
      // 检查后端是否安装了该插件
      return installedPluginIds.contains(manifest.pluginId);
    }).toList();
  }
  
  /// 查找UI元素所属的插件清单
  /// 
  /// [element] UI元素
  /// 返回插件清单，如果找不到则返回null
  PluginUIManifest? _findManifestForElement(UIElement element) {
    for (final manifest in _manifests.values) {
      // 检查按钮
      if (manifest.buttons.any((btn) => btn.id == element.id)) {
        return manifest;
      }
    }
    return null;
  }

  /// 根据ID获取对话框
  /// 
  /// [dialogId] 对话框ID
  /// 返回对话框对象，如果不存在则返回null
  UIDialog? getDialog(String dialogId) {
    return _dialogs[dialogId];
  }

  /// 获取所有已加载的插件清单
  Map<String, PluginUIManifest> get manifests => Map.unmodifiable(_manifests);

  /// 获取指定插件的清单
  /// 
  /// [pluginId] 插件ID
  /// 返回插件清单，如果不存在则返回null
  PluginUIManifest? getManifest(String pluginId) {
    return _manifests[pluginId];
  }

  /// 清空所有注册的UI元素
  void clear() {
    _manifests.clear();
    _injectionPoints.clear();
    _dialogs.clear();
  }

  /// 卸载指定插件的UI
  /// 
  /// [pluginId] 插件ID
  void unloadPluginUI(String pluginId) {
    final manifest = _manifests.remove(pluginId);
    if (manifest == null) return;

    // 从注入点移除该插件的UI元素
    for (final button in manifest.buttons) {
      final elements = _injectionPoints[button.injectionPoint];
      if (elements != null) {
        elements.removeWhere((e) => e.id == button.id);
      }
    }

    // 移除对话框
    for (final dialog in manifest.dialogs) {
      _dialogs.remove(dialog.id);
    }

    print('Unloaded plugin UI: $pluginId');
  }

  /// 重新加载指定插件的UI
  /// 
  /// [pluginId] 插件ID
  /// [manifestPath] 配置文件路径
  Future<void> reloadPluginUI(String pluginId, String manifestPath) async {
    unloadPluginUI(pluginId);
    await loadPluginUI(pluginId, manifestPath);
  }

  /// 获取所有注入点的名称
  List<String> get injectionPoints => _injectionPoints.keys.toList();

  /// 检查指定注入点是否有UI元素
  /// 
  /// [injectionPoint] 注入点ID
  /// 返回true如果该注入点有UI元素
  bool hasUIElements(String injectionPoint) {
    final elements = _injectionPoints[injectionPoint];
    return elements != null && elements.isNotEmpty;
  }
}
