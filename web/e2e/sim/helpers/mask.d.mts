import type { Page } from '@playwright/test'
export const SECRET_SELECTOR: string
export const MASK: string
export function maskSecrets(page: Page): Promise<number>
