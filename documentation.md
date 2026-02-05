# Documentação Técnica - No Ponto
**Versão:** 1.0.0
**Data:** 05/02/2026

## 1. Visão Geral do Projeto

O **No Ponto** é uma aplicação Flutter desenvolvida para auxiliar usuários do transporte público em Fortaleza. O aplicativo oferece funcionalidades de planejamento de rotas, acompanhamento em tempo real, consulta de itinerários e sistema de alertas de paradas.

### 1.1 Tecnologias Principais
*   **Framework:** Flutter SDK > 3.10.0
*   **Linguagem:** Dart
*   **Gerenciamento de Estado:** Provider
*   **Mapas:** Google Maps Flutter / OpenLayers (WebView)
*   **Persistência:** Shared Preferences, JSON Assets
*   **Localização:** Geolocator, Flutter Background Service

---

## 2. Arquitetura e Dependências

O projeto segue um padrão arquitetural MVVM simplificado, utilizando o pacote `provider` para injeção de dependência e gerenciamento de estado global.

### 2.1 Dependências Chave (pubspec.yaml)

| Pacote | Propósito |
| :--- | :--- |
| `provider` | Gerenciamento de estado (Ex: `BusProvider`). |
| `geolocator` | Acesso ao GPS do dispositivo. |
| `flutter_background_service` | Execução de código Dart em segundo plano (Isolates). |
| `flutter_local_notifications` | Exibição de notificações locais e alertas. |
| `webview_flutter` | Renderização de mapas avançados via OpenLayers/HTML. |
| `google_maps_flutter` | Interface de mapa nativa para a tela inicial. |

---

## 3. Estrutura do Projeto

O código fonte reside em `lib/` e está organizado por responsabilidade semântica.

### 3.1 Diretórios Principais

*   **`/lib/main.dart`**: Ponto de entrada da aplicação. Inicializa serviços e configurações globais.
*   **`/lib/models/`**: Classes de dados (DTOs) como `Line`, `StopInfo`, `Itinerary`.
*   **`/lib/screens/`**: Telas da aplicação (UI).
    *   `home_map_screen.dart`: Mapa principal com busca de rotas.
    *   `real_time_travel_screen.dart`: Tela de acompanhamento de viagem ativa.
    *   `course_planner_screen.dart`: Planejador de trajetos.
    *   `line_detail_screen.dart`: Detalhes e mapa de uma linha específica.
*   **`/lib/services/`**: Lógica de negócios e integração com APIs/Sistema.
    *   `background_service.dart`: Lógica de rastreamento em segundo plano.
    *   `kml_service.dart`: Parser de arquivos KML para rotas de ônibus.
    *   `notification_service.dart`: Gerenciador de canais e disparos de notificações.
*   **`/lib/providers/`**:
    *   `bus_provider.dart`: Centraliza o estado global das linhas e paradas carregadas.

---

## 4. Funcionalidades Detalhadas

### 4.1 Acompanhamento em Tempo Real
Permite que o usuário selecione uma linha e um destino. O app monitora a posição GPS do usuário em relação à rota do ônibus.
*   **UI:** Utiliza `WebView` com OpenLayers para desenhar a rota e a posição do usuário, permitindo animações suaves (ex: gradiente no traçado da rota).
*   **Lógica:** Calcula a distância euclidiana para a próxima parada e estima paradas restantes.

### 4.2 Planejador de Rotas
Algoritmo personalizado que utiliza grafos (construídos a partir dos dados de paradas e linhas) para encontrar o melhor trajeto entre dois pontos.

### 4.3 Dados Offline
O aplicativo carrega dados estáticos de rotas e paradas a partir de arquivos assets (KML/JSON), garantindo funcionamento básico mesmo sem internet constante.

---

## 5. Sistema de Rastreamento em Segundo Plano

Esta é uma funcionalidade crítica implementada para garantir que o usuário continue sendo monitorado mesmo com o app minimizado.

### 5.1 Fluxo de Funcionamento

1.  **Inicialização:** O `BackgroundService` é configurado no `SplashScreen`.
2.  **Lifecycle:** O `RealTimeTravelScreen` observa o estado do app (`didChangeAppLifecycleState`).
3.  **Pausa (Minimizar):**
    *   O stream de GPS da UI é pausado.
    *   O `BackgroundService` é iniciado.
    *   Os dados da viagem atual (paradas, destino) são enviados via `sendTripData` para o Isolate de background.
4.  **Execução (Background):**
    *   O serviço roda um `Geolocator.getPositionStream` com configurações de alta precisão e `enableWakeLock`.
    *   Calcula a distância para as paradas restantes.
    *   Dispara notificações locais ("Faltam 3 paradas", "Chegando!") independentemente da UI.
5.  **Retorno (Resumo):**
    *   O serviço de background é parado.
    *   A UI retoma o controle do GPS e atualiza o mapa visualmente.

### 5.2 Configurações Críticas (Android)

Para funcionar no Android 14+, as seguintes permissões foram configuradas no `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```
