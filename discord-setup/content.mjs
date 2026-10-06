// Structure and fixed texts of the DriftFactory Discord server.
// Edit here and re-run setup.mjs: existing channels are reused and the
// bot's own messages are edited in place, nothing is duplicated.
//
// Channel kinds: text (default), announcement, forum, voice, stage.
// readOnly: everyone reads, only staff (and webhooks) post.
// staffOnly on a category: hidden from everyone but the staff roles.
// webhook: a webhook the server plugin posts to (its URL goes into the plugin config).

// Names as shown in Discord: "👋・boas-vindas" for channels, "📌 INFORMAÇÃO"
// for categories. `name` stays the key used everywhere else (links in
// messages, webhooks, the setup state).
export const SPACER = '・';
export const displayName = (spec, isCategory = false) =>
  !spec.emoji ? spec.name : isCategory ? `${spec.emoji} ${spec.name}` : `${spec.emoji}${SPACER}${spec.name}`;

export const SERVER_JOIN_URL ='https://acstuff.ru/s/q:race/online/join?ip=45.131.108.170&httpPort=9055';

// Google Drive downloads of what the server runs (shared "anyone with the link").
export const CAR_DOWNLOAD_URL = 'https://drive.google.com/file/d/1ZNqAIFWX11pZ9o_Kkky1X5jMSHOaUcKX/view?usp=sharing';
export const TRACK_DOWNLOAD_URL = 'https://drive.google.com/file/d/1bise65vhpFfxisXy-Ro7FTcoYmWw3eKF/view?usp=sharing';

// Brand colors (driftfactory.pt).
export const LIME = 0xd4ff3f;
export const MAGENTA = 0xff3ec8;
export const CREAM = 0xf3f4ef;

// Highest first. Staff roles see the private STAFF category.
export const ROLES = [
  { name: 'Admin', color: LIME, hoist: true, admin: true, staff: true },
  { name: 'Moderador', color: 0x7fd6ff, hoist: true, staff: true, moderate: true },
  { name: 'Juiz', color: MAGENTA, hoist: true, staff: true },
  { name: 'Organizador de Eventos', color: 0xffb03e, hoist: true, staff: true },
  { name: 'Campeão da Semana', color: 0xffd34d, hoist: true },
  { name: 'Criador de Conteúdo', color: 0xb58cff, hoist: false },
  { name: 'Piloto Real', color: 0xff6b4a, hoist: false },
];

