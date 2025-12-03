
import 'dart:collection';

// --- COPIED LOGIC FROM planomelhor.dart (Modified to remove Flutter deps) ---

class Logradouro {
  final int id;
  final String nome;
  final String tipo;

  Logradouro({required this.id, required this.nome, required this.tipo});

  factory Logradouro.fromJson(Map<String, dynamic> json) {
    return Logradouro(
      id: json['id'],
      nome: (json['nome'] as String).trim(),
      tipo: (json['tipo'] as String).trim(),
    );
  }

  String get fullName => "$tipo $nome";
  
  @override
  bool operator ==(Object other) => other is Logradouro && other.id == id;
  
  @override
  int get hashCode => id.hashCode;
}

class Linha {
  final int numero;
  final String nome;
  final String numeroNome;
  final String tipoLinha;

  Linha({
    required this.numero,
    required this.nome,
    required this.numeroNome,
    required this.tipoLinha,
  });

  factory Linha.fromJson(Map<String, dynamic> json) {
    return Linha(
      numero: json['numero'],
      nome: json['nome'],
      numeroNome: json['numeroNome'],
      tipoLinha: json['tipoLinha'],
    );
  }
}

class GraphEdge {
  final int toNodeId;
  final double weight; // Distância
  final Linha linha;   // Linha que faz este trajeto
  final String stopName; // Nome do ponto de destino

  GraphEdge({
    required this.toNodeId,
    required this.weight,
    required this.linha,
    required this.stopName,
  });
}

class BusGraph {
  // Mapa de ID do Logradouro -> Lista de Arestas (Conexões)
  final Map<int, List<GraphEdge>> adjacencyList = {};

  void addEdge(int fromNode, int toNode, double weight, Linha linha, String toName) {
    if (!adjacencyList.containsKey(fromNode)) {
      adjacencyList[fromNode] = [];
    }
    adjacencyList[fromNode]!.add(GraphEdge(
      toNodeId: toNode,
      weight: weight,
      linha: linha,
      stopName: toName,
    ));
  }
}

class DijkstraResult {
  final List<GraphEdge> path;
  final double totalDistance;

  DijkstraResult({required this.path, required this.totalDistance});
}

class DijkstraSolver {
  static DijkstraResult? solve(BusGraph graph, int startNodeId, int endNodeId) {
    return _solveWithBacktracking(graph, startNodeId, endNodeId);
  }
  
  static DijkstraResult? _solveWithBacktracking(BusGraph graph, int startNodeId, int endNodeId) {
    Map<int, double> distances = {startNodeId: 0};
    Map<int, int> previousNodes = {}; // NodeId -> Parent NodeId
    Map<int, GraphEdge> edgeFromParent = {}; // NodeId -> Edge used from parent
    Set<int> visited = {};
    List<MapEntry<int, double>> priorityQueue = [MapEntry(startNodeId, 0)];

    while (priorityQueue.isNotEmpty) {
      priorityQueue.sort((a, b) => a.value.compareTo(b.value));
      final current = priorityQueue.removeAt(0);
      final u = current.key;

      if (u == endNodeId) break;
      if (visited.contains(u)) continue;
      visited.add(u);

      final neighbors = graph.adjacencyList[u] ?? [];
      for (var edge in neighbors) {
        final v = edge.toNodeId;
        final alt = distances[u]! + edge.weight;

        if (alt < (distances[v] ?? double.infinity)) {
          distances[v] = alt;
          previousNodes[v] = u;
          edgeFromParent[v] = edge;
          priorityQueue.add(MapEntry(v, alt));
        }
      }
    }

    if (!distances.containsKey(endNodeId)) return null;

    // Reconstruir
    List<GraphEdge> path = [];
    int curr = endNodeId;
    while (curr != startNodeId) {
      final edge = edgeFromParent[curr];
      if (edge == null) break; // Erro ou fim
      path.insert(0, edge);
      curr = previousNodes[curr]!;
    }

    return DijkstraResult(path: path, totalDistance: distances[endNodeId]!);
  }
}

// --- TEST RUNNER ---

void main() {
  print("Running Dijkstra Test...");

  // Setup Graph
  final graph = BusGraph();
  
  // Mock Data
  final l1 = Linha(numero: 617, nome: "Rota Bairro", numeroNome: "617-Bairro", tipoLinha: "Alim");
  final l2 = Linha(numero: 51, nome: "Rota Centro", numeroNome: "051-Centro", tipoLinha: "Comp");
  final l3 = Linha(numero: 900, nome: "Expresso", numeroNome: "900-Expresso", tipoLinha: "Exp");

  // Route 1: A -> B -> C -> D (Vicente -> Tulipa -> Getulio -> Parangaba)
  // A=3846, B=254, C=612, D=51
  graph.addEdge(3846, 254, 200, l1, "Tulipa Negra");
  graph.addEdge(254, 3846, 200, l1, "Vicente Celestino");
  
  graph.addEdge(254, 612, 300, l1, "Getúlio Vargas");
  graph.addEdge(612, 254, 300, l1, "Tulipa Negra");
  
  graph.addEdge(612, 51, 400, l1, "Terminal Parangaba");
  graph.addEdge(51, 612, 400, l1, "Getúlio Vargas");

  // Route 2: D -> E -> F (Parangaba -> Osorio -> Centro)
  // D=51, E=33, F=999
  graph.addEdge(51, 33, 1500, l2, "Av. Osório de Paiva");
  graph.addEdge(33, 51, 1500, l2, "Terminal Parangaba");
  
  graph.addEdge(33, 999, 2000, l2, "Centro");
  graph.addEdge(999, 33, 2000, l2, "Av. Osório de Paiva");

  // Route 3: A -> D (Vicente -> Parangaba) - Shortcut
  graph.addEdge(3846, 51, 800, l3, "Terminal Parangaba");
  graph.addEdge(51, 3846, 800, l3, "Vicente Celestino");

  // Test 1: A -> D (Should take Route 3, dist 800)
  print("Test 1: Vicente (3846) -> Parangaba (51)");
  var result1 = DijkstraSolver.solve(graph, 3846, 51);
  if (result1 != null) {
    print("  Distance: ${result1.totalDistance}");
    print("  Path: ${result1.path.map((e) => e.linha.numero).toList()}");
    if (result1.totalDistance == 800) {
      print("  [PASS] Correct distance");
    } else {
      print("  [FAIL] Expected 800, got ${result1.totalDistance}");
    }
  } else {
    print("  [FAIL] No path found");
  }

  // Test 2: A -> F (Vicente -> Centro)
  // Should be A -> D (800) + D -> E (1500) + E -> F (2000) = 4300
  // Or A -> B -> C -> D (900) + ... = 4400
  print("\nTest 2: Vicente (3846) -> Centro (999)");
  var result2 = DijkstraSolver.solve(graph, 3846, 999);
  if (result2 != null) {
    print("  Distance: ${result2.totalDistance}");
    print("  Path: ${result2.path.map((e) => e.linha.numero).toList()}");
     if (result2.totalDistance == 4300) {
      print("  [PASS] Correct distance");
    } else {
      print("  [FAIL] Expected 4300, got ${result2.totalDistance}");
    }
  } else {
    print("  [FAIL] No path found");
  }
}
