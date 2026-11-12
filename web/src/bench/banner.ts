import { interact } from '../init';
import { locale } from '../locale';
import { nui } from '../nui';

export interface BannerType {
  name: string;
  label: string;
}

const WIDTH = 1024;
const HEIGHT = 256;

function roundedRect(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, radius: number) {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + width, y, x + width, y + height, radius);
  ctx.arcTo(x + width, y + height, x, y + height, radius);
  ctx.arcTo(x, y + height, x, y, radius);
  ctx.arcTo(x, y, x + width, y, radius);
  ctx.closePath();
  ctx.fill();
}

function drawBanner(label: string) {
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');

  if (!ctx) return null;

  canvas.width = WIDTH;
  canvas.height = HEIGHT;

  const fill = ctx.createLinearGradient(0, 0, WIDTH, 0);

  fill.addColorStop(0, '#1f56cf');
  fill.addColorStop(1, '#2f7bff');
  ctx.fillStyle = fill;
  roundedRect(ctx, 0, 0, WIDTH, HEIGHT, 10);

  ctx.fillStyle = 'rgba(255, 255, 255, 0.75)';
  ctx.font = '600 40px Montserrat';
  ctx.textBaseline = 'alphabetic';
  ctx.fillText(label.toUpperCase(), 66, 92);

  ctx.fillStyle = '#fff';
  ctx.font = '800 104px Montserrat';
  ctx.fillText(locale('ui_crafting').toUpperCase(), 60, 196, 780);

  if (interact.showKey) {
    ctx.fillStyle = '#fff';
    roundedRect(ctx, 884, 84, 76, 76, 8);

    ctx.fillStyle = '#1f56cf';
    ctx.font = '700 44px Montserrat';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(interact.key, 922, 124, 68);

    ctx.fillStyle = 'rgba(255, 255, 255, 0.85)';
    ctx.font = '600 26px Montserrat';
    ctx.fillText(locale('ui_open').toUpperCase(), 922, 196);
  }

  return canvas.toDataURL('image/png');
}

export async function renderBanners(types: BannerType[]) {
  await Promise.all([
    document.fonts.load('800 104px Montserrat'),
    document.fonts.load('600 40px Montserrat'),
    document.fonts.load('700 44px Montserrat'),
    document.fonts.load('600 26px Montserrat'),
  ]);

  for (const type of types) {
    const image = drawBanner(type.label);

    if (image) {
      nui('banner', { name: type.name, label: type.label, image });
    }
  }
}
