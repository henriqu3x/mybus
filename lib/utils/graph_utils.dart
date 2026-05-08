import 'package:collection/collection.dart';
import '../models/itinerario.dart';

class GraphNode {
  final int id;
  final String name;

  GraphNode(this.id, this.name);

  @override
  bool operator ==(Object other) => other is GraphNode && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name};
  }

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(json['id'] as int, json['name'] as String? ?? '');
  }
}

class GraphEdge {
  final GraphNode destination;
  final double weight; // Cost (e.g., distance or time)
  final String lineName; // Which bus line covers this edge

  GraphEdge(this.destination, this.weight, this.lineName);

  Map<String, dynamic> toJson() {
    return {
      'destinationId': destination.id,
      'weight': weight,
      'lineName': lineName,
    };
  }
}

class TransportGraph {
  final Map<int, GraphNode> nodes = {};
  final Map<int, List<GraphEdge>> adjacencyList = {};

  TransportGraph();

  Map<String, dynamic> toJson() {
    return {
      'nodes': nodes.map(
        (id, node) => MapEntry(id.toString(), node.toJson()),
      ),
      'adjacencyList': adjacencyList.map(
        (fromId, edges) => MapEntry(
          fromId.toString(),
          edges.map((edge) => edge.toJson()).toList(),
        ),
      ),
    };
  }

  factory TransportGraph.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'];
    final rawAdjacency = json['adjacencyList'];

    if (rawNodes is! Map || rawAdjacency is! Map) {
      throw const FormatException('Invalid transport graph payload.');
    }

    final graph = TransportGraph();

    for (final entry in rawNodes.entries) {
      final id = int.tryParse(entry.key.toString());
      final value = entry.value;
      if (id == null || value is! Map<String, dynamic>) {
        throw const FormatException('Invalid node entry in graph payload.');
      }
      final node = GraphNode.fromJson(value);
      graph.nodes[id] = node;
      graph.adjacencyList[id] = [];
    }

    for (final entry in rawAdjacency.entries) {
      final fromId = int.tryParse(entry.key.toString());
      final value = entry.value;
      if (fromId == null || value is! List) {
        throw const FormatException('Invalid adjacency entry in graph payload.');
      }

      final edges = <GraphEdge>[];
      for (final rawEdge in value) {
        if (rawEdge is! Map<String, dynamic>) {
          throw const FormatException('Invalid graph edge payload.');
        }

        final destinationId = rawEdge['destinationId'] as int?;
        final weightValue = rawEdge['weight'];
        final lineName = rawEdge['lineName'] as String?;
        final destination = destinationId != null
            ? graph.nodes[destinationId]
            : null;

        if (destination == null ||
            weightValue is! num ||
            lineName == null ||
            !graph.nodes.containsKey(fromId)) {
          throw const FormatException('Graph edge references invalid nodes.');
        }

        edges.add(GraphEdge(destination, weightValue.toDouble(), lineName));
      }

      graph.adjacencyList[fromId] = edges;
    }

