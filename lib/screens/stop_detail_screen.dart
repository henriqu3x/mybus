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
  Map<String, List<String>> _schedules = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final provider = Provider.of<BusProvider>(context, listen: false);
    final now = DateTime.now();
    final dateStr =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;
    
    if (provider.linhas.isEmpty) {
        await provider.fetchLinhas();
    }

    Map<String, List<String>> result = {};

    for (String lineCode in widget.stop.lines) {
      final lineId = int.tryParse(lineCode);
      if (lineId == null) continue;

      try {
        final horariosPosto = await provider.getHorarios(lineId, dateStr);
        List<String> allTimes = [];
        for (var posto in horariosPosto) {
          allTimes.addAll(posto.horarios.map((h) => h.horario));
        }

        // Filter upcoming times
        final upcoming = allTimes.where((t) {
          try {
            final parts = t.split(':');
            final min = int.parse(parts[0]) * 60 + int.parse(parts[1]);
            return min >= currentMinutes;
          } catch (e) {
            return false;
          }
        }).toList();

        result[lineCode] = upcoming;
      } catch (e) {
        print('Error loading schedule for line $lineCode: $e');
        result[lineCode] = [];
      }
    }

    if (mounted) {
      setState(() {
        _schedules = result;
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
                      final schedules = _schedules[lineCode] ?? [];

                          final line = Provider.of<BusProvider>(context, listen: false)
                              .getLineByNumber(lineCode);
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ExpansionTile(
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
                          subtitle: schedules.isEmpty
                              ? const Text(
                                  'Sem mais saídas hoje',
                                  style: TextStyle(color: Colors.orange),
                                )
                              : Text(
                                  'Próximas: ${schedules.take(3).join(', ')}',
                                  style: const TextStyle(color: Colors.green),
                                ),
                          children: [
                            if (schedules.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Próximos horários:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: schedules
                                          .take(10)
                                          .map(
                                            (time) => Chip(
                                              label: Text(time),
                                              backgroundColor: Colors.blue[100],
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                          ],
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
