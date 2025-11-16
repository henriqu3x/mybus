import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/api_provider.dart';
import '../models/line.dart';
import '../models/itinerary.dart';

class ItineraryDetailsScreen extends StatefulWidget {
  final Line line;

  const ItineraryDetailsScreen({super.key, required this.line});

  @override
  State<ItineraryDetailsScreen> createState() => _ItineraryDetailsScreenState();
}

class _ItineraryDetailsScreenState extends State<ItineraryDetailsScreen> with SingleTickerProviderStateMixin {
  Map<String, Itinerary>? _itineraries;
  bool _isLoading = true;
  String? _errorMessage;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadItineraries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadItineraries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await context.read<ApiProvider>().fetchItinerary(widget.line.id);
      final provider = context.read<ApiProvider>();
      setState(() {
        _itineraries = provider.itinerary;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Itinerário - ${widget.line.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItineraries,
          ),
        ],
        bottom: _itineraries != null ? TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ida'),
            Tab(text: 'Volta'),
          ],
        ) : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar Novamente'),
                        onPressed: _loadItineraries,
                      ),
                    ],
                  ),
                )
              : _itineraries == null
                  ? const Center(
                      child: Text('Nenhum dado de itinerário disponível.'),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildItineraryList(_itineraries!['ida'], 'Ida'),
                        _buildItineraryList(_itineraries!['volta'], 'Volta'),
                      ],
                    ),
    );
  }

  Widget _buildItineraryList(Itinerary? itinerary, String direction) {
    if (itinerary == null) {
      return Center(
        child: Text('Itinerário de $direction não disponível.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Ponto de Partida ($direction): ${itinerary.pontoInicial}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: itinerary.points.length,
            itemBuilder: (context, index) {
              final point = itinerary.points[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text('${index + 1}'),
                  ),
                  title: Text(
                    point.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text('Distância percorrida: ${point.distanciaPercorrida}m'),
                  trailing: const Icon(Icons.location_on, color: Colors.blue),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
