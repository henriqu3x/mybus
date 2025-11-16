import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/api_provider.dart';
import '../models/line.dart';
import 'itinerary_details_screen.dart';
import 'schedule_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
      ),
      body: Consumer<ApiProvider>(
        builder: (context, provider, child) {
          final favorites = provider.favoriteLines;

          if (favorites.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum favorito ainda',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Adicione linhas aos favoritos na tela de linhas',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final line = favorites[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(
                      line.id.toString(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(line.name),
                  subtitle: Text('${line.numeroNome} - ${line.tipoLinha}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.favorite, color: Colors.red),
                    onPressed: () {
                      provider.removeFromFavorites(line);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${line.name} removido dos favoritos'),
                          action: SnackBarAction(
                            label: 'Desfazer',
                            onPressed: () => provider.addToFavorites(line),
                          ),
                        ),
                      );
                    },
                  ),
                  onTap: () {
                    _showFavoriteOptions(context, line);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showFavoriteOptions(BuildContext context, Line line) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.route),
              title: const Text('Ver Itinerário'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ItineraryDetailsScreen(line: line),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Ver Horários'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ScheduleScreen(line: line),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Configurar Alertas'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement notifications setup
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Funcionalidade em desenvolvimento')),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
