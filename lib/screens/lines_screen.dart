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

class LinesScreen extends StatefulWidget {
  const LinesScreen({super.key});

  @override
  State<LinesScreen> createState() => _LinesScreenState();
}

class _LinesScreenState extends State<LinesScreen> {
  final TextEditingController _searchController = TextEditingController();
  late BusProvider _busProvider;

  List<Favorito> _favoritesLines = [];
  bool _loadingFavorites = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BusProvider>(context, listen: false);
      if (provider.linhas.isEmpty) {
        provider.fetchLinhas();
      }
    });
  }

  Future<void> _loadFavorites() async {
    final favorites = await FavoritesService().getFavoritesByType(
      FavoritoType.LINE,
    );
    if (mounted) {
      setState(() {
        _favoritesLines = favorites;
        _loadingFavorites = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 2. Salva a referência do provider enquanto o context ainda é válido
    _busProvider = Provider.of<BusProvider>(context, listen: false);
  }

  @override
  void dispose() {
    // O microtask agenda a execução para o próximo milissegundo disponível,
    // saindo do momento em que a árvore está "travada".
    Future.microtask(() {
      _busProvider.filterLinhas('');
    });
    
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linhas de Ônibus'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // If not loading and empty, maybe trigger fetch or show empty state
                  if (!provider.isLoading && provider.error != null) {
                    return Center(child: Text(provider.error!));
                  }
                }

                // Prioritize favorites
                final allLinhas = provider.linhas;
                final favoriteIds = _favoritesLines
                    .map((f) => f.entityId)
                    .toSet();

                final favoriteLinhas = allLinhas
                    .where((l) => favoriteIds.contains(l.numero.toString()))
                    .toList();
                final nonFavoriteLinhas = allLinhas
                    .where((l) => !favoriteIds.contains(l.numero.toString()))
                    .toList();

                final sortedLinhas = [...favoriteLinhas, ...nonFavoriteLinhas];

                if (sortedLinhas.isEmpty && !provider.isLoading) {
                  return const Center(child: Text("Nenhuma linha encontrada."));
                }

                return ListView.builder(
                  itemCount: sortedLinhas.length,
                  itemBuilder: (context, index) {
                    final linha = sortedLinhas[index];
                    final isFavorite = favoriteIds.contains(
                      linha.numero.toString(),
                    );

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
          final provider = Provider.of<BusProvider>(context, listen: false);
          final linhaNumero = int.tryParse(favorito.entityId);
          if (linhaNumero == null) return;

          final linha = provider.linhas.firstWhere(
            (l) => l.numero == linhaNumero,
            orElse: () => Linha(
              numero: 0,
              nome: 'Desconhecida',
              tipoLinha: '',
              numeroNome: '',
            ), // Safe fallback
          );

          if (linha.numero != 0) {
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
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      await FavoritesService().removeFavorite(
                        favorito.favoritoId,
                      );
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