export const CATEGORIES = [
  {
    name: 'INFORMAÇÃO', emoji: '📌',
    channels: [
      { name: 'boas-vindas', emoji: '👋', readOnly: true, topic: 'Bem-vindo à DriftFactory. Começa por aqui.' },
      { name: 'regras', emoji: '📜', readOnly: true, topic: 'Regras da comunidade e do servidor.' },
      { name: 'como-entrar', emoji: '🔑', readOnly: true, topic: 'Tudo o que precisas para entrar no servidor.' },
      { name: 'anúncios', emoji: '📢', kind: 'announcement', readOnly: true, topic: 'Novidades, eventos e mudanças. Podes seguir este canal no teu servidor.' },
      { name: 'faq', emoji: '❓', readOnly: true, topic: 'Perguntas frequentes.' },
      { name: 'cargos', emoji: '🏷️', readOnly: true, topic: 'O que significa cada cargo e como se consegue.' },
    ],
  },
  {
    name: 'SERVIDORES', emoji: '🖥️',
    channels: [
      { name: 'estado-servidores', emoji: '🟢', readOnly: true, webhook: 'StatusWebhookUrl',
        topic: 'Pista, pilotos ligados e link para entrar — atualizado a cada minuto.' },
      { name: 'atualizações-da-app', emoji: '🛠️', readOnly: true, topic: 'Mudanças na app de julgamento e no servidor.' },
    ],
  },
  {
    name: 'COMPETIÇÃO', emoji: '🏆',
    channels: [
      { name: 'classificação', emoji: '📊', readOnly: true, webhook: 'LeaderboardWebhookUrl',
        topic: 'Classificação semanal por pista. Nova semana à segunda-feira; as anteriores ficam aqui.' },
      { name: 'runs', emoji: '💨', readOnly: true, webhook: 'RunsWebhookUrl',
        topic: 'Novos líderes, subidas no top e vencedores de cada semana.' },
      { name: 'hall-da-fama', emoji: '👑', readOnly: true, topic: 'Campeões semanais e momentos para a história.' },
      { name: 'layouts', emoji: '🗺️', readOnly: true, topic: 'Pistas com layout oficial de julgamento.' },
      { name: 'conversa-competição', emoji: '💬', topic: 'Fala das runs, das notas e da classificação.' },
    ],
  },
  {
    name: 'EVENTOS', emoji: '📅',
    channels: [
      { name: 'calendário', emoji: '🗓️', kind: 'announcement', readOnly: true, topic: 'Próximos eventos, treinos livres e batalhas de tandem.' },
      { name: 'inscrições', emoji: '✍️', kind: 'forum', topic: 'Um tópico por evento: inscreve-te respondendo ao tópico.',
        tags: ['Aberto', 'Fechado', 'Tandem', 'Solo'] },
      { name: 'resultados', emoji: '🥇', readOnly: true, topic: 'Resultados e chaves dos eventos.' },
      { name: 'conversa-eventos', emoji: '🎤', topic: 'Antes, durante e depois dos eventos.' },
    ],
  },
  {
    name: 'COMUNIDADE', emoji: '🤝',
    channels: [
      { name: 'geral', emoji: '💬', topic: 'Conversa geral sobre drift e tudo o resto.' },
      { name: 'apresentações', emoji: '🙋', topic: 'És novo? Diz olá: de onde és, que volante tens, que carro preferes.' },
      { name: 'clips-e-fotos', emoji: '🎬', topic: 'Mostra as tuas melhores runs, tandems e fotos. Só media — conversa nos tópicos.' },
      { name: 'procura-tandem', emoji: '🏎️', topic: 'Procura parceiros para tandem e marca sessões.' },
      { name: 'drift-real', emoji: '🔥', topic: 'Drift na vida real: eventos, campeonatos, carros e trackdays.' },
      { name: 'sim-rigs', emoji: '🎮', topic: 'Volantes, pedais, cockpits, monitores e VR.' },
      { name: 'off-topic', emoji: '🍿', topic: 'Tudo o que não é drift.' },
      { name: 'sugestões', emoji: '💡', kind: 'forum', topic: 'Ideias para o servidor, a app, o Discord ou os eventos. Um tópico por ideia.',
        tags: ['Servidor', 'App', 'Discord', 'Eventos', 'Feito'] },
    ],
  },
  {
    name: 'APRENDER', emoji: '🎓',
    channels: [
      { name: 'guia-para-novatos', emoji: '🔰', readOnly: true, topic: 'Do zero ao primeiro drift limpo.' },
      { name: 'técnica-e-dicas', emoji: '🧠', topic: 'Iniciar o drift, transições, ângulo, linha e controlo.' },
      { name: 'pedir-feedback', emoji: '🎯', kind: 'forum', topic: 'Partilha uma run e pede opiniões. Um tópico por run.',
        tags: ['Novato', 'Intermédio', 'Avançado', 'Tandem'] },
      { name: 'setups', emoji: '🔧', kind: 'forum', topic: 'Setups por carro e pista. Um tópico por setup.',
        tags: ['Nissan GT-R', 'Mondello', 'Iniciante', 'Competição'] },
    ],
  },
  {
    name: 'CONTEÚDO', emoji: '📦',
    channels: [
      { name: 'carros', emoji: '🚗', readOnly: true, topic: 'Carros do servidor e downloads.' },
      { name: 'pistas', emoji: '🛣️', readOnly: true, topic: 'Pistas do servidor e downloads.' },
      { name: 'mods-recomendados', emoji: '🧩', readOnly: true, topic: 'O essencial para ter o Assetto Corsa como deve ser.' },
      { name: 'skins-e-liveries', emoji: '🎨', kind: 'forum', topic: 'Partilha as tuas pinturas. Um tópico por skin, com imagens e download.',
        tags: ['Nissan GT-R', 'Pedido', 'Equipa'] },
      { name: 'streams-e-vídeos', emoji: '📺', topic: 'Vais fazer live ou publicaste um vídeo? Partilha aqui.' },
    ],
  },
  {
    name: 'SUPORTE', emoji: '🛟',
    channels: [
      { name: 'ajuda', emoji: '🙏', kind: 'forum', topic: 'Problemas a entrar, a instalar conteúdo ou com o jogo. Um tópico por problema.',
        tags: ['Instalação', 'Servidor', 'App', 'Resolvido'] },
      { name: 'bugs-da-app', emoji: '🐞', topic: 'Algo estranho na app de julgamento? Conta o que aconteceu, com print se possível.' },
    ],
  },
  {
    name: 'VOZ', emoji: '🔊',
    channels: [
      { name: 'Lobby', emoji: '🛋️', kind: 'voice' },
      { name: 'Tandem 1', emoji: '🏎️', kind: 'voice', userLimit: 4 },
      { name: 'Tandem 2', emoji: '🏎️', kind: 'voice', userLimit: 4 },
      { name: 'Tandem 3', emoji: '🏎️', kind: 'voice', userLimit: 4 },
      { name: 'Treino e Dicas', emoji: '🎓', kind: 'voice' },
      { name: 'A Ver Lives', emoji: '📺', kind: 'voice' },
      { name: 'Conversa', emoji: '☕', kind: 'voice' },
      { name: 'AFK', emoji: '💤', kind: 'voice', afk: true },
    ],
  },
  {
    name: 'EVENTOS AO VIVO', emoji: '🎙️',
    channels: [
      { name: 'Palco do Evento', emoji: '🎙️', kind: 'stage', topic: 'Briefing, apresentação dos pilotos e entrega de prémios.' },
      { name: 'Pilotos em Pista', emoji: '🏁', kind: 'voice' },
      { name: 'Comentadores', emoji: '🎧', kind: 'voice', userLimit: 4 },
      { name: 'Juízes', emoji: '⚖️', kind: 'voice', staffOnly: true },
    ],
  },
  {
    name: 'STAFF', emoji: '🔒',
    staffOnly: true,
    channels: [
      { name: 'staff-geral', emoji: '💬', topic: 'Conversa da equipa.' },
      { name: 'avisos-do-discord', emoji: '📨', topic: 'Avisos que o Discord envia aos admins de servidores Comunidade.', updatesChannel: true },
      { name: 'decisões-dos-juízes', emoji: '⚖️', topic: 'Revisões de runs e decisões tomadas, para ficar registado.' },
      { name: 'moderação', emoji: '🛡️', topic: 'Avisos, kicks e bans — com o motivo.' },
      { name: 'layouts-em-preparação', emoji: '📐', topic: 'Pistas novas a preparar no editor antes de publicar.' },
      { name: 'organização-de-eventos', emoji: '📋', topic: 'Planeamento de eventos: datas, formato, prémios.' },
      { name: 'Reunião da Staff', emoji: '🗣️', kind: 'voice' },
    ],
  },
];

