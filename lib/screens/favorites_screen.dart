import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/favorites_service.dart';
import '../models/favorito.dart';
import '../models/linha.dart';
import '../models/trip_segment.dart';
import '../providers/bus_provider.dart';
import 'line_detail_screen.dart';
import 'route_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Favorito> _favoriteLines = [];
  List<Favorito> _favoriteStops = [];
  List<Favorito> _favoriteRoutes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFavorites();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    
    final lines = await FavoritesService().getFavoritesByType(FavoritoType.LINE);
    final stops = await FavoritesService().getFavoritesByType(FavoritoType.STOP);
    final routes = await FavoritesService().getFavoritesByType(FavoritoType.ROUTE);
    
    if (mounted) {
      setState(() {
        _favoriteLines = lines;
        _favoriteStops = stops;
        _favoriteRoutes = routes;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.directions_bus), text: 'Linhas'),
            // Tab(icon: Icon(Icons.place), text: 'Paradas'),
            Tab(icon: Icon(Icons.route), text: 'Rotas'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLinesTab(),
                _buildStopsTab(),
                _buildRoutesTab(),
              ],
            ),
    );
  }

  Widget _buildLinesTab() {
    if (_favoriteLines.isEmpty) {
      return _buildEmptyState(
        icon: Icons.directions_bus,
        message: 'Nenhuma linha favorita',
        subtitle: 'Adicione linhas aos favoritos na tela inicial',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favoriteLines.length,
      itemBuilder: (context, index) {
        final favorito = _favoriteLines[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue,
              child: Text(
                favorito.entityId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(favorito.displayName),
            subtitle: Text('Adicionado em ${_formatDate(favorito.createdAt)}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDelete(favorito),
            ),
            onTap: () => _openLineDetail(favorito),
          ),
        );
      },
    );
  }

  Widget _buildStopsTab() {
    if (_favoriteStops.isEmpty) {
      return _buildEmptyState(
        icon: Icons.place,
        message: 'Nenhuma parada favorita',
        subtitle: 'Adicione paradas aos favoritos no mapa',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favoriteStops.length,
      itemBuilder: (context, index) {
        final favorito = _favoriteStops[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.place, color: Colors.white),
            ),
            title: Text(favorito.displayName),
            subtitle: Text('Adicionado em ${_formatDate(favorito.createdAt)}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDelete(favorito),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoutesTab() {
    if (_favoriteRoutes.isEmpty) {
      return _buildEmptyState(
        icon: Icons.route,
        message: 'Nenhuma rota favorita',
        subtitle: 'Salve rotas planejadas como favoritas',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favoriteRoutes.length,
      itemBuilder: (context, index) {
        final favorito = _favoriteRoutes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.amber,
              child: Icon(Icons.route, color: Colors.white),
            ),
            title: Text(
              favorito.displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Adicionado em ${_formatDate(favorito.createdAt)}'),
                const SizedBox(height: 4),
                Text(
                  _getRoutePreview(favorito.routeData),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDelete(favorito),
            ),
            onTap: () => _openRouteDetail(favorito),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Hoje';
    } else if (difference.inDays == 1) {
      return 'Ontem';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} dias atrás';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getRoutePreview(String? routeData) {
    if (routeData == null) return '';
    
    try {
      final data = jsonDecode(routeData) as Map<String, dynamic>;
      final segments = data['segments'] as List<dynamic>;
      
      if (segments.isEmpty) return '';
      
      final lineNames = segments
          .map((s) => s['lineName'] as String)
          .toSet()
          .take(2)
          .join(', ');
      
      final moreCount = segments.length > 2 ? ' +${segments.length - 2}' : '';
      return 'Linhas: $lineNames$moreCount';
    } catch (e) {
      return '';
    }
  }

  Future<void> _confirmDelete(Favorito favorito) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover favorito'),
        content: Text('Deseja remover "${favorito.displayName}" dos favoritos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Remover',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FavoritesService().removeFavorite(favorito.favoritoId);
      _loadFavorites();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Favorito removido'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _openLineDetail(Favorito favorito) async {
    final provider = Provider.of<BusProvider>(context, listen: false);
    final linhaNumero = int.tryParse(favorito.entityId);
    
    if (linhaNumero == null) return;
    
    final linha = provider.linhas.cast<Linha?>().firstWhere(
      (l) => l?.numero == linhaNumero,
      orElse: () => null,
    );
    
    if (linha != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LineDetailScreen(linha: linha),
        ),
      );
    }
  }

  Future<void> _openRouteDetail(Favorito favorito) async {
    if (favorito.routeData == null) return;
    
    try {
      final data = jsonDecode(favorito.routeData!) as Map<String, dynamic>;
      
      final origin = data['origin'] as String;
      final destination = data['destination'] as String;
      final totalDistance = (data['totalDistance'] as num).toDouble();
      final totalTime = data['totalTime'] as int;
      
      final segmentsData = data['segments'] as List<dynamic>;
      final segments = segmentsData.map((s) {
        return TripSegment(
          type: s['type'] as String,
          lineName: s['lineName'] as String,
          startStreetName: s['startStreetName'] as String,
          endStreetName: s['endStreetName'] as String,
          distance: (s['distance'] as num).toDouble(),
        );
      }).toList();
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RouteDetailScreen(
              segments: segments,
              origin: origin,
              destination: destination,
              totalDistance: totalDistance,
              totalTime: totalTime,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir rota: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
