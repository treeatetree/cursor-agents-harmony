/** FeralUI Flow 波浪色板：https://feralui.dev/gradients-gallery-waves */

export const AVATAR_IDS: string[] = [
  'iridescent',
  'opal',
  'lagoon',
  'emerald',
  'solar',
  'orchid',
  'peach',
  'tide',
  'sunset',
  'mint',
  'midnight',
  'rose'
];

export function normalizeAvatarId(id: string): string {
  if (id === 'custom') {
    return 'custom';
  }
  for (let i = 0; i < AVATAR_IDS.length; i++) {
    if (AVATAR_IDS[i] === id) {
      return id;
    }
  }
  return 'iridescent';
}

export function avatarLabel(id: string): string {
  const k = normalizeAvatarId(id);
  if (k === 'opal') {
    return '蛋白石';
  }
  if (k === 'lagoon') {
    return '潟湖';
  }
  if (k === 'emerald') {
    return '翡翠';
  }
  if (k === 'solar') {
    return '日焰';
  }
  if (k === 'orchid') {
    return '兰';
  }
  if (k === 'peach') {
    return '桃光';
  }
  if (k === 'tide') {
    return '电潮';
  }
  if (k === 'sunset') {
    return '日落';
  }
  if (k === 'mint') {
    return '薄荷';
  }
  if (k === 'midnight') {
    return '夜开';
  }
  if (k === 'rose') {
    return '玫瑰金';
  }
  if (k === 'custom') {
    return '相册';
  }
  return '虹云';
}
