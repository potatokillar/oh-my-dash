// localStorage 持久化：设备列表、本地会话注册表（本地数值 id ↔ 远端 sessionId）、
// 每会话模型选择缓存。对齐 dsh_mobile/lib/device_store.dart 的角色。

const DEVICES_KEY = "dsh.devices";
const SESSIONS_KEY = "dsh.sessions";
const MODELS_KEY = "dsh.sessionModels";

// ---- 设备 ----

export interface StoredDevice {
  id: number; // 数值自增 id
  name: string;
  address: string; // http(s)://host:port
  kind: "builtin" | "remote";
  createdAt: string; // ISO-8601
}

function read<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    if (raw == null) return fallback;
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

function write(key: string, value: unknown): void {
  localStorage.setItem(key, JSON.stringify(value));
}

export function loadDevices(): StoredDevice[] {
  const list = read<StoredDevice[]>(DEVICES_KEY, []);
  return Array.isArray(list) ? list : [];
}

export function saveDevices(devices: StoredDevice[]): void {
  write(DEVICES_KEY, devices);
}

export function addDevice(name: string, address: string): StoredDevice {
  const devices = loadDevices();
  const id = devices.reduce((m, d) => Math.max(m, d.id), 0) + 1;
  const device: StoredDevice = {
    id,
    name: name.trim(),
    address: address.trim(),
    kind: "remote",
    createdAt: new Date().toISOString(),
  };
  saveDevices([...devices, device]);
  return device;
}

export function getDevice(id: number): StoredDevice | undefined {
  return loadDevices().find((d) => d.id === id);
}

// ---- 会话注册表：本地数值 id ↔ (deviceId, 远端 sessionId) ----

export interface SessionBinding {
  id: number; // 本地数值 id
  deviceId: number;
  remoteId: string; // dsh sessionId
  createdAt: string; // ISO-8601（远端不提供创建时间，以首次登记时间为准）
}

function loadBindings(): SessionBinding[] {
  const list = read<SessionBinding[]>(SESSIONS_KEY, []);
  return Array.isArray(list) ? list : [];
}

function saveBindings(list: SessionBinding[]): void {
  write(SESSIONS_KEY, list);
}

/** 找到或登记 (deviceId, remoteId) 的本地数值 id（幂等） */
export function bindSession(deviceId: number, remoteId: string): SessionBinding {
  const list = loadBindings();
  const hit = list.find((b) => b.deviceId === deviceId && b.remoteId === remoteId);
  if (hit) return hit;
  const binding: SessionBinding = {
    id: list.reduce((m, b) => Math.max(m, b.id), 0) + 1,
    deviceId,
    remoteId,
    createdAt: new Date().toISOString(),
  };
  saveBindings([...list, binding]);
  return binding;
}

export function resolveSession(id: number): SessionBinding | undefined {
  return loadBindings().find((b) => b.id === id);
}

/** 设备删除时清理其会话登记与模型缓存 */
export function dropDeviceState(deviceId: number): void {
  const dropped = loadBindings().filter((b) => b.deviceId === deviceId);
  saveBindings(loadBindings().filter((b) => b.deviceId !== deviceId));
  const models = loadModelCache();
  for (const b of dropped) delete models[`${b.deviceId}:${b.remoteId}`];
  write(MODELS_KEY, models);
}

// ---- 每会话模型选择缓存（dsh 的 session.list 不带模型信息，聊过/切过才知道） ----

export interface CachedModelSelection {
  provider: string;
  model: string;
  effort: string;
}

function loadModelCache(): Record<string, CachedModelSelection> {
  const m = read<Record<string, CachedModelSelection>>(MODELS_KEY, {});
  return m && typeof m === "object" ? m : {};
}

export function getCachedModel(deviceId: number, remoteId: string): CachedModelSelection | undefined {
  return loadModelCache()[`${deviceId}:${remoteId}`];
}

export function setCachedModel(
  deviceId: number,
  remoteId: string,
  sel: CachedModelSelection,
): void {
  const m = loadModelCache();
  m[`${deviceId}:${remoteId}`] = sel;
  write(MODELS_KEY, m);
}
