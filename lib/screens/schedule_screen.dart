import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/api_provider.dart';
import '../models/line.dart';
import '../models/schedule.dart';

class ScheduleScreen extends StatefulWidget {
  final Line line;

  const ScheduleScreen({super.key, required this.line});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Schedule>? _schedules;
  bool _isLoading = true;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dateStr = DateFormat('yyyyMMdd').format(_selectedDate);
      await context.read<ApiProvider>().fetchSchedules(widget.line.id, dateStr);
      final schedules = context.read<ApiProvider>().schedules;

      if (!mounted) return;

      setState(() {
        _schedules = schedules;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadSchedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Horários - ${widget.line.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSchedule,
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(context),
            tooltip: 'Selecionar data',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho com data e informações da linha
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Linha: ${widget.line.numeroNome}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Data: ${DateFormat('EEEE, dd/MM/yyyy', 'pt_BR').format(_selectedDate)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Alterar'),
                        onPressed: () => _selectDate(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Indicador de carregamento
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )

          // Mensagem de erro
          else if (_errorMessage != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar Novamente'),
                        onPressed: _loadSchedule,
                      ),
                    ],
                  ),
                ),
              ),
            )

          // Lista de horários
          else if (_schedules != null && _schedules!.isNotEmpty)
            Expanded(
              child: _buildScheduleList(),
            )
          else
            const Expanded(
              child: Center(
                child: Text('Nenhum horário disponível para esta data.'),
              ),
            ),
        ]
      ),
    );
  }

  Widget _buildScheduleList() {
    if (_schedules == null || _schedules!.isEmpty) {
      return const Center(
        child: Text('Nenhum horário disponível para esta data.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _schedules!.length,
      itemBuilder: (context, index) {
        final schedule = _schedules![index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Text(
                'Ponto de Controle: ${schedule.postoControle}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
            ...schedule.entries.map((entry) {
              final isAccessible = entry.acessivel == true;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                elevation: 2,
                child: ListTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        entry.horario,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    'Saída ${entry.horario}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text('Tabela: ${entry.tabela}'),
                  trailing: isAccessible
                      ? const Tooltip(
                          message: 'Ônibus acessível',
                          child: Icon(
                            Icons.accessible_forward,
                            color: Colors.green,
                            size: 28,
                          ),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              );
            }),
            if (index < _schedules!.length - 1)
              const Divider(height: 32, thickness: 1),
          ],
        );
      },
    );
  }
}
