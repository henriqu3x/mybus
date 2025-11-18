import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/api_provider.dart';
import '../models/line.dart';
import 'itinerary_details_screen.dart';
import 'schedule_screen.dart';

class LinesListScreen extends StatefulWidget {
  const LinesListScreen({super.key});

  @override
  State<LinesListScreen> createState() => _LinesListScreenState();
}

class _LinesListScreenState extends State<LinesListScreen> {
  List<Line> _filteredLines = [];
  String _searchQuery = '';
  String _selectedType = 'Todas';

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  Future<void> _loadLines() async {
    await context.read<ApiProvider>().fetchLines();
    _filterLines();
  }

  void _filterLines() {
    final provider = context.read<ApiProvider>();
    final allLines = provider.lines ?? [];

    setState(() {
      _filteredLines = allLines.where((line) {
        final matchesSearch = _searchQuery.isEmpty ||
            line.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            line.numeroNome.toLowerCase().contains(_searchQuery.toLowerCase());

        final matchesType =
            _selectedType == 'Todas' || line.tipoLinha == _selectedType;

        return matchesSearch && matchesType;
      }).toList();

      // Ordena por número da linha
      _filteredLines.sort((a, b) => a.id.compareTo(b.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linhas de Ônibus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLines,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Consumer<ApiProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    provider.error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar Novamente'),
                    onPressed: _loadLines,
                  ),
                ],
              ),
            );
          }

          final allLines = provider.lines ?? [];
          if (allLines.isEmpty) {
            return const Center(
              child: Text('Nenhuma linha encontrada.'),
            );
          }

          return Column(
            children: [
              // Barra de filtros
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Campo de busca
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar linha...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      onChanged: (value) {
                        _searchQuery = value;
                        _filterLines();
                      },
                    ),
                    const SizedBox(height: 12),
                    // Filtro por tipo
                    Row(
                      children: [
                        const Text('Tipo: ',
                            style:
                                TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _selectedType,
                            isExpanded: true,
                            items: [
                              'Todas',
                              'Complementar',
                              'Alimentadora',
                              'Troncal',
                            ].map((type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedType = value;
                                });
                                _filterLines();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Contador de resultados
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  '${_filteredLines.length} linha(s) encontrada(s)',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ),

              // Lista de linhas
              Expanded(
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _filteredLines.length,
                  itemBuilder: (context, index) {
                    final line = _filteredLines[index];
                    final isFavorite = provider.isFavorite(line);

                    return Card(
                      margin:
                          const EdgeInsets.symmetric(vertical: 4),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Text(
                            line.id.toString(),
                            style:
                                const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          line.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                            '${line.numeroNome} - ${line.tipoLinha}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isFavorite
                                    ? Colors.red
                                    : Colors.grey,
                              ),
                              onPressed: () {
                                if (isFavorite) {
                                  provider.removeFromFavorites(line);
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${line.name} removido dos favoritos'),
                                      action: SnackBarAction(
                                        label: 'Desfazer',
                                        onPressed: () => provider
                                            .addToFavorites(line),
                                      ),
                                    ),
                                  );
                                } else {
                                  provider.addToFavorites(line);
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${line.name} adicionado aos favoritos'),
                                    ),
                                  );
                                }
                              },
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) =>
                                  _onMenuItemSelected(value, line),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'itinerary',
                                  child: Text('Ver Itinerário'),
                                ),
                                const PopupMenuItem(
                                  value: 'schedule',
                                  child: Text('Ver Horários'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () =>
                            _onMenuItemSelected('itinerary', line),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onMenuItemSelected(String value, Line line) {
    switch (value) {
      case 'itinerary':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ItineraryDetailsScreen(line: line),
          ),
        );
        break;
      case 'schedule':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScheduleScreen(line: line),
          ),
        );
        break;
    }
  }
}
