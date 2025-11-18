class RouteNode {
  final int logId;
  final double cost; // Custo total acumulado (em minutos)
  final RouteNode? predecessor;
  final int lineId; // -1 para caminhada
  final String lineName;

  RouteNode({
    required this.logId,
    required this.cost,
    this.predecessor,
    required this.lineId,
    required this.lineName,
  });
}