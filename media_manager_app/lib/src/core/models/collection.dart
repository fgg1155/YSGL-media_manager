import 'package:json_annotation/json_annotation.dart';

part 'collection.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Collection {
  final String id;
  final String mediaId;
  final List<String> userTags;
  final double? personalRating;
  final WatchStatus watchStatus;
  final double? watchProgress;
  final String? notes;
  final bool isFavorite;
  final DateTime addedAt;
  final DateTime? lastWatched;
  final DateTime? completedAt;

  const Collection({
    required this.id,
    required this.mediaId,
    this.userTags = const [],
    this.personalRating,
    required this.watchStatus,
    this.watchProgress,
    this.notes,
    this.isFavorite = false,
    required this.addedAt,
    this.lastWatched,
    this.completedAt,
  });

  factory Collection.fromJson(Map<String, dynamic> json) =>
      _$CollectionFromJson(json);

  Map<String, dynamic> toJson() => _$CollectionToJson(this);

  String get statusDisplay {
    switch (watchStatus) {
      case WatchStatus.wantToWatch:
        return 'Want to Watch';
      case WatchStatus.watching:
        return 'Watching';
      case WatchStatus.completed:
        return 'Completed';
      case WatchStatus.onHold:
        return 'On Hold';
      case WatchStatus.dropped:
        return 'Dropped';
    }
  }

  String get ratingDisplay {
    return personalRating != null 
        ? '${personalRating!.toStringAsFixed(1)}/10' 
        : 'Not rated';
  }

  int get progressPercentage {
    return watchProgress != null 
        ? (watchProgress! * 100).round() 
        : 0;
  }

  bool get isCompleted => watchStatus == WatchStatus.completed;
  bool get isWatching => watchStatus == WatchStatus.watching;

  Collection copyWith({
    String? id,
    String? mediaId,
    List<String>? userTags,
    Object? personalRating = const _Undefined(),
    WatchStatus? watchStatus,
    Object? watchProgress = const _Undefined(),
    Object? notes = const _Undefined(),
    bool? isFavorite,
    DateTime? addedAt,
    Object? lastWatched = const _Undefined(),
    Object? completedAt = const _Undefined(),
  }) {
    return Collection(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      userTags: userTags ?? this.userTags,
      personalRating: personalRating is _Undefined ? this.personalRating : personalRating as double?,
      watchStatus: watchStatus ?? this.watchStatus,
      watchProgress: watchProgress is _Undefined ? this.watchProgress : watchProgress as double?,
      notes: notes is _Undefined ? this.notes : notes as String?,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: addedAt ?? this.addedAt,
      lastWatched: lastWatched is _Undefined ? this.lastWatched : lastWatched as DateTime?,
      completedAt: completedAt is _Undefined ? this.completedAt : completedAt as DateTime?,
    );
  }
}

// 用于区分"未传值"和"传入 null"的辅助类
class _Undefined {
  const _Undefined();
}

@JsonEnum()
enum WatchStatus {
  @JsonValue('WantToWatch')
  wantToWatch,
  @JsonValue('Watching')
  watching,
  @JsonValue('Completed')
  completed,
  @JsonValue('OnHold')
  onHold,
  @JsonValue('Dropped')
  dropped,
}