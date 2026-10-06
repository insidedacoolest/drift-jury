// Builds the DriftFactory Discord server from content.mjs: Community mode,
// roles, categories, channels (text, announcement, forum, voice, stage) with
// permissions, the bot's fixed messages and the webhooks the server plugin
// posts to. Safe to re-run — it reuses what already exists.
//
//   node discord-setup/setup.mjs
//
// Reads the bot token from dist/discord/token.txt (never printed). Writes
// the webhook URLs, which are secrets, only to dist/discord/pitlane-config.yml,
// ready to paste into the plugin configuration — they are never printed either.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ROLES, CATEGORIES, MESSAGES, SERVER_JOIN_URL } from './content.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(repo, 'dist', 'discord');
const statePath = path.join(outDir, 'state.json');
const API = 'https://discord.com/api/v10';

const P = {
  KICK: 1n << 1n, BAN: 1n << 2n, ADMINISTRATOR: 1n << 3n, MANAGE_CHANNELS: 1n << 4n, ADD_REACTIONS: 1n << 6n,
  VIEW: 1n << 10n, SEND: 1n << 11n, MANAGE_MESSAGES: 1n << 13n, CONNECT: 1n << 20n, MUTE: 1n << 22n,
  MOVE: 1n << 24n, MANAGE_NICKNAMES: 1n << 27n, MANAGE_EVENTS: 1n << 33n, MANAGE_THREADS: 1n << 34n,
  CREATE_PUBLIC_THREADS: 1n << 35n, SEND_IN_THREADS: 1n << 38n, MODERATE_MEMBERS: 1n << 40n,
};
const TYPE = { text: 0, voice: 2, category: 4, announcement: 5, stage: 13, forum: 15 };
const COMMUNITY_KINDS = new Set(['announcement', 'forum', 'stage']);

const token = fs.readFileSync(path.join(outDir, 'token.txt'), 'utf8').trim();
const state = fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : { messages: {} };
const saveState = () => fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
const str = bits => String(bits);

