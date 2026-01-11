import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/bus_provider.dart';
import '../models/linha.dart';
import '../models/horario.dart';
import '../models/itinerario.dart';
import '../services/notification_service.dart';
import '../utils/time_utils.dart';

class AlertSetupScreen extends StatefulWidget {
  const AlertSetupScreen({super.key});

  @override
  State<AlertSetupScreen> createState() => _AlertSetupScreenState();
}

class _AlertSetupScreenState extends State<AlertSetupScreen> {
  Linha? _selectedLinha;
  ItinerarioCompleto? _itinerarioCompleto;
  String _selectedDirection = 'Ida'; // 'Ida' or 'Volta'
  Ponto? _selectedPonto;
  List<String> _upcomingArrivalTimes = [];
  String? _selectedArrivalTime;
  int _alertMinutesBefore = 5;
  bool _isLoadingItinerary = false;

  @override
  void initState() {
    super.initState();
    // NotificationService is now initialized in main.dart
  }

  Future<void> _loadItinerary(Linha linha) async {
    setState(() {
      _isLoadingItinerary = true;
      _selectedLinha = linha;
      _itinerarioCompleto = null;
      _selectedPonto = null;
      _upcomingArrivalTimes = [];
      _selectedArrivalTime = null;
    });

    try {
      final provider = Provider.of<BusProvider>(context, listen: false);
      final itinerario = await provider.getItinerario(linha.numero);

      // Load schedules as well for calculation
      String today = DateFormat('yyyyMMdd').format(DateTime.now());
      await provider.getHorarios(linha.numero, today);

      if (mounted) {
        setState(() {
          _itinerarioCompleto = itinerario;
          _isLoadingItinerary = false;
          // Default to Ida, check if available
          if (itinerario.ida == null && itinerario.volta != null) {
            _selectedDirection = 'Volta';
          } else {
            _selectedDirection = 'Ida';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingItinerary = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao carregar itinerário')),
        );
      }
    }
  }

  void _calculateArrivalTimes() async {
    if (_selectedLinha == null ||
        _selectedPonto == null ||
        _itinerarioCompleto == null)
      return;

    final provider = Provider.of<BusProvider>(context, listen: false);
    String today = DateFormat('yyyyMMdd').format(DateTime.now());
    final horarios = await provider.getHorarios(_selectedLinha!.numero, today);

    setState(() {
      _upcomingArrivalTimes = [];
      _selectedArrivalTime = null;
    });

    if (horarios.isEmpty) {
      return;
    }

    // Calculate distance to selected point
    Itinerario? currentItinerario = _selectedDirection == 'Ida'
        ? _itinerarioCompleto!.ida
        : _itinerarioCompleto!.volta;

    if (currentItinerario == null) return;

    double totalDist = 0;
    bool found = false;
    for (var ponto in currentItinerario.pontos) {
      if (ponto.logId == _selectedPonto!.logId) {
        found = true;
        break;
      }
      totalDist += ponto.distanciaPercorrida;
    }

    if (!found) {
      // Fallback logic
      totalDist = 0;
      for (var ponto in currentItinerario.pontos) {
        if (ponto.nome == _selectedPonto!.nome) {
          found = true;
          break;
        }
        totalDist += ponto.distanciaPercorrida;
      }
    }

    if (!found) return;

    int travelMinutes = TimeUtils.calculateTravelTimeMinutes(totalDist);
    
    // Find all next arrival times
    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;
    
    List<int> validArrivalMinutes = [];

    // Find matching control point
    HorarioPosto? matchingPosto;
    for (var posto in horarios) {
      if (posto.postoControle.toLowerCase() == currentItinerario.pontoInicial.toLowerCase() ||
          posto.postoControle.toLowerCase().contains(currentItinerario.pontoInicial.toLowerCase()) ||
          currentItinerario.pontoInicial.toLowerCase().contains(posto.postoControle.toLowerCase())) {
        matchingPosto = posto;
        break;
      }
    }
    
    // Fallback
    if (matchingPosto == null && horarios.length == 1) {
      matchingPosto = horarios.first;
    }

    if (matchingPosto != null) {
      for (var h in matchingPosto.horarios) {
        try {
          final parts = h.horario.split(':');
          final departureMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
          
          final arrivalMinutes = departureMinutes + travelMinutes;
          
          if (arrivalMinutes > currentMinutes) {
             validArrivalMinutes.add(arrivalMinutes);
          }
        } catch (e) {
          // ignore
        }
      }
    }

    validArrivalMinutes.sort();

    List<String> formattedTimes = validArrivalMinutes.map((minutes) {
  // Converte minutos totais de volta para o formato HH:mm base
      final h = (minutes ~/ 60) % 24;
      final m = minutes % 60;
      final baseTime = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      
      // Retorna o intervalo usando a função que criamos (passando 0 pois o tempo de viagem já foi somado)
      return TimeUtils.getTimeInterval(baseTime, 0); 
    }).toList();

    setState(() {
      _upcomingArrivalTimes = formattedTimes;
      if (formattedTimes.isNotEmpty) {
        _selectedArrivalTime = formattedTimes.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar Alertas'),
      backgroundColor: Colors.blue[800],
      foregroundColor: Colors.white,),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Escolha a Linha',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Consumer<BusProvider>(
              builder: (context, provider, child) {
                return Autocomplete<Linha>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      return const Iterable<Linha>.empty();
                    }
                    return provider.linhas.where((Linha option) {
                      return option.numeroNome.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      );
                    });
                  },
                  displayStringForOption: (Linha option) => option.numeroNome,
                  onSelected: (Linha selection) {
                    _loadItinerary(selection);
                  },
                  fieldViewBuilder:
                      (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Digite o número ou nome da linha',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.directions_bus),
                          ),
                        );
                      },
                );
              },
            ),

            if (_isLoadingItinerary)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),

            if (_itinerarioCompleto != null && !_isLoadingItinerary) ...[
              const SizedBox(height: 20),
              const Text(
                '2. Sentido e Ponto',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              // Direction Selector
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Ida'),
                      value: 'Ida',
                      groupValue: _selectedDirection,
                      onChanged: _itinerarioCompleto!.ida != null
                          ? (val) {
                              setState(() {
                                _selectedDirection = val!;
                                _selectedPonto = null;
                                _upcomingArrivalTimes = [];
                                _selectedArrivalTime = null;
                              });
                            }
                          : null,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Volta'),
                      value: 'Volta',
                      groupValue: _selectedDirection,
                      onChanged: _itinerarioCompleto!.volta != null
                          ? (val) {
                              setState(() {
                                _selectedDirection = val!;
                                _selectedPonto = null;
                                _upcomingArrivalTimes = [];
                                _selectedArrivalTime = null;
                              });
                            }
                          : null,
                    ),
                  ),
                ],
              ),

              // Stop Selector
              DropdownButtonFormField<Ponto>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Selecione o Ponto de Subida',
                  border: OutlineInputBorder(),
                ),
                value: _selectedPonto,
                items:
                    (_selectedDirection == 'Ida'
                            ? _itinerarioCompleto!.ida?.pontos
                            : _itinerarioCompleto!.volta?.pontos)
                        ?.map((ponto) {
                          return DropdownMenuItem(
                            value: ponto,
                            child: Text(
                              ponto.nome,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        })
                        .toList() ??
                    [],
                onChanged: (val) {
                  setState(() {
                    _selectedPonto = val;
                  });
                  _calculateArrivalTimes();
                },
              ),
            ],

            if (_selectedPonto != null) ...[
              const SizedBox(height: 20),
              
              if (_upcomingArrivalTimes.isEmpty)
                const Padding(
                   padding: EdgeInsets.all(8.0),
                   child: Text(
                     "Nenhuma previsão encontrada para hoje ou horários esgotados.",
                     style: TextStyle(color: Colors.orange),
                   ),
                )
              else 
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Previsão de Chegada no Ponto',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Escolha o horário do ônibus',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      value: _selectedArrivalTime,
                      items: _upcomingArrivalTimes.map((time) {
                        return DropdownMenuItem(
                          value: time,
                          child: Text(time),
                        );
                      }).toList(),
                      onChanged: (val) {
                         setState(() => _selectedArrivalTime = val);
                      }
                    ),
                  ],
                ),
                
              const SizedBox(height: 20),
              const Text(
                '3. Configurar Alerta',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Alertar $_alertMinutesBefore minutos antes da chegada prevista',
              ),
              Slider(
                value: _alertMinutesBefore.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$_alertMinutesBefore min',
                onChanged: (val) =>
                    setState(() => _alertMinutesBefore = val.toInt()),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.alarm_add),
                  label: const Text('Agendar Alerta'),
                  onPressed:
                      (_selectedArrivalTime != null)
                      ? _scheduleAlert
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _scheduleAlert() {
    if (_selectedArrivalTime == null || _selectedLinha == null) return;

    // Extrai apenas o primeiro horário do intervalo (ex: "10:13")
    final String firstTimeInInterval = _selectedArrivalTime!.split(' - ').first;
    
    final now = DateTime.now();
    final parts = firstTimeInInterval.split(':'); // Agora funciona
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    var arrivalDate = DateTime(now.year, now.month, now.day, hour, minute);
    if (arrivalDate.isBefore(now)) {
      arrivalDate = arrivalDate.add(const Duration(days: 1));
    }

    final alertDate = arrivalDate.subtract(
      Duration(minutes: _alertMinutesBefore),
    );

    if (alertDate.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horário do alerta já passou!')),
      );
      return;
    }

    NotificationService().scheduleNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Prepare-se para ir para a parada!',
      body:
          'O ônibus da linha ${_selectedLinha!.numeroNome} chegará às approx. $_selectedArrivalTime.',
      scheduledDate: alertDate,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Alerta agendado para ${DateFormat('HH:mm').format(alertDate)}',
        ),
      ),
    );
  }
}
