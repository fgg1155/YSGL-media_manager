/// UI元素数据模型
/// 
/// 定义插件UI配置的所有数据结构

/// 本地化辅助函数 - 智能匹配语言代码
String _getLocalizedString(Map<String, String> textMap, String locale) {
  // 直接匹配
  if (textMap.containsKey(locale)) {
    return textMap[locale]!;
  }
  
  // 提取语言代码（zh-CN -> zh, zh-Hans -> zh, en-US -> en）
  final languageCode = locale.split('-').first.split('_').first;
  if (textMap.containsKey(languageCode)) {
    return textMap[languageCode]!;
  }
  
  // Fallback到英文
  if (textMap.containsKey('en')) {
    return textMap['en']!;
  }
  
  // 最后返回第一个可用的值
  return textMap.values.first;
}

/// UI元素基类
abstract class UIElement {
  final String id;
  final String injectionPoint;

  UIElement({
    required this.id,
    required this.injectionPoint,
  });
}

/// 按钮元素
class UIButton extends UIElement {
  final String icon;
  final Map<String, String>? label;
  final Map<String, String>? tooltip;
  final UIAction action;

  UIButton({
    required String id,
    required String injectionPoint,
    required this.icon,
    this.label,
    this.tooltip,
    required this.action,
  }) : super(id: id, injectionPoint: injectionPoint);

  factory UIButton.fromYaml(Map<String, dynamic> yaml) {
    return UIButton(
      id: yaml['id'] as String,
      injectionPoint: yaml['injection_point'] as String,
      icon: yaml['icon'] as String,
      label: yaml['label'] != null
          ? Map<String, String>.from(yaml['label'] as Map)
          : null,
      tooltip: yaml['tooltip'] != null
          ? Map<String, String>.from(yaml['tooltip'] as Map)
          : null,
      action: UIAction.fromYaml(yaml['action'] as Map<String, dynamic>),
    );
  }

  /// 获取本地化文本
  String getLocalizedText(Map<String, String>? textMap, String locale) {
    if (textMap == null) return '';
    return _getLocalizedString(textMap, locale);
  }
}

/// 对话框元素
class UIDialog {
  final String id;
  final Map<String, String> title;
  final List<UIField> fields;
  final List<UIDialogAction> actions;

  UIDialog({
    required this.id,
    required this.title,
    required this.fields,
    required this.actions,
  });

