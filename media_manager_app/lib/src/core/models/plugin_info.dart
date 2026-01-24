/// 刮削插件信息模型
class PluginInfo {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? author;
  final List<String> idPatterns;
  final bool supportsSearch;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.author,
    this.idPatterns = const [],
    this.supportsSearch = false,
  });

  factory PluginInfo.fromJson(Map<String, dynamic> json) => PluginInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        description: json['description'] as String?,
        author: json['author'] as String?,
        idPatterns: (json['id_patterns'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        supportsSearch: json['supports_search'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        if (description != null) 'description': description,
        if (author != null) 'author': author,
        'id_patterns': idPatterns,
        'supports_search': supportsSearch,
      };
}
