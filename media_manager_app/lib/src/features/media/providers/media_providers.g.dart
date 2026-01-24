// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$mediaListHash() => r'eaec9c45253ef4ca6270fa066423e4f4b8192db0';

/// See also [MediaList].
@ProviderFor(MediaList)
final mediaListProvider =
    AutoDisposeAsyncNotifierProvider<MediaList, List<MediaItem>>.internal(
  MediaList.new,
  name: r'mediaListProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$mediaListHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$MediaList = AutoDisposeAsyncNotifier<List<MediaItem>>;
String _$mediaDetailHash() => r'2d659603bc290bad8434b9230ef450e0bcacf804';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$MediaDetail
    extends BuildlessAutoDisposeAsyncNotifier<MediaItem?> {
  late final String mediaId;

  FutureOr<MediaItem?> build(
    String mediaId,
  );
}

/// See also [MediaDetail].
@ProviderFor(MediaDetail)
const mediaDetailProvider = MediaDetailFamily();

/// See also [MediaDetail].
class MediaDetailFamily extends Family<AsyncValue<MediaItem?>> {
  /// See also [MediaDetail].
  const MediaDetailFamily();

  /// See also [MediaDetail].
  MediaDetailProvider call(
    String mediaId,
  ) {
    return MediaDetailProvider(
      mediaId,
    );
  }

  @override
  MediaDetailProvider getProviderOverride(
    covariant MediaDetailProvider provider,
  ) {
    return call(
      provider.mediaId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'mediaDetailProvider';
}

/// See also [MediaDetail].
class MediaDetailProvider
    extends AutoDisposeAsyncNotifierProviderImpl<MediaDetail, MediaItem?> {
  /// See also [MediaDetail].
  MediaDetailProvider(
    String mediaId,
  ) : this._internal(
          () => MediaDetail()..mediaId = mediaId,
          from: mediaDetailProvider,
          name: r'mediaDetailProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$mediaDetailHash,
          dependencies: MediaDetailFamily._dependencies,
          allTransitiveDependencies:
              MediaDetailFamily._allTransitiveDependencies,
          mediaId: mediaId,
        );

  MediaDetailProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.mediaId,
  }) : super.internal();

  final String mediaId;

  @override
  FutureOr<MediaItem?> runNotifierBuild(
    covariant MediaDetail notifier,
  ) {
    return notifier.build(
      mediaId,
    );
  }

  @override
  Override overrideWith(MediaDetail Function() create) {
    return ProviderOverride(
      origin: this,
      override: MediaDetailProvider._internal(
        () => create()..mediaId = mediaId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        mediaId: mediaId,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<MediaDetail, MediaItem?>
      createElement() {
    return _MediaDetailProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is MediaDetailProvider && other.mediaId == mediaId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, mediaId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin MediaDetailRef on AutoDisposeAsyncNotifierProviderRef<MediaItem?> {
  /// The parameter `mediaId` of this provider.
  String get mediaId;
}

class _MediaDetailProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<MediaDetail, MediaItem?>
    with MediaDetailRef {
  _MediaDetailProviderElement(super.provider);

  @override
  String get mediaId => (origin as MediaDetailProvider).mediaId;
}

String _$popularContentHash() => r'8e96168fc7e5aceeb3e3115c9f7b7ed188e798b0';

abstract class _$PopularContent
    extends BuildlessAutoDisposeAsyncNotifier<List<MediaItem>> {
  late final String mediaType;

  FutureOr<List<MediaItem>> build({
    String mediaType = 'movie',
  });
}

/// See also [PopularContent].
@ProviderFor(PopularContent)
const popularContentProvider = PopularContentFamily();

/// See also [PopularContent].
class PopularContentFamily extends Family<AsyncValue<List<MediaItem>>> {
  /// See also [PopularContent].
  const PopularContentFamily();

  /// See also [PopularContent].
  PopularContentProvider call({
    String mediaType = 'movie',
  }) {
    return PopularContentProvider(
      mediaType: mediaType,
    );
  }

  @override
  PopularContentProvider getProviderOverride(
    covariant PopularContentProvider provider,
  ) {
    return call(
      mediaType: provider.mediaType,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'popularContentProvider';
}

/// See also [PopularContent].
class PopularContentProvider extends AutoDisposeAsyncNotifierProviderImpl<
    PopularContent, List<MediaItem>> {
  /// See also [PopularContent].
  PopularContentProvider({
    String mediaType = 'movie',
  }) : this._internal(
          () => PopularContent()..mediaType = mediaType,
          from: popularContentProvider,
          name: r'popularContentProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$popularContentHash,
          dependencies: PopularContentFamily._dependencies,
          allTransitiveDependencies:
              PopularContentFamily._allTransitiveDependencies,
          mediaType: mediaType,
        );

  PopularContentProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.mediaType,
  }) : super.internal();

  final String mediaType;

  @override
  FutureOr<List<MediaItem>> runNotifierBuild(
    covariant PopularContent notifier,
  ) {
    return notifier.build(
      mediaType: mediaType,
    );
  }

  @override
  Override overrideWith(PopularContent Function() create) {
    return ProviderOverride(
      origin: this,
      override: PopularContentProvider._internal(
        () => create()..mediaType = mediaType,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        mediaType: mediaType,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<PopularContent, List<MediaItem>>
      createElement() {
    return _PopularContentProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PopularContentProvider && other.mediaType == mediaType;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, mediaType.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin PopularContentRef
    on AutoDisposeAsyncNotifierProviderRef<List<MediaItem>> {
  /// The parameter `mediaType` of this provider.
  String get mediaType;
}

class _PopularContentProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<PopularContent,
        List<MediaItem>> with PopularContentRef {
  _PopularContentProviderElement(super.provider);

  @override
  String get mediaType => (origin as PopularContentProvider).mediaType;
}

String _$tmdbDetailsHash() => r'f69038345002104ec8da3f288ae0e13776625de6';

abstract class _$TmdbDetails
    extends BuildlessAutoDisposeAsyncNotifier<MediaItem?> {
  late final int tmdbId;
  late final String mediaType;

  FutureOr<MediaItem?> build({
    required int tmdbId,
    required String mediaType,
  });
}

/// See also [TmdbDetails].
@ProviderFor(TmdbDetails)
const tmdbDetailsProvider = TmdbDetailsFamily();

/// See also [TmdbDetails].
class TmdbDetailsFamily extends Family<AsyncValue<MediaItem?>> {
  /// See also [TmdbDetails].
  const TmdbDetailsFamily();

  /// See also [TmdbDetails].
  TmdbDetailsProvider call({
    required int tmdbId,
    required String mediaType,
  }) {
    return TmdbDetailsProvider(
      tmdbId: tmdbId,
      mediaType: mediaType,
    );
  }

  @override
  TmdbDetailsProvider getProviderOverride(
    covariant TmdbDetailsProvider provider,
  ) {
    return call(
      tmdbId: provider.tmdbId,
      mediaType: provider.mediaType,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'tmdbDetailsProvider';
}

/// See also [TmdbDetails].
class TmdbDetailsProvider
    extends AutoDisposeAsyncNotifierProviderImpl<TmdbDetails, MediaItem?> {
  /// See also [TmdbDetails].
  TmdbDetailsProvider({
    required int tmdbId,
    required String mediaType,
  }) : this._internal(
          () => TmdbDetails()
            ..tmdbId = tmdbId
            ..mediaType = mediaType,
          from: tmdbDetailsProvider,
          name: r'tmdbDetailsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$tmdbDetailsHash,
          dependencies: TmdbDetailsFamily._dependencies,
          allTransitiveDependencies:
              TmdbDetailsFamily._allTransitiveDependencies,
          tmdbId: tmdbId,
          mediaType: mediaType,
        );

  TmdbDetailsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.tmdbId,
    required this.mediaType,
  }) : super.internal();

  final int tmdbId;
  final String mediaType;

  @override
  FutureOr<MediaItem?> runNotifierBuild(
    covariant TmdbDetails notifier,
  ) {
    return notifier.build(
      tmdbId: tmdbId,
      mediaType: mediaType,
    );
  }

  @override
  Override overrideWith(TmdbDetails Function() create) {
    return ProviderOverride(
      origin: this,
      override: TmdbDetailsProvider._internal(
        () => create()
          ..tmdbId = tmdbId
          ..mediaType = mediaType,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        tmdbId: tmdbId,
        mediaType: mediaType,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<TmdbDetails, MediaItem?>
      createElement() {
    return _TmdbDetailsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is TmdbDetailsProvider &&
        other.tmdbId == tmdbId &&
        other.mediaType == mediaType;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, tmdbId.hashCode);
    hash = _SystemHash.combine(hash, mediaType.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin TmdbDetailsRef on AutoDisposeAsyncNotifierProviderRef<MediaItem?> {
  /// The parameter `tmdbId` of this provider.
  int get tmdbId;

  /// The parameter `mediaType` of this provider.
  String get mediaType;
}

class _TmdbDetailsProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<TmdbDetails, MediaItem?>
    with TmdbDetailsRef {
  _TmdbDetailsProviderElement(super.provider);

  @override
  int get tmdbId => (origin as TmdbDetailsProvider).tmdbId;
  @override
  String get mediaType => (origin as TmdbDetailsProvider).mediaType;
}

String _$mediaFiltersHash() => r'03d3386fab6ef0d01ed08f60b84c08115b28d5c6';

/// See also [MediaFilters].
@ProviderFor(MediaFilters)
final mediaFiltersProvider =
    AutoDisposeNotifierProvider<MediaFilters, MediaFiltersState>.internal(
  MediaFilters.new,
  name: r'mediaFiltersProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$mediaFiltersHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$MediaFilters = AutoDisposeNotifier<MediaFiltersState>;
String _$filterOptionsNotifierHash() =>
    r'6171ce01559b53c388e1bf8fb4251fe3c7d210e5';

/// 筛选选项 Provider - 使用 Repository（支持独立模式和 PC 模式）
///
/// Copied from [FilterOptionsNotifier].
@ProviderFor(FilterOptionsNotifier)
final filterOptionsNotifierProvider = AutoDisposeAsyncNotifierProvider<
    FilterOptionsNotifier, FilterOptions>.internal(
  FilterOptionsNotifier.new,
  name: r'filterOptionsNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$filterOptionsNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$FilterOptionsNotifier = AutoDisposeAsyncNotifier<FilterOptions>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
