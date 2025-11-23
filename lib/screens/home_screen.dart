import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bus_provider.dart';
import 'line_detail_screen.dart';
import 'route_planner_screen.dart';
import 'alert_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BusProvider>(context, listen: false);
      provider.fetchLinhas();
      // Start building graph in background for Route Planner pre-load
      provider.buildGraph();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyBus - Ônibus Inteligente'),
        actions: [
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
                return ListView.builder(
                  itemCount: provider.linhas.length,
                  itemBuilder: (context, index) {
                    final linha = provider.linhas[index];
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
}
