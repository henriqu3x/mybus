import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Política de Privacidade'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Política de Privacidade',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            const Text(
              'Última atualização: ${'06/02/2026'}\n\n' // Using current date/placeholder
              'Este aplicativo foi desenvolvido com foco em transparência, privacidade e uso responsável das informações do usuário.\n\n'

              '1. Dados coletados\n'
              'O aplicativo pode acessar dados de localização do usuário, conforme permissão concedida no sistema operacional:\n'
              '- Localização em primeiro plano\n'
              '- Localização em segundo plano, quando necessário\n'
              'Nenhum dado pessoal identificável, como nome, e-mail ou documento, é coletado.\n\n'

              '2. Finalidade do uso\n'
              'Os dados de localização são utilizados exclusivamente para:\n'
              '- Exibir a posição do usuário no mapa\n'
              '- Calcular distâncias e previsões de chegada de ônibus\n'
              '- Permitir o acompanhamento de viagens em tempo real\n'
              '- Enviar notificações quando o usuário se aproxima do destino selecionado\n\n'

              '3. Uso da localização em segundo plano\n'
              'A localização em segundo plano é utilizada apenas durante viagens ativas, com a finalidade de garantir o funcionamento correto das notificações de aproximação ao destino.\n'
              'O aplicativo não realiza rastreamento contínuo fora desse contexto.\n\n'

              '4. Armazenamento de dados\n'
              '- Dados de localização não são armazenados em servidores externos\n'
              '- Informações como linhas favoritas e rotas frequentes são salvas localmente no dispositivo do usuário\n\n'

              '5. Compartilhamento de dados\n'
              'O aplicativo não compartilha dados com terceiros, empresas ou serviços externos.\n\n'

              '6. Direitos do usuário\n'
              'O usuário pode, a qualquer momento:\n'
              '- Revogar as permissões de localização nas configurações do dispositivo\n'
              '- Interromper o uso do aplicativo\n'
              'A revogação das permissões pode limitar ou impedir o funcionamento de algumas funcionalidades.\n\n'

              '7. Segurança\n'
              'São adotadas medidas técnicas adequadas para garantir que os dados sejam utilizados apenas para as finalidades descritas nesta política.\n\n'

              '8. Alterações nesta política\n'
              'Esta Política de Privacidade pode ser atualizada para refletir melhorias ou mudanças no aplicativo. Recomenda-se a revisão periódica.\n\n'

              '9. Contato\n'
              'Em caso de dúvidas sobre esta Política de Privacidade, o usuário pode entrar em contato pelo canal disponibilizado na página oficial do projeto.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: AppTheme.spaceXl),
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Voltar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
