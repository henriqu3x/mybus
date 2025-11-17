import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/api_provider.dart';
import '../models/logradouro.dart';
import '../models/line.dart';
import '../models/route_suggestion.dart';
import 'itinerary_details_screen.dart';
import 'route_details_screen.dart';

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  Logradouro? _origin;
  Logradouro? _destination;
  List<RouteSuggestion> _routeSuggestions = [];
  bool _isLoading = false;
  bool _isSearching = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planejador de Rotas'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _clearSearch,
              tooltip: 'Limpar busca',
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cartão de seleção de origem e destino
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Planejar Rota',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLocationSelector(
                    label: 'Origem',
                    selectedLocation: _origin,
                    onTap: () => _selectLocation(true),
                  ),
                  const SizedBox(height: 12),
                  _buildLocationSelector(
                    label: 'Destino',
                    selectedLocation: _destination,
                    onTap: () => _selectLocation(false),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.directions_bus),
                      label: const Text('Buscar Rotas'),
                      onPressed: (_origin != null && _destination != null && !_isLoading)
                          ? _findRoutes
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Resultados da busca
          if (_isSearching) ..._buildSearchResults(),
        ],
      ),
    );
  }

  List<Widget> _buildSearchResults() {
    if (_isLoading) {
      return [
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
      ];
    }

    if (_errorMessage != null) {
      return [
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar Novamente'),
                onPressed: _findRoutes,
              ),
            ],
          ),
        ),
      ];
    }

    if (_routeSuggestions.isEmpty) {
      return [
        const SizedBox(height: 24),
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Nenhuma rota encontrada. Tente ajustar os pontos de partida e destino.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ];
    }

    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Text(
          'Sugestões de Rotas:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _routeSuggestions.length,
          itemBuilder: (context, index) {
            final suggestion = _routeSuggestions[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              elevation: 2,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: Text(
                    suggestion.steps.length == 1 ? 'Direto' : '${suggestion.steps.length - 1} troca',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(
                  suggestion.steps.length == 1
                      ? 'Rota Direta - ${suggestion.steps[0].line.name}'
                      : 'Com troca - ${suggestion.steps[0].line.name} → ${suggestion.steps[1].line.name}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: suggestion.steps.length == 1
                    ? Text('Linha: ${suggestion.steps[0].line.numeroNome}')
                    : Text('Troca em: ${suggestion.steps[1].from?.nome ?? 'Ponto'}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // Navigate to route details screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RouteDetailsScreen(routeSuggestion: suggestion),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ];
  }

  void _clearSearch() {
    setState(() {
      _isSearching = false;
      _routeSuggestions = [];
      _errorMessage = null;
    });
  }

  Widget _buildLocationSelector({
    required String label,
    required Logradouro? selectedLocation,
    required VoidCallback onTap,
  }) {
    final isSelected = selectedLocation != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Colors.blue.shade100 : Colors.grey.shade300,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(8),
            color: isSelected ? Colors.blue.shade50 : Colors.white,
          ),
          child: Row(
            children: [
              Icon(
                label == 'Origem' ? Icons.location_on : Icons.location_city,
                color: isSelected ? Colors.blue : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.blue.shade700 : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isSelected
                          ? '${selectedLocation.nome} (${selectedLocation.tipo})'
                          : 'Toque para selecionar $label',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        color: isSelected ? Colors.black87 : Colors.grey.shade600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: isSelected ? Colors.blue : Colors.grey,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectLocation(bool isOrigin) async {
    final provider = context.read<ApiProvider>();
    List<Logradouro> logradouros = provider.logradouros ?? [];
    bool loadedFromApi = false;

    // Se os logradouros ainda não foram carregados, carregue-os
    if (logradouros.isEmpty) {
      if (!mounted) return;

      setState(() {
        _isLoading = true;
      });

      try {
        await provider.fetchLogradouros();
        logradouros = provider.logradouros ?? [];
        loadedFromApi = true;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao carregar logradouros. Tente novamente.'),
            action: SnackBarAction(
              label: 'Tentar Novamente',
              onPressed: () => _selectLocation(isOrigin),
            ),
          ),
        );
        return;
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }

    if (!mounted) return;

    // Se não há logradouros após a tentativa de carregamento, mostre uma mensagem
    if (logradouros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum logradouro disponível.')),
      );
      return;
    }

    // Se acabou de carregar da API e tem poucos itens, mostre direto a lista
    if (loadedFromApi && logradouros.length <= 5) {
      if (logradouros.length == 1) {
        // Se só tiver um, selecione automaticamente
        _updateSelectedLocation(logradouros.first, isOrigin);
        return;
      }
      // Se tiver poucos, mostre um diálogo de seleção simples
      _showSimpleSelectionDialog(logradouros, isOrigin);
      return;
    }

    // Para muitos itens, mostre o bottom sheet com busca
    final selected = await showModalBottomSheet<Logradouro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildLocationSelectionSheet(logradouros, isOrigin),
    );

    if (selected != null && mounted) {
      _updateSelectedLocation(selected, isOrigin);
    }
  }

  void _updateSelectedLocation(Logradouro selected, bool isOrigin) {
    setState(() {
      if (isOrigin) {
        _origin = selected;
      } else {
        _destination = selected;
      }
      // Se ambos estão preenchidos e é uma nova seleção, limpe os resultados anteriores
      if (_origin != null && _destination != null) {
        _routeSuggestions = [];
        _errorMessage = null;
      }
    });
  }

  Widget _buildLocationSelectionSheet(List<Logradouro> logradouros, bool isOrigin) {
    final TextEditingController searchController = TextEditingController();
    List<Logradouro> filteredLogradouros = List.from(logradouros);

    return StatefulBuilder(
      builder: (context, setState) {
        void filterLogradouros(String query) {
          if (query.isEmpty) {
            filteredLogradouros = List.from(logradouros);
          } else {
            filteredLogradouros = logradouros
                .where((logradouro) =>
                    logradouro.nome.toLowerCase().contains(query.toLowerCase()) ||
                    logradouro.tipo.toLowerCase().contains(query.toLowerCase()))
                .toList();
          }
          setState(() {});
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Cabeçalho
              Padding(
                padding: const EdgeInsets.all(16).copyWith(bottom: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selecionar ${isOrigin ? 'Origem' : 'Destino'}${filteredLogradouros.isNotEmpty ? ' (${filteredLogradouros.length})' : ''}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Barra de busca
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar logradouro...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: filterLogradouros,
                ),
              ),

              // Lista de logradouros
              Expanded(
                child: filteredLogradouros.isEmpty
                    ? _buildEmptyState(searchController.text.isNotEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: filteredLogradouros.length,
                        itemBuilder: (context, index) {
                          final logradouro = filteredLogradouros[index];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isOrigin ? Icons.location_on : Icons.location_city,
                                color: Colors.blue,
                              ),
                            ),
                            title: Text(
                              logradouro.nome,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              logradouro.tipo,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                            onTap: () => Navigator.pop(context, logradouro),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isSearch) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearch ? Icons.search_off : Icons.location_off,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              isSearch
                  ? 'Nenhum logradouro encontrado'
                  : 'Nenhum logradouro disponível',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isSearch) ...[
              const SizedBox(height: 8),
              const Text(
                'Tente atualizar a lista ou verificar sua conexão com a internet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSimpleSelectionDialog(List<Logradouro> logradouros, bool isOrigin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Selecione ${isOrigin ? 'origem' : 'destino'}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: logradouros.length,
            itemBuilder: (context, index) {
              final logradouro = logradouros[index];
              return ListTile(
                title: Text(logradouro.nome),
                subtitle: Text(logradouro.tipo),
                onTap: () {
                  Navigator.pop(context);
                  _updateSelectedLocation(logradouro, isOrigin);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _findRoutes() async {
    if (_origin == null || _destination == null) return;
    if (_origin!.id == _destination!.id) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Origem e destino não podem ser iguais'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isSearching = true;
      _routeSuggestions = [];
      _errorMessage = null;
    });

    try {
      final suggestions = await context.read<ApiProvider>().fetchRouteSuggestions(_origin!, _destination!);
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _routeSuggestions = suggestions;

        // Ordena as sugestões por número de conexões, depois por tipo e nome da primeira linha
        _routeSuggestions.sort((a, b) {
          if (a.connections != b.connections) {
            return a.connections.compareTo(b.connections);
          }
          final typeCompare = a.steps[0].line.tipoLinha.compareTo(b.steps[0].line.tipoLinha);
          if (typeCompare != 0) return typeCompare;
          return a.steps[0].line.name.compareTo(b.steps[0].line.name);
        });

        if (suggestions.isEmpty) {
          _errorMessage = 'Nenhuma rota encontrada entre os pontos selecionados.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erro ao buscar rotas: ${e.toString().replaceAll('Exception: ', '')}';
        });

        // Mostra um snackbar adicional para erros graves
        if (e.toString().contains('timeout') || e.toString().contains('SocketException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verifique sua conexão com a internet e tente novamente.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }
}
