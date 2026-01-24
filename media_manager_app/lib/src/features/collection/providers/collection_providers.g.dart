// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$filteredCollectionsHash() =>
    r'1b308858e854eebf8e5a61bc02d03e9cec879c81';

/// See also [filteredCollections].
@ProviderFor(filteredCollections)
final filteredCollectionsProvider =
    AutoDisposeProvider<List<Collection>>.internal(
  filteredCollections,
  name: r'filteredCollectionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$filteredCollectionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef FilteredCollectionsRef = AutoDisposeProviderRef<List<Collection>>;
String _$isInCollectionHash() => r'c9368175bd83c7b190aef755927691cd0a767df8';

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

/// See also [isInCollection].
@ProviderFor(isInCollection)
const isInCollectionProvider = IsInCollectionFamily();

/// See also [isInCollection].
class IsInCollectionFamily extends Family<bool> {
  /// See also [isInCollection].
  const IsInCollectionFamily();

  /// See also [isInCollection].
  IsInCollectionProvider call(
    String mediaId,
  ) {
    return IsInCollectionProvider(
      mediaId,
    );
  }

  @override
  IsInCollectionProvider getProviderOverride(
    covariant IsInCollectionProvider provider,
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
  String? get name => r'isInCollectionProvider';
}

/// See also [isInCollection].
class IsInCollectionProvider extends AutoDisposeProvider<bool> {
  /// See also [isInCollection].
  IsInCollectionProvider(
    String mediaId,
  ) : this._internal(
          (ref) => isInCollection(
            ref as IsInCollectionRef,
            mediaId,
          ),
          from: isInCollectionProvider,
          name: r'isInCollectionProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$isInCollectionHash,
          dependencies: IsInCollectionFamily._dependencies,
          allTransitiveDependencies:
              IsInCollectionFamily._allTransitiveDependencies,
          mediaId: mediaId,
        );

  IsInCollectionProvider._internal(
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
  Override overrideWith(
    bool Function(IsInCollectionRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: IsInCollectionProvider._internal(
        (ref) => create(ref as IsInCollectionRef),
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
  AutoDisposeProviderElement<bool> createElement() {
    return _IsInCollectionProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is IsInCollectionProvider && other.mediaId == mediaId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, mediaId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin IsInCollectionRef on AutoDisposeProviderRef<bool> {
  /// The parameter `mediaId` of this provider.
  String get mediaId;
}

class _IsInCollectionProviderElement extends AutoDisposeProviderElement<bool>
    with IsInCollectionRef {
  _IsInCollectionProviderElement(super.provider);

  @override
  String get mediaId => (origin as IsInCollectionProvider).mediaId;
}

String _$getCollectionForMediaHash() =>
    r'3c3119d644b8d54595ca025c839a88224fc488e4';

/// See also [getCollectionForMedia].
@ProviderFor(getCollectionForMedia)
const getCollectionForMediaProvider = GetCollectionForMediaFamily();

/// See also [getCollectionForMedia].
class GetCollectionForMediaFamily extends Family<Collection?> {
  /// See also [getCollectionForMedia].
  const GetCollectionForMediaFamily();

  /// See also [getCollectionForMedia].
  GetCollectionForMediaProvider call(
    String mediaId,
  ) {
    return GetCollectionForMediaProvider(
      mediaId,
    );
  }

  @override
  GetCollectionForMediaProvider getProviderOverride(
    covariant GetCollectionForMediaProvider provider,
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
  String? get name => r'getCollectionForMediaProvider';
}

/// See also [getCollectionForMedia].
class GetCollectionForMediaProvider extends AutoDisposeProvider<Collection?> {
  /// See also [getCollectionForMedia].
  GetCollectionForMediaProvider(
    String mediaId,
  ) : this._internal(
          (ref) => getCollectionForMedia(
            ref as GetCollectionForMediaRef,
            mediaId,
          ),
          from: getCollectionForMediaProvider,
          name: r'getCollectionForMediaProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$getCollectionForMediaHash,
          dependencies: GetCollectionForMediaFamily._dependencies,
          allTransitiveDependencies:
              GetCollectionForMediaFamily._allTransitiveDependencies,
          mediaId: mediaId,
        );

  GetCollectionForMediaProvider._internal(
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
  Override overrideWith(
    Collection? Function(GetCollectionForMediaRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: GetCollectionForMediaProvider._internal(
        (ref) => create(ref as GetCollectionForMediaRef),
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
  AutoDisposeProviderElement<Collection?> createElement() {
    return _GetCollectionForMediaProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is GetCollectionForMediaProvider && other.mediaId == mediaId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, mediaId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin GetCollectionForMediaRef on AutoDisposeProviderRef<Collection?> {
  /// The parameter `mediaId` of this provider.
  String get mediaId;
}

class _GetCollectionForMediaProviderElement
    extends AutoDisposeProviderElement<Collection?>
    with GetCollectionForMediaRef {
  _GetCollectionForMediaProviderElement(super.provider);

  @override
  String get mediaId => (origin as GetCollectionForMediaProvider).mediaId;
}

String _$allTagsHash() => r'c3d6523c780776582ba20ef4520168ba14ee12df';

/// See also [allTags].
@ProviderFor(allTags)
final allTagsProvider = AutoDisposeProvider<List<String>>.internal(
  allTags,
  name: r'allTagsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$allTagsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AllTagsRef = AutoDisposeProviderRef<List<String>>;
String _$collectionsByTagHash() => r'986b51f575035bf5decc5d222c54e6fae2466f00';

/// See also [collectionsByTag].
@ProviderFor(collectionsByTag)
const collectionsByTagProvider = CollectionsByTagFamily();

/// See also [collectionsByTag].
class CollectionsByTagFamily extends Family<List<Collection>> {
  /// See also [collectionsByTag].
  const CollectionsByTagFamily();

  /// See also [collectionsByTag].
  CollectionsByTagProvider call(
    String tag,
  ) {
    return CollectionsByTagProvider(
      tag,
    );
  }

  @override
  CollectionsByTagProvider getProviderOverride(
    covariant CollectionsByTagProvider provider,
  ) {
    return call(
      provider.tag,
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
  String? get name => r'collectionsByTagProvider';
}

/// See also [collectionsByTag].
class CollectionsByTagProvider extends AutoDisposeProvider<List<Collection>> {
  /// See also [collectionsByTag].
  CollectionsByTagProvider(
    String tag,
  ) : this._internal(
          (ref) => collectionsByTag(
            ref as CollectionsByTagRef,
            tag,
          ),
          from: collectionsByTagProvider,
          name: r'collectionsByTagProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$collectionsByTagHash,
          dependencies: CollectionsByTagFamily._dependencies,
          allTransitiveDependencies:
              CollectionsByTagFamily._allTransitiveDependencies,
          tag: tag,
        );

  CollectionsByTagProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.tag,
  }) : super.internal();

  final String tag;

  @override
  Override overrideWith(
    List<Collection> Function(CollectionsByTagRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: CollectionsByTagProvider._internal(
        (ref) => create(ref as CollectionsByTagRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        tag: tag,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<List<Collection>> createElement() {
    return _CollectionsByTagProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CollectionsByTagProvider && other.tag == tag;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, tag.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin CollectionsByTagRef on AutoDisposeProviderRef<List<Collection>> {
  /// The parameter `tag` of this provider.
  String get tag;
}

class _CollectionsByTagProviderElement
    extends AutoDisposeProviderElement<List<Collection>>
    with CollectionsByTagRef {
  _CollectionsByTagProviderElement(super.provider);

  @override
  String get tag => (origin as CollectionsByTagProvider).tag;
}

String _$collectionStatsHash() => r'bdb8abc6f7495da5f58dd69ade9638f2f67fb8fe';

/// See also [collectionStats].
@ProviderFor(collectionStats)
final collectionStatsProvider = AutoDisposeProvider<CollectionStats>.internal(
  collectionStats,
  name: r'collectionStatsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$collectionStatsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef CollectionStatsRef = AutoDisposeProviderRef<CollectionStats>;
String _$collectionListHash() => r'2a08890af2e3c464a529115d2b6aed1d5cbced6e';

/// See also [CollectionList].
@ProviderFor(CollectionList)
final collectionListProvider =
    AutoDisposeAsyncNotifierProvider<CollectionList, List<Collection>>.internal(
  CollectionList.new,
  name: r'collectionListProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$collectionListHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CollectionList = AutoDisposeAsyncNotifier<List<Collection>>;
String _$collectionFilterHash() => r'8eb3e97d88c5f1919a238d3a42260c66c27caaf1';

/// See also [CollectionFilter].
@ProviderFor(CollectionFilter)
final collectionFilterProvider = AutoDisposeNotifierProvider<CollectionFilter,
    CollectionFilterState>.internal(
  CollectionFilter.new,
  name: r'collectionFilterProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$collectionFilterHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CollectionFilter = AutoDisposeNotifier<CollectionFilterState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
