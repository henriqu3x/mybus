import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/kml_service.dart';
import '../providers/bus_provider.dart';

class StopDetailScreen extends StatefulWidget {
  final StopInfo stop;

  const StopDetailScreen({super.key, required this.stop});

  @override
  State<StopDetailScreen> createState() => _StopDetailScreenState();
}

class _StopDetailScreenState extends State<StopDetailScreen> {
  Map<String, int?> _predictedArrivals = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final provider = Provider.of<BusProvider>(context, listen: false);

    if (provider.linhas.isEmpty) {
        await provider.fetchLinhas();
    }

    Map<String, int?> result = {};

    for (String lineCode in widget.stop.lines) {
      final lineId = int.tryParse(lineCode);
      if (lineId == null) continue;

      try {
        final predictedArrival = await provider.getPredictedArrivalForStreet(lineId, widget.stop.name);
        result[lineCode] = predictedArrival;
      } catch (e) {
        print('Error loading predicted arrival for line $lineCode: $e');
        result[lineCode] = null;
      }
    }

    if (mounted) {
      setState(() {
        _predictedArrivals = result;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Parada ${widget.stop.id}'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : widget.stop.lines.isEmpty
                ? const Center(child: Text('Nenhuma linha identificada.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: widget.stop.lines.length,
                    itemBuilder: (context, index) {
                      final lineCode = widget.stop.lines[index];
                      final predictedArrival = _predictedArrivals[lineCode];

                      final line = Provider.of<BusProvider>(context, listen: false)
                          .getLineByNumber(lineCode);

                      String subtitleText;
                      Color subtitleColor;

                      if (predictedArrival == null) {
                        subtitleText = 'Sem previsão';
                        subtitleColor = Colors.grey;
                      } else {
                        subtitleText = 'Próxima chegada: $predictedArrival min';
                        if (predictedArrival <= 5) {
                          subtitleColor = Colors.red;
                        } else if (predictedArrival <= 15) {
                          subtitleColor = Colors.orange;
                        } else {
                          subtitleColor = Colors.green;
                        }
                      }

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
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            subtitleText,
                            style: TextStyle(color: subtitleColor),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
