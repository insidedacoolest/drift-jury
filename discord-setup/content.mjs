// Structure and fixed texts of the DriftFactory Discord server.
// Edit here and re-run setup.mjs: existing channels are reused and the
// bot's own messages are edited in place, nothing is duplicated.

export const SERVER_JOIN_URL = 'https://acstuff.ru/s/q:race/online/join?ip=45.131.108.170&httpPort=9055';

// Brand colors (driftfactory.pt).
export const LIME = 0xd4ff3f;
export const MAGENTA = 0xff3ec8;
export const DARK = 0x0b0c0f;

export const ROLES = [
  { name: 'Admin', color: LIME, hoist: true, admin: true },
  { name: 'Juiz', color: MAGENTA, hoist: true },
];

// readOnly: everyone reads, only Admin (and webhooks) post.
// webhook: a webhook the server plugin posts to (its URL goes into the Pitlane config).
export const CATEGORIES = [
  {
    name: 'INFORMAÇÃO',
    channels: [
      { name: 'boas-vindas', readOnly: true, topic: 'Bem-vindo à DriftFactory.' },
      { name: 'regras', readOnly: true, topic: 'Regras da comunidade e do servidor.' },
      { name: 'como-entrar', readOnly: true, topic: 'Tudo o que precisas para entrar no servidor.' },
      { name: 'anúncios', readOnly: true, topic: 'Novidades, eventos e mudanças no servidor.' },
    ],
  },
  {
    name: 'SERVIDORES',
    channels: [
      { name: 'estado-servidores', readOnly: true, webhook: 'StatusWebhookUrl',
        topic: 'Pista, pilotos ligados e link para entrar — atualizado a cada minuto.' },
    ],
  },
  {
    name: 'COMPETIÇÃO',
    channels: [
      { name: 'classificação', readOnly: true, webhook: 'LeaderboardWebhookUrl',
        topic: 'Classificação semanal por pista. Nova semana à segunda-feira; as anteriores ficam aqui.' },
      { name: 'runs', readOnly: true, webhook: 'RunsWebhookUrl',
        topic: 'Novos recordes da semana e vencedores semanais.' },
      { name: 'layouts', readOnly: true, topic: 'Pistas com layout oficial de julgamento.' },
    ],
  },
  {
    name: 'CONTEÚDO',
    channels: [
      { name: 'carros', readOnly: true, topic: 'Carros do servidor e downloads.' },
      { name: 'pistas', readOnly: true, topic: 'Pistas do servidor e downloads.' },
    ],
  },
  {
    name: 'COMUNIDADE',
    channels: [
      { name: 'geral', topic: 'Conversa geral.' },
      { name: 'clips-e-fotos', topic: 'Mostra as tuas melhores runs.' },
      { name: 'setups', topic: 'Partilha e discute setups.' },
      { name: 'procura-tandem', topic: 'Procura parceiros para tandem.' },
    ],
  },
  {
    name: 'SUPORTE',
    channels: [
      { name: 'ajuda', topic: 'Problemas a entrar ou a instalar conteúdo.' },
      { name: 'bugs-da-app', topic: 'Algo estranho na app de julgamento? Conta aqui, com print se possível.' },
    ],
  },
  {
    name: 'VOZ',
    voice: ['Lobby', 'Tandem 1', 'Tandem 2'],
  },
];

// Fixed messages, posted by the bot. Keyed by channel name.
export const MESSAGES = {
  'boas-vindas': [{
    title: 'Bem-vindo à DriftFactory',
    color: LIME,
    description: [
      'Comunidade de drift em Assetto Corsa, com julgamento automático das runs e classificação semanal.',
      '',
      '**Começa por aqui**',
      '• <#regras> — as regras da comunidade e do servidor',
      '• <#como-entrar> — o que precisas para entrar',
      '• <#estado-servidores> — que pista está a correr e quem está ligado',
      '• <#classificação> — a classificação da semana',
      '',
      'Site: https://driftfactory.pt',
    ].join('\n'),
  }],
  'regras': [{
    title: 'Regras',
    color: LIME,
    description: [
      '**Comunidade**',
      '1. Respeito por todos. Sem insultos, discriminação ou provocações.',
      '2. Sem spam, publicidade ou links duvidosos.',
      '3. Os admins têm a última palavra.',
      '',
      '**No servidor**',
      '4. O drift faz-se num só sentido. Nada de contramão.',
      '5. Não bates de propósito. Em tandem, combina antes.',
      '6. Se rodares ou parares, sai da linha para não estragar a run dos outros.',
      '',
      '**A run fica inválida se**',
      '• arrancares antes do fim da contagem',
      '• andares em contramão',
      '• endireitares o carro depois de começar o drift',
      '• saíres da pista com as quatro rodas',
      '• parares o carro, ou fizeres um trompo',
    ].join('\n'),
  }],
  'como-entrar': [{
    title: 'Como entrar',
    color: LIME,
    description: [
      '**Precisas de**',
      '• Assetto Corsa com o **Content Manager**',
      '• **Custom Shaders Patch (CSP)** atualizado',
      '• O carro e a pista do servidor — ver <#carros> e <#pistas>',
      '',
      '**Entrar**',
      `• [Abrir o servidor no Content Manager](${SERVER_JOIN_URL})`,
      '• Ou procura **DRIFTFACTORY** na lista de servidores online',
      '',
      '**A app de julgamento**',
      'Vem do próprio servidor — não instalas nada. Ao entrar, segue o guia em baixo no ecrã: vai até ao círculo verde da partida e **buzina**. Contagem de 5 segundos e a run começa.',
      'A janela da app abre-se no menu de extras online do chat do CSP (ícone da lâmpada).',
      '',
      'Problemas? Pergunta em <#ajuda>.',
    ].join('\n'),
  }],
  'layouts': [{
    title: 'Layouts oficiais',
    color: LIME,
    description: [
      'Pistas com layout oficial de julgamento (partida, chegada, zonas e clips):',
      '',
      '• **VDC Mondello 2022**',
      '',
      'Os layouts são publicados pelos admins e chegam sozinhos a quem entra no servidor.',
    ].join('\n'),
  }],
  'carros': [{
    title: 'Carros',
    color: LIME,
    description: [
      '**DriftFactory Nissan GT-R** (`driftfactory_nissan_gtr`)',
      'Download: _em breve_',
    ].join('\n'),
  }],
  'pistas': [{
    title: 'Pistas',
    color: LIME,
    description: [
      '**VDC Mondello 2022** (`vdc_mondello_2022`)',
      'Download: _em breve_',
    ].join('\n'),
  }],
};
