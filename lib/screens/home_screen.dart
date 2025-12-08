import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bus_provider.dart';
import '../services/favorites_service.dart';
import '../models/favorito.dart';
import '../models/linha.dart';
import 'line_detail_screen.dart';
import 'route_planner_screen.dart';
import 'alert_setup_screen.dart';
import 'favorites_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Favorito> _favoritesLines = [];
  bool _loadingFavorites = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BusProvider>(context, listen: false);
      provider.fetchLinhas();
      // Start building graph in background for Route Planner pre-load
      provider.buildGraph();
    });
  }

  Future<void> _loadFavorites() async {
    final favorites = await FavoritesService().getFavoritesByType(FavoritoType.LINE);
    if (mounted) {
      setState(() {
        _favoritesLines = favorites;
        _loadingFavorites = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('No Ponto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.star),
            tooltip: 'Favoritos',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FavoritesScreen(),
                ),
              ).then((_) => _loadFavorites()); // Reload favorites when returning
            },
          ),
          IconButton(
            icon: const Icon(Icons.map),
            tooltip: 'Planejador de Rotas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RoutePlannerScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Alertas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AlertSetupScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Favorites Section
          if (_favoritesLines.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        'Favoritos',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 95,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _favoritesLines.length,
                      itemBuilder: (context, index) {
                        final favorito = _favoritesLines[index];
                        return _buildFavoriteCard(favorito);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar Linha',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    Provider.of<BusProvider>(
                      context,
                      listen: false,
                    ).filterLinhas('');
                  },
                ),
              ),
              onChanged: (value) {
                Provider.of<BusProvider>(
                  context,
                  listen: false,
                ).filterLinhas(value);
              },
            ),
          ),
          Expanded(
            child: Consumer<BusProvider>(
              builder: (context, provider, child) {
                if (provider.linhas.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                // Prioritize favorites in search results
                final allLinhas = provider.linhas;
                final favoriteIds = _favoritesLines.map((f) => f.entityId).toSet();
                
                // Split into favorites and non-favorites
                final favoriteLinhas = allLinhas.where((l) => favoriteIds.contains(l.numero.toString())).toList();
                final nonFavoriteLinhas = allLinhas.where((l) => !favoriteIds.contains(l.numero.toString())).toList();
                
                // Combine: favorites first
                final sortedLinhas = [...favoriteLinhas, ...nonFavoriteLinhas];
                
                return ListView.builder(
                  itemCount: sortedLinhas.length,
                  itemBuilder: (context, index) {
                    final linha = sortedLinhas[index];
                    final isFavorite = favoriteIds.contains(linha.numero.toString());
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Text(
                            linha.numero.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(linha.nome),
                        subtitle: Text(linha.tipoLinha),
                        trailing: IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: isFavorite ? Colors.amber : Colors.grey,
                          ),
                          onPressed: () async {
                            if (isFavorite) {
                              await FavoritesService().removeFavoriteByEntity(
                                linha.numero.toString(),
                                FavoritoType.LINE,
                              );
                            } else {
                              await FavoritesService().addFavorite(
                                Favorito(
                                  tipo: FavoritoType.LINE,
                                  entityId: linha.numero.toString(),
                                  displayName: linha.nome,
                                ),
                              );
                            }
                            _loadFavorites();
                          },
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  LineDetailScreen(linha: linha),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard(Favorito favorito) {
    return Card(
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () async {
          // Find the linha by entityId (which is linha.numero)
          final provider = Provider.of<BusProvider>(context, listen: false);
          final linhaNumero = int.tryParse(favorito.entityId);
          if (linhaNumero == null) return;
          
          final linha = provider.linhas.cast<Linha?>().firstWhere(
            (l) => l?.numero == linhaNumero,
            orElse: () => null,
          );
          
          if (linha != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LineDetailScreen(linha: linha),
              ),
            );
          }
        },
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    radius: 16,
                    child: Text(
                      favorito.entityId,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      await FavoritesService().removeFavorite(favorito.favoritoId);
                      _loadFavorites();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                favorito.displayName,
                style: const TextStyle(fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