// Fixed messages, posted by the bot. Keyed by channel name; <#name> becomes a channel link.
export const MESSAGES = {
  'boas-vindas': [{
    title: 'Bem-vindo à DriftFactory',
    color: LIME,
    description: [
      'Comunidade portuguesa de drift em Assetto Corsa: servidor sempre aberto, julgamento automático das runs, classificação semanal e eventos.',
      '',
      '**Começa por aqui**',
      '• <#regras> — lê antes de entrar em pista',
      '• <#como-entrar> — o que precisas e o link do servidor',
      '• <#guia-para-novatos> — nunca fizeste drift? começa aqui',
      '• <#apresentações> — diz olá à comunidade',
      '',
      '**Em pista**',
      '• <#estado-servidores> — que pista está a correr e quem está ligado',
      '• <#classificação> — a classificação da semana',
      '• <#calendário> — os próximos eventos',
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
      '3. Cada coisa no seu canal — ajuda em <#ajuda>, clips em <#clips-e-fotos>.',
      '4. Os admins e moderadores têm a última palavra.',
      '',
      '**No servidor**',
      '5. O drift faz-se num só sentido. Nada de contramão.',
      '6. Não bates de propósito. Em tandem, combina antes.',
      '7. Se rodares ou parares, sai da linha para não estragar a run dos outros.',
      '8. Nome no jogo = nome reconhecível aqui, para a classificação fazer sentido.',
      '',
      '**A run fica inválida se**',
      '• arrancares antes do fim da contagem',
      '• andares em contramão',
      '• endireitares o carro depois de começar o drift',
      '• saíres da pista com as quatro rodas',
      '• parares o carro, ou fizeres um trompo',
      '',
      'Problema com alguém? Fala com um <@&Moderador> por mensagem privada.',
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
      'A janela da app abre-se no menu de extras online do chat do CSP (ícone da lâmpada). A classificação aparece no canto superior direito.',
      '',
      'Problemas? Abre um tópico em <#ajuda>.',
    ].join('\n'),
  }],
  'faq': [{
    title: 'Perguntas frequentes',
    color: LIME,
    description: [
      '**Não vejo o círculo de partida.**',
      'Confirma que tens o CSP atualizado e que estás numa pista com layout oficial (<#layouts>).',
      '',
      '**A minha run ficou inválida e não percebi porquê.**',
      'O motivo aparece no HUD no fim da run. As regras estão em <#regras>.',
      '',
      '**Como funciona a pontuação?**',
      'Até 100 pontos: linha (35), ângulo (35) e estilo/velocidade (30). Passar nas zonas exteriores e nos clips conta para a linha.',
      '',
      '**Quando reinicia a classificação?**',
      'Todas as segundas-feiras às 00:00 (hora de Lisboa). As semanas anteriores ficam em <#classificação> e o vencedor vai para <#hall-da-fama>.',
      '',
      '**Posso sugerir uma pista ou um carro?**',
      'Claro — abre um tópico em <#sugestões>.',
    ].join('\n'),
  }],
  'cargos': [{
    title: 'Cargos',
    color: LIME,
    description: [
      '<@&Admin> — gere o servidor e a comunidade.',
      '<@&Moderador> — mantém o Discord e o servidor em ordem.',
      '<@&Juiz> — revê runs e decide em caso de dúvida.',
      '<@&Organizador de Eventos> — prepara os eventos e as batalhas de tandem.',
      '<@&Campeão da Semana> — quem venceu a última semana. Passa ao próximo vencedor.',
      '<@&Criador de Conteúdo> — faz lives, vídeos ou skins para a comunidade. Pede a um admin.',
      '<@&Piloto Real> — também faz drift na vida real. Pede a um admin.',
    ].join('\n'),
  }],
  'atualizações-da-app': [{
    title: 'App de julgamento — o que há de novo',
    color: LIME,
    description: [
      '• Entregue pelo servidor: entras e já tens a app, sem instalar nada.',
      '• Guia no ecrã antes de cada run e classificação no canto superior direito.',
      '• Runs inválidas por partida antecipada, contramão, endireitar, sair da pista e parar.',
      '• Resultados guardados no servidor e classificação semanal aqui no Discord.',
    ].join('\n'),
  }],
  'hall-da-fama': [{
    title: 'Hall da Fama',
    color: 0xffd34d,
    description: 'Aqui ficam os campeões de cada semana e os grandes momentos da comunidade. O primeiro nome ainda está por escrever.',
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
  'calendário': [{
    title: 'Calendário',
    color: LIME,
    description: [
      'Ainda não há eventos marcados.',
      '',
      'Os eventos são anunciados aqui, com inscrições em <#inscrições>. Durante o evento usamos o <#Palco do Evento> e as salas de voz da categoria **EVENTOS AO VIVO**.',
    ].join('\n'),
  }],
  'resultados': [{
    title: 'Resultados dos eventos',
    color: LIME,
    description: 'Os resultados e as chaves de cada evento ficam publicados aqui.',
  }],
  'guia-para-novatos': [{
    title: 'Guia para novatos',
    color: LIME,
    description: [
      '**1. Prepara o jogo**',
      'Volante com 900° de rotação, sem ajudas de tração (TC e ABS desligados) e caixa manual se conseguires. Ver <#mods-recomendados>.',
      '',
      '**2. Treina offline**',
      'Num parque ou numa pista larga: inicia o drift com o travão de mão ou com um golpe de volante, segura o ângulo com o acelerador e corrige com contra-volta.',
      '',
      '**3. Entra no servidor**',
      'Segue <#como-entrar>. Faz runs, mesmo que fiquem inválidas — o HUD diz-te porquê.',
      '',
      '**4. Pede opinião**',
      'Grava uma run e abre um tópico em <#pedir-feedback>. A malta ajuda.',
      '',
      'Dúvidas de técnica: <#técnica-e-dicas> e a sala de voz **Treino e Dicas**.',
    ].join('\n'),
  }],
  'carros': [{
    title: 'Carros',
    color: LIME,
    description: [
      '**DriftFactory Nissan GT-R** (`driftfactory_nissan_gtr`)',
      `[⬇️ Download (Google Drive)](${CAR_DOWNLOAD_URL})`,
      '',
      'Instala: arrasta o `.rar` para a janela do Content Manager e confirma, ou extrai a pasta para `assettocorsa/content/cars`.',
    ].join('\n'),
  }],
  'pistas': [{
    title: 'Pistas',
    color: LIME,
    description: [
      '**VDC Mondello 2022** (`vdc_mondello_2022`)',
      `[⬇️ Download (Google Drive)](${TRACK_DOWNLOAD_URL})`,
      '',
      'Instala: arrasta o `.rar` para a janela do Content Manager e confirma, ou extrai a pasta para `assettocorsa/content/tracks`.',
    ].join('\n'),
  }],
  'mods-recomendados': [{
    title: 'Mods recomendados',
    color: LIME,
    description: [
      '**Obrigatório**',
      '• **Content Manager** — https://acstuff.ru/app/',
      '• **Custom Shaders Patch (CSP)** — instala-se e atualiza-se a partir do Content Manager (Definições → Custom Shaders Patch)',
      '',
      '**Recomendado**',
      '• Um mod de luz e tempo (Pure ou Sol) para o jogo ficar com outro aspeto',
      '',
      'Dúvidas a instalar? Abre um tópico em <#ajuda>.',
    ].join('\n'),
  }],
};
