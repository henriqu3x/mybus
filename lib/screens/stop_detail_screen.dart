import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/kml_service.dart';
import '../providers/bus_provider.dart';

import 'line_detail_screen.dart';

class StopDetailScreen extends StatefulWidget {
  final StopInfo stop;

  const StopDetailScreen({super.key, required this.stop});

  @override
  State<StopDetailScreen> createState() => _StopDetailScreenState();
}

class _StopDetailScreenState extends State<StopDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure lines are loaded just in case, though usually HomeMapScreen does it
    // We can do it silently
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BusProvider>(context, listen: false);
      if (provider.linhas.isEmpty) {
        provider.fetchLinhas();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Parada ${widget.stop.id}'),
        // backgroundColor: Colors.blue[800],
        // foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Parada ${widget.stop.id}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.stop.name != 'Parada ${widget.stop.id}')
                  Text(
                    widget.stop.name,
                    style: TextStyle(color: Colors.grey[700], fontSize: 16),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${widget.stop.lines.length} linha(s) passam aqui',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),

          // Lines list
          Expanded(
            child: widget.stop.lines.isEmpty
                ? const Center(child: Text('Nenhuma linha identificada.'))
                : Consumer<BusProvider>(
                    builder: (context, provider, child) {
                      if (provider.isLoading && provider.linhas.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: widget.stop.lines.length,
                        itemBuilder: (context, index) {
                          final lineCode = widget.stop.lines[index];
                          final line = provider.getLineByNumber(lineCode);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue,
                                child: Text(
                                  lineCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                line?.numeroNome ?? 'Linha $lineCode',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: const Text(
                                'Toque para ver detalhes e horários',
                                style: TextStyle(color: Colors.blueGrey),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              onTap: () {
                                if (line != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          LineDetailScreen(linha: line),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Detalhes da linha não disponíveis.',
                                      ),
                                    ),
                                  );
                                }
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
