import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/bus_provider.dart';
import '../services/kml_service.dart';
import 'line_detail_screen.dart';
import 'stop_walking_map_screen.dart';

class NearbyLinesScreen extends StatefulWidget {
  final Position? initialPosition;

  const NearbyLinesScreen({super.key, this.initialPosition});

  @override
  State<NearbyLinesScreen> createState() => _NearbyLinesScreenState();
}

class _NearbyLinesScreenState extends State<NearbyLinesScreen> {
  static const double _radiusMeters = 200;

  final KmlService _kmlService = KmlService();
  Position? _position;
  List<StopInfo> _nearbyStops = [];
  List<_NearbyLine> _nearbyLines = [];
  bool _loadingNearby = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScreenData();
    });
  }

  Future<void> _loadScreenData() async {
    final provider = Provider.of<BusProvider>(context, listen: false);
    setState(() {
      _loadingNearby = true;
      _message = null;
    });

    try {
      _position = widget.initialPosition ?? await _getCurrentPosition();
      if (_position == null) {
        setState(() {
          _message = 'Nao foi possivel obter sua localizacao.';
          _loadingNearby = false;
        });
        return;
      }

      provider.fetchLinhas().then((_) {
        if (mounted) setState(() {});
      });

      final stops = await _kmlService.findStopsNearLocation(
        _position!.latitude,
        _position!.longitude,
        radiusMeters: _radiusMeters,
      );

      if (!mounted) return;
      setState(() {
        _nearbyStops = stops;
        _nearbyLines = _groupStopsByLine(stops);
        _loadingNearby = false;
        if (stops.isEmpty) {
          _message = 'Nenhuma parada encontrada em ate 200 metros.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Erro ao carregar linhas proximas.';
        _loadingNearby = false;
      });
    }
  }

  Future<Position?> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      return Geolocator.getLastKnownPosition();
    }
  }

  List<_NearbyLine> _groupStopsByLine(List<StopInfo> stops) {
    final byLine = <String, List<StopInfo>>{};

    for (final stop in stops) {
      for (final line in stop.lines) {
        byLine.putIfAbsent(line.trim(), () => []).add(stop);
      }
    }

    final result = byLine.entries
        .map((entry) => _NearbyLine(code: entry.key, stops: entry.value))
        .toList();

    result.sort((a, b) {
      final aNum = int.tryParse(a.code) ?? 999999;
      final bNum = int.tryParse(b.code) ?? 999999;
      final numberCompare = aNum.compareTo(bNum);
      if (numberCompare != 0) return numberCompare;
      return a.code.compareTo(b.code);
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linhas perto de voce'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadingNearby ? null : _loadScreenData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingNearby
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadScreenData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  if (_message != null) _buildMessage(_message!),
                  _buildNearbyLines(),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.near_me,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_nearbyLines.length} linha(s) em ${_nearbyStops.length} parada(s) num raio de 200 m',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(message, style: TextStyle(color: Colors.orange[800])),
    );
  }

  Widget _buildNearbyLines() {
    if (_nearbyLines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Linhas proximas',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ..._nearbyLines.map(_buildLineTile),
      ],
    );
  }

  Widget _buildLineTile(_NearbyLine nearbyLine) {
    final provider = Provider.of<BusProvider>(context, listen: false);
    final line = provider.getLineByNumber(nearbyLine.code);

    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            nearbyLine.code,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(line?.numeroNome ?? 'Linha ${nearbyLine.code}'),
        subtitle: Text(
          '${nearbyLine.stops.length} parada(s) perto de voce',
        ),
        children: [
          for (final stop in nearbyLine.stops)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text('Parada ${stop.id}'),
              subtitle: Text(stop.name),
              onTap: () {
                final position = _position;
                if (position == null) return;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StopWalkingMapScreen(
                      userPosition: position,
                      stop: stop,
                    ),
                  ),
                );
              },
            ),
          if (line != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LineDetailScreen(linha: line),
                    ),
                  );
                },
                icon: const Icon(Icons.directions_bus),
                label: const Text('Ver linha'),
              ),
            ),
        ],
      ),
    );
  }

}

class _NearbyLine {
  final String code;
  final List<StopInfo> stops;

  _NearbyLine({required this.code, required this.stops});
}
