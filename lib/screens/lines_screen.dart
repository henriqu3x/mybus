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
        title: Row(
          children: [
            const Icon(Icons.list_rounded, size: 28),
            const SizedBox(width: 12),
            const Text('Linhas de Ônibus'),
          ],
        ),
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
                      Icon(
                        Icons.star_rounded,
                        color: Theme.of(context).colorScheme.tertiary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Favoritos',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 110,
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
                hintText: 'Digite o número ou nome da linha',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          Provider.of<BusProvider>(
                            context,
                            listen: false,
                          ).filterLinhas('');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {}); // Rebuild to show/hide clear button
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
                  padding: const EdgeInsets.only(bottom: 16),
                  itemBuilder: (context, index) {
                    final linha = sortedLinhas[index];
                    final isFavorite = favoriteIds.contains(
                      linha.numero.toString(),
                    );

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(context).colorScheme.primaryContainer,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              linha.numero.toString(),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          linha.nome,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            linha.tipoLinha,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: isFavorite 
                                ? Theme.of(context).colorScheme.tertiary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 28,
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
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 130,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      favorito.entityId,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      await FavoritesService().removeFavorite(
                        favorito.favoritoId,
                      );
                      _loadFavorites();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                favorito.displayName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
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
