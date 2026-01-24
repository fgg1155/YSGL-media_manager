import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/collection/presentation/screens/collection_screen.dart';
import '../../features/media/presentation/screens/media_list_screen.dart';
import '../../features/media/presentation/screens/media_detail_screen.dart';
import '../../features/media/presentation/screens/media_edit_screen.dart';
import '../../features/media/presentation/screens/filter_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/actors/presentation/screens/actor_list_screen.dart';
import '../../features/actors/presentation/screens/actor_detail_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/collection',
        name: 'collection',
        builder: (context, state) => const CollectionScreen(),
      ),
      GoRoute(
        path: '/filter',
        name: 'filter',
        builder: (context, state) => const FilterScreen(),
      ),
      GoRoute(
        path: '/media',
        name: 'media_list',
        builder: (context, state) => const MediaListScreen(),
      ),
      GoRoute(
        path: '/media/new',
        name: 'media_create',
        builder: (context, state) => const MediaEditScreen(mediaId: null),
      ),
      GoRoute(
        path: '/media/:id',
        name: 'media_detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return MediaDetailScreen(mediaId: id);
        },
      ),
      GoRoute(
        path: '/media/:id/edit',
        name: 'media_edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return MediaEditScreen(mediaId: id);
        },
      ),
      GoRoute(
        path: '/actors',
        name: 'actor_list',
        builder: (context, state) => const ActorListScreen(),
      ),
      GoRoute(
        path: '/actors/:id',
        name: 'actor_detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ActorDetailScreen(actorId: id);
        },
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (context, state) {
          final query = state.uri.queryParameters['query'];
          return SearchScreen(initialQuery: query);
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});