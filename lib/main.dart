import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/map/data/gpx_service.dart';
import 'features/map/data/stage_repository.dart';
import 'features/map/presentation/map_screen.dart';
import 'features/map/state/map_cubit.dart';

void main() {
  runApp(const RallyMapApp());
}

class RallyMapApp extends StatelessWidget {
  const RallyMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rally Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: BlocProvider<MapCubit>(
        create: (_) => MapCubit(
          stageRepository: StageRepository(),
          gpxCache: GpxCache(),
        ),
        child: const MapScreen(),
      ),
    );
  }
}
