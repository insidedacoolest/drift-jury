// Builds the DriftFactory Discord server from content.mjs: roles, categories,
// channels with permissions, the bot's fixed messages and the webhooks the
// server plugin posts to. Safe to re-run — it reuses what already exists.
//
//   node discord-setup/setup.mjs
//
// Reads the bot token from dist/discord/token.txt (never printed). Writes
// the webhook URLs, which are secrets, only to dist/discord/pitlane-config.yml,
// ready to paste into the plugin configuration — they are never printed either.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ROLES, CATEGORIES, MESSAGES } from './content.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(repo, 'dist', 'discord');
const statePath = path.join(outDir, 'state.json');
const API = 'https://discord.com/api/v10';

const VIEW = 1n << 10n, SEND = 1n << 11n, ADD_REACTIONS = 1n << 6n;
const SEND_IN_THREADS = 1n << 38n, CREATE_PUBLIC_THREADS = 1n << 35n, ADMINISTRATOR = 1n << 3n;
const GUILD_TEXT = 0, GUILD_VOICE = 2, GUILD_CATEGORY = 4;

const token = fs.readFileSync(path.join(outDir, 'token.txt'), 'utf8').trim();
const state = fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : { messages: {} };
const saveState = () => fs.writeFileSync(statePath, JSON.stringify(state, null, 2));

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
const guild = guilds[0];
console.log(`Bot ${me.username} → server "${guild.name}"`);

// Roles ---------------------------------------------------------------------
let roles = await api('GET', `/guilds/${guild.id}/roles`);
const everyone = roles.find(role => role.id === guild.id);
const roleIds = {};
for (const spec of ROLES) {
  let role = roles.find(r => r.name === spec.name);
  const body = { name: spec.name, color: spec.color, hoist: spec.hoist, mentionable: true,
    permissions: String(spec.admin ? ADMINISTRATOR : BigInt(everyone.permissions)) };
  role = role
    ? await api('PATCH', `/guilds/${guild.id}/roles/${role.id}`, body)
    : await api('POST', `/guilds/${guild.id}/roles`, body);
  roleIds[spec.name] = role.id;
  console.log(`role ${spec.name}`);
}

// Channels --------------------------------------------------------------------
let channels = await api('GET', `/guilds/${guild.id}/channels`);
const channelIds = {};

function readOnlyOverwrites() {
  return [
    { id: guild.id, type: 0, allow: String(VIEW | ADD_REACTIONS), deny: String(SEND | CREATE_PUBLIC_THREADS | SEND_IN_THREADS) },
    { id: roleIds.Admin, type: 0, allow: String(SEND), deny: '0' },
  ];
}

async function ensureChannel(name, type, parentId, extra = {}) {
  const existing = channels.find(c => c.name === name && c.type === type && (c.parent_id ?? null) === (parentId ?? null));
  const body = { name, parent_id: parentId, ...extra };
  const channel = existing
    ? await api('PATCH', `/channels/${existing.id}`, body)
    : await api('POST', `/guilds/${guild.id}/channels`, { ...body, type });
  if (!existing) channels.push(channel);
  return channel;
}

for (const [position, category] of CATEGORIES.entries()) {
  const parent = await ensureChannel(category.name, GUILD_CATEGORY, null, { position });
  for (const [index, spec] of (category.channels ?? []).entries()) {
    const channel = await ensureChannel(spec.name, GUILD_TEXT, parent.id, {
      topic: spec.topic, position: index,
      permission_overwrites: spec.readOnly ? readOnlyOverwrites() : [],
    });
    channelIds[spec.name] = channel.id;
    console.log(`#${spec.name}`);
  }
  for (const [index, name] of (category.voice ?? []).entries()) {
    await ensureChannel(name, GUILD_VOICE, parent.id, { position: index });
    console.log(`🔊 ${name}`);
  }
}

// New members land in #boas-vindas.
await api('PATCH', `/guilds/${guild.id}`, { system_channel_id: channelIds['boas-vindas'] });

// Fixed messages --------------------------------------------------------------
const linkChannels = text => text.replace(/<#([^>\d][^>]*)>/g, (match, name) =>
  channelIds[name] ? `<#${channelIds[name]}>` : match);

for (const [channelName, embeds] of Object.entries(MESSAGES)) {
  const channelId = channelIds[channelName];
  const payload = { embeds: embeds.map(embed => ({ ...embed, description: linkChannels(embed.description) })) };
  const known = state.messages[channelName];
  let message = null;
  if (known) {
    message = await api('PATCH', `/channels/${channelId}/messages/${known}`, payload).catch(() => null);
  }
  message ??= await api('POST', `/channels/${channelId}/messages`, payload);
  state.messages[channelName] = message.id;
  saveState();
  console.log(`message in #${channelName}`);
}

// Webhooks for the server plugin ----------------------------------------------
const config = {};
for (const category of CATEGORIES) {
  for (const spec of category.channels ?? []) {
    if (!spec.webhook) continue;
    const channelId = channelIds[spec.name];
    const hooks = await api('GET', `/channels/${channelId}/webhooks`);
    const hook = hooks.find(h => h.name === 'DriftFactory' && h.user?.id === me.id)
      ?? await api('POST', `/channels/${channelId}/webhooks`, { name: 'DriftFactory' });
    config[spec.webhook] = `https://discord.com/api/webhooks/${hook.id}/${hook.token}`;
    console.log(`webhook for #${spec.name}`);
  }
}

const yaml = [
  `StatusWebhookUrl: ${config.StatusWebhookUrl}`,
  `LeaderboardWebhookUrl: ${config.LeaderboardWebhookUrl}`,
  `RunsWebhookUrl: ${config.RunsWebhookUrl}`,
  'JoinUrl: https://acstuff.ru/s/q:race/online/join?ip=45.131.108.170&httpPort=9055',
  '',
].join('\n');
fs.writeFileSync(path.join(outDir, 'pitlane-config.yml'), yaml);
console.log('Plugin configuration written to dist/discord/pitlane-config.yml (contains secrets).');