  factory UIDialog.fromYaml(Map<String, dynamic> yaml) {
    return UIDialog(
      id: yaml['id'] as String,
      title: Map<String, String>.from(yaml['title'] as Map),
      fields: (yaml['fields'] as List<dynamic>)
          .map((f) => UIField.fromYaml(f as Map<String, dynamic>))
          .toList(),
      actions: (yaml['actions'] as List<dynamic>)
          .map((a) => UIDialogAction.fromYaml(a as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取本地化标题
  String getLocalizedTitle(String locale) {
    return _getLocalizedString(title, locale);
  }
}

/// 表单字段
class UIField {
  final String id;
  final String type; // text, radio, checkbox, dropdown, number, date
  final Map<String, String> label;
  final Map<String, String>? hint;
  final bool required;
  final dynamic defaultValue;
  final List<UIFieldOption>? options;

  UIField({
    required this.id,
    required this.type,
    required this.label,
    this.hint,
    this.required = false,
    this.defaultValue,
    this.options,
  });

  factory UIField.fromYaml(Map<String, dynamic> yaml) {
    return UIField(
      id: yaml['id'] as String,
      type: yaml['type'] as String,
      label: Map<String, String>.from(yaml['label'] as Map),
      hint: yaml['hint'] != null
          ? Map<String, String>.from(yaml['hint'] as Map)
          : null,
      required: yaml['required'] as bool? ?? false,
      defaultValue: yaml['default'],
      options: yaml['options'] != null
          ? (yaml['options'] as List<dynamic>)
              .map((o) => UIFieldOption.fromYaml(o as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  /// 获取本地化标签
  String getLocalizedLabel(String locale) {
    return _getLocalizedString(label, locale);
  }

  /// 获取本地化提示
  String? getLocalizedHint(String locale) {
    if (hint == null) return null;
    return _getLocalizedString(hint!, locale);
  }
}

/// 字段选项
class UIFieldOption {
  final String value;
  final Map<String, String> label;

  UIFieldOption({
    required this.value,
    required this.label,
  });

  factory UIFieldOption.fromYaml(Map<String, dynamic> yaml) {
    return UIFieldOption(
      value: yaml['value'] as String,
      label: Map<String, String>.from(yaml['label'] as Map),
    );
  }

  /// 获取本地化标签
  String getLocalizedLabel(String locale) {
    return _getLocalizedString(label, locale);
  }
}

/// UI动作
class UIAction {
  final String type; // show_dialog, call_api, close
  final String? dialogId;
  final String? apiEndpoint;
  final String? method;
  final Map<String, dynamic>? body; // 固定的请求体参数
  final List<APIParam>? params;
  final bool showProgress;
  final Map<String, String>? progressMessage;
  final Map<String, String>? successMessage;
  final Map<String, String>? errorMessage;
  final String? onSuccess; // refresh_page, close, show_results

  UIAction({
    required this.type,
    this.dialogId,
    this.apiEndpoint,
    this.method,
    this.body,
    this.params,
    this.showProgress = false,
    this.progressMessage,
    this.successMessage,
    this.errorMessage,
    this.onSuccess,
  });

  factory UIAction.fromYaml(Map<String, dynamic> yaml) {
    return UIAction(
      type: yaml['type'] as String,
      dialogId: yaml['dialog_id'] as String?,
      apiEndpoint: yaml['api_endpoint'] as String?,
      method: yaml['method'] as String? ?? 'GET',
      body: yaml['body'] as Map<String, dynamic>?,
      params: yaml['params'] != null
          ? (yaml['params'] as List<dynamic>)
              .map((p) => APIParam.fromYaml(p as Map<String, dynamic>))
              .toList()
          : null,
      showProgress: yaml['show_progress'] as bool? ?? false,
      progressMessage: yaml['progress_message'] != null
          ? Map<String, String>.from(yaml['progress_message'] as Map)
          : null,
      successMessage: yaml['success_message'] != null
          ? Map<String, String>.from(yaml['success_message'] as Map)
          : null,
      errorMessage: yaml['error_message'] != null
          ? Map<String, String>.from(yaml['error_message'] as Map)
          : null,
      onSuccess: yaml['on_success'] as String?,
    );
  }

  /// 获取本地化消息
  String? getLocalizedMessage(
      Map<String, String>? messageMap, String locale) {
    if (messageMap == null) return null;
    return _getLocalizedString(messageMap, locale);
  }
}

/// API参数
class APIParam {
  final String field; // 表单字段ID
  final String param; // API参数名

  APIParam({
    required this.field,
    required this.param,
  });

  factory APIParam.fromYaml(Map<String, dynamic> yaml) {
    return APIParam(
      field: yaml['field'] as String,
      param: yaml['param'] as String,
    );
  }
}

/// 对话框动作
class UIDialogAction {
  final String id;
  final Map<String, String> label;
  final String type; // call_api, close
  final String? apiEndpoint;
  final String? method;
  final Map<String, dynamic>? body; // 固定的请求体参数
  final List<APIParam>? params;
  final bool showProgress;
  final Map<String, String>? progressMessage;
  final Map<String, String>? successMessage;
  final Map<String, String>? errorMessage;
  final String? onSuccess;

  UIDialogAction({
    required this.id,
    required this.label,
    required this.type,
    this.apiEndpoint,
    this.method,
    this.body,
    this.params,
    this.showProgress = false,
    this.progressMessage,
    this.successMessage,
    this.errorMessage,
    this.onSuccess,
  });

  factory UIDialogAction.fromYaml(Map<String, dynamic> yaml) {
    return UIDialogAction(
      id: yaml['id'] as String,
      label: Map<String, String>.from(yaml['label'] as Map),
      type: yaml['type'] as String,
      apiEndpoint: yaml['api_endpoint'] as String?,
      method: yaml['method'] as String? ?? 'POST',
      body: yaml['body'] as Map<String, dynamic>?,
      params: yaml['params'] != null
          ? (yaml['params'] as List<dynamic>)
              .map((p) => APIParam.fromYaml(p as Map<String, dynamic>))
              .toList()
          : null,
      showProgress: yaml['show_progress'] as bool? ?? false,
      progressMessage: yaml['progress_message'] != null
          ? Map<String, String>.from(yaml['progress_message'] as Map)
          : null,
      successMessage: yaml['success_message'] != null
          ? Map<String, String>.from(yaml['success_message'] as Map)
          : null,
      errorMessage: yaml['error_message'] != null
          ? Map<String, String>.from(yaml['error_message'] as Map)
          : null,
      onSuccess: yaml['on_success'] as String?,
    );
  }

  /// 获取本地化标签
  String getLocalizedLabel(String locale) {
    return _getLocalizedString(label, locale);
  }

  /// 获取本地化消息
  String? getLocalizedMessage(
      Map<String, String>? messageMap, String locale) {
    if (messageMap == null) return null;
    return _getLocalizedString(messageMap, locale);
  }
}

/// 插件UI清单
class PluginUIManifest {
  final String pluginId;
  final String name;
  final String version;
  final String? description;
  final List<UIButton> buttons;
  final List<UIDialog> dialogs;
  final PluginPermissions permissions;

  PluginUIManifest({
    required this.pluginId,
    required this.name,
    required this.version,
    this.description,
    required this.buttons,
    required this.dialogs,
    required this.permissions,
  });

  factory PluginUIManifest.fromYaml(Map<String, dynamic> yaml) {
    final plugin = yaml['plugin'] as Map<String, dynamic>;
    final uiElements = yaml['ui_elements'] as Map<String, dynamic>;
    final permissions = yaml['permissions'] as Map<String, dynamic>;

    return PluginUIManifest(
      pluginId: plugin['id'] as String,
      name: plugin['name'] as String,
      version: plugin['version'] as String,
      description: plugin['description'] as String?,
      buttons: (uiElements['buttons'] as List<dynamic>?)
              ?.map((b) => UIButton.fromYaml(b as Map<String, dynamic>))
              .toList() ??
          [],
      dialogs: (uiElements['dialogs'] as List<dynamic>?)
              ?.map((d) => UIDialog.fromYaml(d as Map<String, dynamic>))
              .toList() ??
          [],
      permissions: PluginPermissions.fromYaml(permissions),
    );
  }
}

/// 插件权限
class PluginPermissions {
  final List<String> injectionPoints;
  final List<String> apiAccess;
  final List<String> dataAccess;

  PluginPermissions({
    required this.injectionPoints,
    required this.apiAccess,
    required this.dataAccess,
  });

  factory PluginPermissions.fromYaml(Map<String, dynamic> yaml) {
    return PluginPermissions(
      injectionPoints: (yaml['injection_points'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      apiAccess: (yaml['api_access'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      dataAccess: (yaml['data_access'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  /// 检查是否有访问指定注入点的权限
  bool hasInjectionPointAccess(String injectionPoint) {
    return injectionPoints.contains(injectionPoint);
  }

  /// 检查是否有访问指定API的权限
  bool hasApiAccess(String apiPath) {
    for (final pattern in apiAccess) {
      if (pattern.contains('*')) {
        // 通配符匹配 - 支持 /api/scrape/* 和 /api/actors/*/scrape 等格式
        final regexPattern = pattern
            .replaceAll('/', r'\/')
            .replaceAll('*', '.*');
        final regex = RegExp('^$regexPattern\$');
        if (regex.hasMatch(apiPath)) {
          return true;
        }
      } else if (pattern == apiPath) {
        return true;
      }
    }
    return false;
  }

  /// 检查是否有访问指定数据的权限
  bool hasDataAccess(String dataKey) {
    return dataAccess.contains(dataKey);
  }
}
