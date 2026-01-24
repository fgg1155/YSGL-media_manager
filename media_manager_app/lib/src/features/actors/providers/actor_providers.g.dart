// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'actor_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$actorMediaListHash() => r'f89b0e897eb00c80812c1d9514da8cfd218671fd';

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

/// 演员的媒体作品列表
///
/// Copied from [actorMediaList].
@ProviderFor(actorMediaList)
const actorMediaListProvider = ActorMediaListFamily();

/// 演员的媒体作品列表
///
/// Copied from [actorMediaList].
class ActorMediaListFamily extends Family<AsyncValue<List<MediaItem>>> {
  /// 演员的媒体作品列表
  ///
  /// Copied from [actorMediaList].
  const ActorMediaListFamily();

  /// 演员的媒体作品列表
  ///
  /// Copied from [actorMediaList].
  ActorMediaListProvider call(
    String actorId,
  ) {
    return ActorMediaListProvider(
      actorId,
    );
  }

  @override
  ActorMediaListProvider getProviderOverride(
    covariant ActorMediaListProvider provider,
  ) {
    return call(
      provider.actorId,
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
  String? get name => r'actorMediaListProvider';
}

/// 演员的媒体作品列表
///
/// Copied from [actorMediaList].
class ActorMediaListProvider
    extends AutoDisposeFutureProvider<List<MediaItem>> {
  /// 演员的媒体作品列表
  ///
  /// Copied from [actorMediaList].
  ActorMediaListProvider(
    String actorId,
  ) : this._internal(
          (ref) => actorMediaList(
            ref as ActorMediaListRef,
            actorId,
          ),
          from: actorMediaListProvider,
          name: r'actorMediaListProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$actorMediaListHash,
          dependencies: ActorMediaListFamily._dependencies,
          allTransitiveDependencies:
              ActorMediaListFamily._allTransitiveDependencies,
          actorId: actorId,
        );

  ActorMediaListProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.actorId,
  }) : super.internal();

  final String actorId;