    return graph;
  }

  void addNode(int id, String name) {
    if (!nodes.containsKey(id)) {
      nodes[id] = GraphNode(id, name);
      adjacencyList[id] = [];
    }
  }

  void addEdge(int fromId, int toId, double weight, String lineName) {
    if (nodes.containsKey(fromId) && nodes.containsKey(toId)) {
      adjacencyList[fromId]!.add(GraphEdge(nodes[toId]!, weight, lineName));
    }
  }

  // Build graph from a list of itineraries
  void buildFromItineraries(List<Map<String, dynamic>> lineItineraries) {
    // lineItineraries structure: {'line': String, 'itinerario': Itinerario}

    for (var item in lineItineraries) {
      String lineName = item['line'];
      Itinerario itinerario = item['itinerario'];
      List<Ponto> pontos = itinerario.pontos;

      if (pontos.isEmpty) continue;

      // Add all nodes first
      for (var ponto in pontos) {
        addNode(ponto.logId, ponto.nome);
      }

      // Add edges between sequential stops
      for (int i = 0; i < pontos.length - 1; i++) {
        Ponto current = pontos[i];
        Ponto next = pontos[i + 1];

        addEdge(current.logId, next.logId, next.distanciaPercorrida, lineName);
      }
    }
  }

  List<GraphEdge>? findShortestPath(
    int startId,
    int endId, {
    Map<String, int>? initialWaitTimes,
    Set<String>? excludedLines,
    Set<String>? penalizedLines,
    Set<String>? allowedInitialLineCodes,
  }) {
    final Map<String, GraphEdge> previousEdge = {};
    // Key: State, Value: Previous State Key
    final Map<String, String> previousState = {};

    // Priority Queue for Dijkstra
    final pq = PriorityQueue<_State>((a, b) => a.cost.compareTo(b.cost));

    // Penalty for switching lines (in meters).
    // Terminal transfers are free, so they get a reduced penalty (50,000m)
    // Street transfers require a new fare, so they get a higher penalty (200,000m)
    const double terminalTransferPenalty = 50000.0;
    const double streetTransferPenalty = 200000.0;

    // Speed in m/min for converting wait time to distance penalty
    // Must match TimeUtils.averageSpeedKmh (25.0 km/h)
    const double speedMetersPerMinute = (25.0 * 1000) / 60;

    // Min cost to reach a node arriving on a specific line
    // Key: "$nodeId|$lineName" (or "$nodeId|null" for start)
    final Map<String, double> minCosts = {};

    // Initialize
    final startKey = "$startId|null";
    minCosts[startKey] = 0;
    pq.add(_State(startId, null, 0));

    String? finalStateKey;
    double finalMinCost = double.infinity;

    while (pq.isNotEmpty) {
      final current = pq.removeFirst();
      final currentKey = "${current.nodeId}|${current.lineName}";

      // If we found a cheaper way to this state already, skip
      if (current.cost > (minCosts[currentKey] ?? double.infinity)) continue;

      // If we reached the destination, we update the best cost found so far.
      // We don't stop immediately because we might reach it cheaper via another line (though unlikely with Dijkstra order,
      // but strictly speaking we stop when we pop the destination).
      if (current.nodeId == endId) {
        if (current.cost < finalMinCost) {
          finalMinCost = current.cost;
          finalStateKey = currentKey;
        }
        // Since it's a priority queue, the first time we pop endId, it is the shortest path to endId
        // (considering the transfer penalty as part of the weight).
        break;
      }

      final neighbors = adjacencyList[current.nodeId];
      if (neighbors == null) continue;

      for (var edge in neighbors) {
        if (excludedLines != null && excludedLines.contains(edge.lineName))
          continue;
        if (current.nodeId == startId &&
            allowedInitialLineCodes != null &&
            !_lineCodeMatches(edge.lineName, allowedInitialLineCodes)) {
          continue;
        }

        double penalty = 0;

        // Apply penalty if we are switching lines (and it's not the start)
        if (current.lineName != null && current.lineName != edge.lineName) {
          // Check if it's the same base line (e.g., "051_IDA" vs "051_VOLTA")
          String currentBase = current.lineName!
              .replaceAll('_IDA', '')
              .replaceAll('_VOLTA', '');
          String edgeBase = edge.lineName
              .replaceAll('_IDA', '')
              .replaceAll('_VOLTA', '');

          // Only apply penalty if it's a different physical line
          if (currentBase != edgeBase) {
            // Check if the transfer is happening at a terminal
            final currentNode = nodes[current.nodeId];
            if (currentNode != null && _isTerminal(currentNode.name)) {
              // Terminal transfers are free, so use reduced penalty
              penalty = terminalTransferPenalty;
            } else {
              // Street transfers require new fare, so use higher penalty
              penalty = streetTransferPenalty;
            }
          }
        }

        // Apply initial wait time penalty if we are at the start node
        if (current.nodeId == startId && initialWaitTimes != null) {
          // Check if we have a wait time for this line
          // The lineName in edge might be "051-Grande Circular I"
          // The key in initialWaitTimes should match this
          if (initialWaitTimes.containsKey(edge.lineName)) {
            final waitMinutes = initialWaitTimes[edge.lineName]!;
            // Convert minutes to meters equivalent
            penalty += waitMinutes * speedMetersPerMinute;
          }
        }

        // Apply penalty for alternative route generation
        if (penalizedLines != null && penalizedLines.contains(edge.lineName)) {
           // Massive penalty to discourage re-using this line unless absolutely necessary
           penalty += 500000.0;
        }

        double newCost = current.cost + edge.weight + penalty;
        String nextKey = "${edge.destination.id}|${edge.lineName}";

        if (newCost < (minCosts[nextKey] ?? double.infinity)) {
          minCosts[nextKey] = newCost;
          previousEdge[nextKey] = edge;
          previousState[nextKey] = currentKey;
          pq.add(_State(edge.destination.id, edge.lineName, newCost));
        }
      }
    }

    if (finalStateKey == null) return null;

    // Reconstruct path
    List<GraphEdge> path = [];
    String? currKey = finalStateKey;

    while (currKey != null && currKey != startKey) {
      final edge = previousEdge[currKey];
      if (edge == null) break;
      path.insert(0, edge);
      currKey = previousState[currKey];
    }

    return path;
  }

  /// Helper method to check if a node is a terminal.
  /// Terminals are identified by the word "Terminal" in their name.
  bool _isTerminal(String nodeName) {
    return nodeName.toLowerCase().contains('terminal');
  }

  bool _lineCodeMatches(String lineName, Set<String> allowedCodes) {
    final match = RegExp(r'^(\d+)').firstMatch(lineName.trim());
    if (match == null) return false;

    final lineNumber = int.tryParse(match.group(1)!);
    if (lineNumber == null) return false;

    return allowedCodes.any((code) {
      final allowedNumber = int.tryParse(code.trim());
      return allowedNumber != null && allowedNumber == lineNumber;
    });
  }
}

class _State {
  final int nodeId;
  final String? lineName;
  final double cost;

  _State(this.nodeId, this.lineName, this.cost);
}
