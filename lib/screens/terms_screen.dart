import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Termos de Uso'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Termos de Uso',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            const Text(
              'Última atualização: ${'06/02/2026'}\n\n' // Using current date/placeholder
              'Ao utilizar este aplicativo, o usuário concorda com os termos descritos abaixo.\n\n'

              '1. Finalidade do aplicativo\n'
              'Este aplicativo tem como objetivo auxiliar usuários no planejamento, acompanhamento e tomada de decisão em viagens de transporte público por ônibus, com base em dados oficiais disponibilizados por órgãos públicos.\n\n'

              '2. Natureza das informações\n'
              'As informações apresentadas, como horários e previsões de chegada, possuem caráter estimativo e podem variar devido a fatores externos, como trânsito, condições operacionais e alterações no sistema de transporte.\n\n'

              '3. Permissões\n'
              'O uso do aplicativo depende da concessão de permissões de localização pelo usuário. Sem essas permissões, determinadas funcionalidades podem não operar corretamente.\n\n'

              '4. Responsabilidades\n'
              'O desenvolvedor:\n'
              '- Não se responsabiliza por atrasos, cancelamentos ou mudanças operacionais do transporte público\n'
              '- Não garante a precisão absoluta das previsões apresentadas\n\n'

              '5. Uso consciente\n'
              'O aplicativo deve ser utilizado como ferramenta de apoio, não substituindo a atenção do usuário às condições reais da viagem.\n\n'

              '6. Modificações\n'
              'O aplicativo pode ser atualizado, modificado ou descontinuado a qualquer momento, visando melhorias técnicas ou funcionais.',
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