  @override
  Override overrideWith(
    FutureOr<List<MediaItem>> Function(ActorMediaListRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ActorMediaListProvider._internal(
        (ref) => create(ref as ActorMediaListRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        actorId: actorId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<MediaItem>> createElement() {
    return _ActorMediaListProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ActorMediaListProvider && other.actorId == actorId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, actorId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin ActorMediaListRef on AutoDisposeFutureProviderRef<List<MediaItem>> {
  /// The parameter `actorId` of this provider.
  String get actorId;
}

class _ActorMediaListProviderElement
    extends AutoDisposeFutureProviderElement<List<MediaItem>>
    with ActorMediaListRef {
  _ActorMediaListProviderElement(super.provider);

  @override
  String get actorId => (origin as ActorMediaListProvider).actorId;
}

String _$mediaActorListHash() => r'375695a73a4e3aea648d65339f734753ca829509';

/// 媒体的演员列表
///
/// Copied from [mediaActorList].
@ProviderFor(mediaActorList)
const mediaActorListProvider = MediaActorListFamily();

/// 媒体的演员列表
///
/// Copied from [mediaActorList].
class MediaActorListFamily extends Family<AsyncValue<List<Actor>>> {
  /// 媒体的演员列表
  ///
  /// Copied from [mediaActorList].
  const MediaActorListFamily();

  /// 媒体的演员列表
  ///
  /// Copied from [mediaActorList].
  MediaActorListProvider call(
    String mediaId,
  ) {
    return MediaActorListProvider(
      mediaId,
    );
  }

  @override
  MediaActorListProvider getProviderOverride(
    covariant MediaActorListProvider provider,
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
  String? get name => r'mediaActorListProvider';
}

/// 媒体的演员列表
///
/// Copied from [mediaActorList].
class MediaActorListProvider extends AutoDisposeFutureProvider<List<Actor>> {
  /// 媒体的演员列表
  ///
  /// Copied from [mediaActorList].
  MediaActorListProvider(
    String mediaId,
  ) : this._internal(
          (ref) => mediaActorList(
            ref as MediaActorListRef,
            mediaId,
          ),
          from: mediaActorListProvider,
          name: r'mediaActorListProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$mediaActorListHash,
          dependencies: MediaActorListFamily._dependencies,
          allTransitiveDependencies:
              MediaActorListFamily._allTransitiveDependencies,
          mediaId: mediaId,
        );

  MediaActorListProvider._internal(
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
    FutureOr<List<Actor>> Function(MediaActorListRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: MediaActorListProvider._internal(
        (ref) => create(ref as MediaActorListRef),
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
  AutoDisposeFutureProviderElement<List<Actor>> createElement() {
    return _MediaActorListProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is MediaActorListProvider && other.mediaId == mediaId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, mediaId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin MediaActorListRef on AutoDisposeFutureProviderRef<List<Actor>> {
  /// The parameter `mediaId` of this provider.
  String get mediaId;
}

class _MediaActorListProviderElement
    extends AutoDisposeFutureProviderElement<List<Actor>>
    with MediaActorListRef {
  _MediaActorListProviderElement(super.provider);

  @override
  String get mediaId => (origin as MediaActorListProvider).mediaId;
}

String _$actorListHash() => r'2cdf35bc6ee2f974cf1b036a415e5bce410cda1c';

/// 演员列表状态
///
/// Copied from [ActorList].
@ProviderFor(ActorList)
final actorListProvider =
    AutoDisposeAsyncNotifierProvider<ActorList, List<Actor>>.internal(
  ActorList.new,
  name: r'actorListProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$actorListHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ActorList = AutoDisposeAsyncNotifier<List<Actor>>;
String _$actorDetailHash() => r'5bcfa9c5397af07f77dbd6710c6d100a6ce8d507';

abstract class _$ActorDetail extends BuildlessAutoDisposeAsyncNotifier<Actor?> {
  late final String actorId;

  FutureOr<Actor?> build(
    String actorId,
  );
}

/// 演员详情状态
///
/// Copied from [ActorDetail].
@ProviderFor(ActorDetail)
const actorDetailProvider = ActorDetailFamily();

/// 演员详情状态
///
/// Copied from [ActorDetail].
class ActorDetailFamily extends Family<AsyncValue<Actor?>> {
  /// 演员详情状态
  ///
  /// Copied from [ActorDetail].
  const ActorDetailFamily();

  /// 演员详情状态
  ///
  /// Copied from [ActorDetail].
  ActorDetailProvider call(
    String actorId,
  ) {
    return ActorDetailProvider(
      actorId,
    );
  }

  @override
  ActorDetailProvider getProviderOverride(
    covariant ActorDetailProvider provider,
  ) {
    return call(
      provider.actorId,
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
  String? get name => r'actorDetailProvider';
}

/// 演员详情状态
///
/// Copied from [ActorDetail].
class ActorDetailProvider
    extends AutoDisposeAsyncNotifierProviderImpl<ActorDetail, Actor?> {
  /// 演员详情状态
  ///
  /// Copied from [ActorDetail].
  ActorDetailProvider(
    String actorId,
  ) : this._internal(
          () => ActorDetail()..actorId = actorId,
          from: actorDetailProvider,
          name: r'actorDetailProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$actorDetailHash,
          dependencies: ActorDetailFamily._dependencies,
          allTransitiveDependencies:
              ActorDetailFamily._allTransitiveDependencies,
          actorId: actorId,
        );

  ActorDetailProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.actorId,
  }) : super.internal();

  final String actorId;

  @override
  FutureOr<Actor?> runNotifierBuild(
    covariant ActorDetail notifier,
  ) {
    return notifier.build(
      actorId,
    );
  }

  @override
  Override overrideWith(ActorDetail Function() create) {
    return ProviderOverride(
      origin: this,
      override: ActorDetailProvider._internal(
        () => create()..actorId = actorId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        actorId: actorId,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<ActorDetail, Actor?> createElement() {
    return _ActorDetailProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ActorDetailProvider && other.actorId == actorId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, actorId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin ActorDetailRef on AutoDisposeAsyncNotifierProviderRef<Actor?> {
  /// The parameter `actorId` of this provider.
  String get actorId;
}

class _ActorDetailProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<ActorDetail, Actor?>
    with ActorDetailRef {
  _ActorDetailProviderElement(super.provider);

  @override
  String get actorId => (origin as ActorDetailProvider).actorId;
}

String _$actorMutationHash() => r'5620c7bc4217c6215bdc9c0ae4d6e82fffa6ad9f';

/// 创建/更新演员
///
/// Copied from [ActorMutation].
@ProviderFor(ActorMutation)
final actorMutationProvider =
    AutoDisposeNotifierProvider<ActorMutation, AsyncValue<Actor?>>.internal(
  ActorMutation.new,
  name: r'actorMutationProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$actorMutationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ActorMutation = AutoDisposeNotifier<AsyncValue<Actor?>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