async function api(method, route, body) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const response = await fetch(API + route, {
      method,
      headers: { Authorization: `Bot ${token}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.status === 429) {
      const { retry_after } = await response.json();
      await new Promise(resolve => setTimeout(resolve, (retry_after ?? 1) * 1000 + 100));
      continue;
    }
    if (!response.ok) {
      throw new Error(`${method} ${route} → ${response.status} ${await response.text()}`);
    }
    return response.status === 204 ? null : response.json();
  }
  throw new Error(`${method} ${route} → still rate limited`);
}

const me = await api('GET', '/users/@me');
const guilds = await api('GET', '/users/@me/guilds');
if (guilds.length !== 1) {
  throw new Error(`The bot must be in exactly one server (it is in ${guilds.length}): ${guilds.map(g => g.name).join(', ')}`);
}
let guild = await api('GET', `/guilds/${guilds[0].id}`);
console.log(`Bot ${me.username} → server "${guild.name}"`);

// Roles ---------------------------------------------------------------------
const roles = await api('GET', `/guilds/${guild.id}/roles`);
const everyone = roles.find(role => role.id === guild.id);
const basePermissions = BigInt(everyone.permissions);
const roleIds = {};
for (const spec of ROLES) {
  let permissions = basePermissions;
  if (spec.admin) permissions = P.ADMINISTRATOR;
  if (spec.moderate) {
    permissions |= P.KICK | P.BAN | P.MANAGE_MESSAGES | P.MANAGE_THREADS | P.MODERATE_MEMBERS
      | P.MUTE | P.MOVE | P.MANAGE_NICKNAMES | P.MANAGE_EVENTS;
  }
  if (spec.name === 'Organizador de Eventos') permissions |= P.MANAGE_EVENTS | P.MUTE | P.MOVE;
  const body = { name: spec.name, color: spec.color, hoist: spec.hoist, mentionable: true, permissions: str(permissions) };
  const existing = roles.find(r => r.name === spec.name);
  const role = existing
    ? await api('PATCH', `/guilds/${guild.id}/roles/${existing.id}`, body)
    : await api('POST', `/guilds/${guild.id}/roles`, body);
  roleIds[spec.name] = role.id;
  console.log(`role ${spec.name}`);
}
// Keep the role list in the order of ROLES, just under the bot's own role.
const botMember = await api('GET', `/guilds/${guild.id}/members/${me.id}`);
const botTop = Math.max(...roles.filter(r => botMember.roles.includes(r.id)).map(r => r.position));
await api('PATCH', `/guilds/${guild.id}/roles`, ROLES.map((spec, index) => ({
  id: roleIds[spec.name], position: Math.max(1, botTop - 1 - index),
}))).catch(error => console.warn(`could not reorder roles: ${error.message}`));
const staffRoleIds = ROLES.filter(spec => spec.staff).map(spec => roleIds[spec.name]);

// Permissions ---------------------------------------------------------------
const readOnly = () => [
  { id: guild.id, type: 0, allow: str(P.VIEW | P.ADD_REACTIONS), deny: str(P.SEND | P.CREATE_PUBLIC_THREADS | P.SEND_IN_THREADS) },
  ...staffRoleIds.map(id => ({ id, type: 0, allow: str(P.SEND), deny: '0' })),
];
const staffOnly = () => [
  { id: guild.id, type: 0, allow: '0', deny: str(P.VIEW | P.CONNECT) },
  ...staffRoleIds.map(id => ({ id, type: 0, allow: str(P.VIEW | P.SEND | P.CONNECT), deny: '0' })),
];
const stageModerators = () => ['Admin', 'Moderador', 'Organizador de Eventos'].map(name => ({
  id: roleIds[name], type: 0, allow: str(P.MANAGE_CHANNELS | P.MUTE | P.MOVE), deny: '0',
}));

function overwritesFor(spec, category) {
  if (category.staffOnly || spec.staffOnly) return staffOnly();
  if (spec.kind === 'stage') return stageModerators();
  return spec.readOnly ? readOnly() : [];
}

// Channels --------------------------------------------------------------------
let channels = await api('GET', `/guilds/${guild.id}/channels`);
const channelIds = {};

async function ensureChannel(name, kind, parentId, extra) {
  const type = TYPE[kind];
  // An existing text channel may become an announcement channel once Community is on.
  const sameFamily = c => c.type === type || (kind === 'announcement' && c.type === TYPE.text);
  const existing = channels.find(c => c.name === name && sameFamily(c) && (c.parent_id ?? null) === (parentId ?? null));
  const body = { name, parent_id: parentId, ...extra };
  if (existing && existing.type !== type) body.type = type;
  const channel = existing
    ? await api('PATCH', `/channels/${existing.id}`, body)
    : await api('POST', `/guilds/${guild.id}/channels`, { ...body, type });
  if (!existing) channels.push(channel);
  return channel;
}

async function buildChannels(onlyBasic) {
  for (const [position, category] of CATEGORIES.entries()) {
    const parent = await ensureChannel(category.name, 'category', null, {
      position, permission_overwrites: category.staffOnly ? staffOnly() : [],
    });
    for (const [index, spec] of category.channels.entries()) {
      const kind = spec.kind ?? 'text';
      if (onlyBasic && COMMUNITY_KINDS.has(kind)) continue;
      const extra = { position: index, permission_overwrites: overwritesFor(spec, category) };
      if (spec.topic && kind !== 'voice' && kind !== 'stage') extra.topic = spec.topic;
      if (spec.userLimit) extra.user_limit = spec.userLimit;
      if (kind === 'forum' && spec.tags) {
        const existing = channels.find(c => c.name === spec.name && c.type === TYPE.forum);
        const known = existing?.available_tags ?? [];
        extra.available_tags = spec.tags.map(name => known.find(tag => tag.name === name) ?? { name });
      }
      const channel = await ensureChannel(spec.name, kind, parent.id, extra);
      channelIds[spec.name] = channel.id;
      if (!onlyBasic) console.log(`${kind.padEnd(12)} ${spec.name}`);
    }
  }
}

// Text and voice first: Community mode needs the rules and updates channels to exist.
await buildChannels(true);

const updatesChannel = CATEGORIES.flatMap(c => c.channels).find(c => c.updatesChannel).name;
const afkChannel = CATEGORIES.flatMap(c => c.channels).find(c => c.afk).name;
guild = await api('PATCH', `/guilds/${guild.id}`, {
  features: [...new Set([...(guild.features ?? []), 'COMMUNITY'])],
  verification_level: Math.max(guild.verification_level ?? 0, 1),
  explicit_content_filter: 2,
  default_message_notifications: 1,
  rules_channel_id: channelIds['regras'],
  public_updates_channel_id: channelIds[updatesChannel],
  system_channel_id: channelIds['boas-vindas'],
  afk_channel_id: channelIds[afkChannel],
  afk_timeout: 900,
});
console.log(`Community mode: ${guild.features.includes('COMMUNITY') ? 'on' : 'off'}`);

await buildChannels(false);

// Fixed messages --------------------------------------------------------------
const linkify = text => text
  .replace(/<@&([^>\d][^>]*)>/g, (match, name) => roleIds[name] ? `<@&${roleIds[name]}>` : match)
  .replace(/<#([^>\d][^>]*)>/g, (match, name) => channelIds[name] ? `<#${channelIds[name]}>` : match);

for (const [channelName, embeds] of Object.entries(MESSAGES)) {
  const channelId = channelIds[channelName];
  const payload = {
    embeds: embeds.map(embed => ({ ...embed, description: linkify(embed.description) })),
    allowed_mentions: { parse: [] }, // links to roles, without pinging anyone
  };
  const known = state.messages[channelName];
  let message = null;
  if (known) {
    message = await api('PATCH', `/channels/${channelId}/messages/${known}`, payload).catch(() => null);
  }
  message ??= await api('POST', `/channels/${channelId}/messages`, payload);
  state.messages[channelName] = message.id;
  saveState();
  console.log(`message      #${channelName}`);
}

// Webhooks for the server plugin ----------------------------------------------
const config = {};
for (const spec of CATEGORIES.flatMap(c => c.channels)) {
  if (!spec.webhook) continue;
  const channelId = channelIds[spec.name];
  const hooks = await api('GET', `/channels/${channelId}/webhooks`);
  const hook = hooks.find(h => h.name === 'DriftFactory' && h.user?.id === me.id)
    ?? await api('POST', `/channels/${channelId}/webhooks`, { name: 'DriftFactory' });
  config[spec.webhook] = `https://discord.com/api/webhooks/${hook.id}/${hook.token}`;
  console.log(`webhook      #${spec.name}`);
}

fs.writeFileSync(path.join(outDir, 'pitlane-config.yml'), [
  `StatusWebhookUrl: ${config.StatusWebhookUrl}`,
  `LeaderboardWebhookUrl: ${config.LeaderboardWebhookUrl}`,
  `RunsWebhookUrl: ${config.RunsWebhookUrl}`,
  `JoinUrl: ${SERVER_JOIN_URL}`,
  '',
].join('\n'));
console.log('Plugin configuration written to dist/discord/pitlane-config.yml (contains secrets).');
