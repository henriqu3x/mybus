import 'logradouro.dart'; // <--- IMPORT OBRIGATÓRIO

class RouteNode {
   final int logId;
   final double cost; // Total accumulated cost in minutes
   final RouteNode? predecessor;
   final int lineId; // -1 for walking
   final String lineName;
   final double segmentDistance; // Distance of this segment in km
   final double segmentTime; // Time for this segment in minutes
  
  // 🛑 CAMPOS ADICIONADOS PARA RESOLVER ERROS NO APIPROVIDER:
  final String? lineType;
  final Logradouro? stop;
  final double latitude;
  final double longitude;

   RouteNode({
     required this.logId,
     required this.cost,
     this.predecessor,
     required this.lineId,
     required this.lineName,
     this.segmentDistance = 0.0,
     this.segmentTime = 0.0,
    // 🛑 Inicialização dos novos campos:
    this.lineType,
    this.stop,
    // Usamos o construtor para inicializar latitude/longitude
    double? latitude,
    double? longitude,
   }) : 
    // Garante que a latitude/longitude sejam definidas, seja pelo 'stop' ou pelos valores passados.
    this.latitude = stop?.latitude ?? latitude ?? 0.0,
    this.longitude = stop?.longitude ?? longitude ?? 0.0;


   // ⚠️ CORREÇÃO CRUCIAL: Implementar igualdade baseada APENAS no logId
   @override
   bool operator ==(Object other) =>
        identical(this, other) ||
        other is RouteNode &&
             runtimeType == other.runtimeType &&
             logId == other.logId;

   @override
   int get hashCode => logId.hashCode;

   @override
   String toString() {
     return 'RouteNode{logId: $logId, cost: ${cost.toStringAsFixed(2)}, lineId: $lineId, type: $lineType}';
   }
}