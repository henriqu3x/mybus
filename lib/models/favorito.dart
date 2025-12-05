import 'package:uuid/uuid.dart';

enum FavoritoType {
  LINE,
  STOP,
  ROUTE;

  String toJson() => name;
  
  static FavoritoType fromJson(String json) {
    return FavoritoType.values.firstWhere((e) => e.name == json);
  }
}

class Favorito {
  final String favoritoId;
  final FavoritoType tipo;
  final String entityId;
  final String displayName;
  final String? routeData; // JSON string for routes
  final DateTime createdAt;

  Favorito({
    String? favoritoId,
    required this.tipo,
    required this.entityId,
    required this.displayName,
    this.routeData,
    DateTime? createdAt,
  })  : favoritoId = favoritoId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'favoritoId': favoritoId,
      'tipo': tipo.toJson(),
      'entityId': entityId,
      'displayName': displayName,
      'routeData': routeData,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Create from JSON
  factory Favorito.fromJson(Map<String, dynamic> json) {
    return Favorito(
      favoritoId: json['favoritoId'] as String,
      tipo: FavoritoType.fromJson(json['tipo'] as String),
      entityId: json['entityId'] as String,
      displayName: json['displayName'] as String,
      routeData: json['routeData'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Favorito &&
          runtimeType == other.runtimeType &&
          favoritoId == other.favoritoId;

  @override
  int get hashCode => favoritoId.hashCode;
}
